// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - ModbusFrameDecoderError

/// Errors from ModbusFrameDecoder.
///
/// These indicate protocol violations that cannot be recovered from.
/// Reference: goburrow/modbus and pymodbus do not attempt resync on corrupt frames.
enum ModbusFrameDecoderError: Error, Equatable, Sendable {
    /// Protocol ID is not 0x0000 (Modbus TCP requires protocol ID = 0)
    case invalidProtocolId(UInt16)

    /// Length field is invalid (0 or exceeds maximum)
    case invalidLength(UInt16)

    /// Frame exceeds maximum ADU size (260 bytes)
    case frameTooLarge(Int)

    /// Connection closed with incomplete frame in buffer.
    /// This indicates the server closed mid-transmission or a network issue.
    /// The associated value is the number of bytes remaining in the buffer.
    case incompleteFrameAtEOF(Int)
}

// MARK: - ModbusFrameDecoder

/// NIO decoder for Modbus TCP frames.
///
/// Accumulates bytes until a complete MBAP frame is received.
/// Validates frame structure before passing to handler.
///
/// **Error Handling:**
/// Invalid frames throw errors rather than attempting resynchronization.
/// This matches goburrow/modbus and pymodbus behavior — Modbus TCP runs over
/// reliable TCP transport, so corrupt frames indicate serious issues
/// (implementation bugs, network attacks) that warrant connection closure.
///
/// Reference:
/// - goburrow/modbus: validates in Verify(), no resync
/// - pymodbus: no resync logic, assumes valid framing
final class ModbusFrameDecoder: ByteToMessageDecoder, Sendable {
    typealias InboundOut = [UInt8]

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Need at least MBAP header to determine frame length
        guard buffer.readableBytes >= MBAPConstants.headerSize else {
            return .needMoreData
        }

        // Peek at protocol ID (bytes 2-3, Big Endian) — must be 0x0000
        guard
            let protocolHigh = buffer.getInteger(at: buffer.readerIndex + MBAPOffset.protocolId, as: UInt8.self),
            let protocolLow = buffer.getInteger(at: buffer.readerIndex + MBAPOffset.protocolId + 1, as: UInt8.self) else {
            return .needMoreData
        }

        let protocolId = (UInt16(protocolHigh) << 8) | UInt16(protocolLow)
        guard protocolId == MBAPConstants.protocolId else {
            throw ModbusFrameDecoderError.invalidProtocolId(protocolId)
        }

        // Peek at length field (bytes 4-5, Big Endian)
        guard
            let lengthHigh = buffer.getInteger(at: buffer.readerIndex + MBAPOffset.length, as: UInt8.self),
            let lengthLow = buffer.getInteger(at: buffer.readerIndex + MBAPOffset.length + 1, as: UInt8.self) else
        {
            return .needMoreData
        }

        let length = (UInt16(lengthHigh) << 8) | UInt16(lengthLow)

        // Validate length field: must be >= 1 (at least unit ID) and within limits
        // Max length = 254 (260 max ADU - 7 header + 1 for unit ID included in length)
        let maxLength = UInt16(MBAPConstants.maximumADUSize - MBAPConstants.headerSize + 1)
        guard length >= 1, length <= maxLength else {
            throw ModbusFrameDecoderError.invalidLength(length)
        }

        // Calculate total frame size
        // Length field = Unit ID (1) + PDU length
        // Total frame = MBAP header (7) + PDU length = 7 + length - 1 = 6 + length
        let frameSize = MBAPConstants.headerSize + Int(length) - 1

        // Wait for complete frame
        guard buffer.readableBytes >= frameSize else {
            return .needMoreData
        }

        // Final size validation (should be redundant given length check, but defense in depth)
        guard frameSize <= MBAPConstants.maximumADUSize else {
            throw ModbusFrameDecoderError.frameTooLarge(frameSize)
        }

        // Extract complete frame
        guard let frameBytes = buffer.readBytes(length: frameSize) else {
            return .needMoreData
        }

        context.fireChannelRead(wrapInboundOut(frameBytes))
        return .continue
    }

    /// Handle channel closure or decoder removal.
    ///
    /// For Modbus TCP, any leftover bytes in the buffer when the connection closes
    /// indicates an incomplete frame — this is always an error condition.
    ///
    /// **Security consideration:** We don't attempt to recover or resync from partial frames.
    /// This prevents potential attacks where malicious data could be interpreted incorrectly
    /// after connection issues.
    ///
    /// Reference: goburrow/modbus closes connection on any frame error, pymodbus same behavior.
    func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF _: Bool,
    ) throws -> DecodingState {
        // First, try to decode any complete frames still in the buffer
        while buffer.readableBytes > 0 {
            let result = try decode(context: context, buffer: &buffer)
            if result == .needMoreData {
                break
            }
        }

        // If there's still data left after decoding complete frames, it's a partial frame
        if buffer.readableBytes > 0 {
            // Connection closed (EOF) or decoder removed with incomplete data
            // This is an error — Modbus TCP frames must be complete
            throw ModbusFrameDecoderError.incompleteFrameAtEOF(buffer.readableBytes)
        }

        return .needMoreData
    }
}
