// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ModbusFrameDecoder Tests (Tier 1: EmbeddedChannel)

/// Tests for ModbusFrameDecoder using EmbeddedChannel.
///
/// These tests validate frame accumulation, parsing, and error handling
/// without real network I/O — fast, deterministic, parallel-safe.
///
/// Reference: SwiftNIO ByteToMessageDecoder testing patterns
@Suite("Modbus Frame Decoder")
struct FrameDecoderTests {
    // MARK: Internal

    // MARK: - Frame Accumulation Tests

    @Test("Complete frame is decoded immediately")
    func completeFrameDecoded() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Build a read holding registers response: FC=0x03, byte count=4, data=[0x00,0x01,0x00,0x02]
        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]
        let frame = buildFrame(transactionId: 0x0001, unitId: 1, pdu: pdu)

        // Write complete frame
        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)

        // Should produce exactly one decoded frame
        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)

        // No more frames
        #expect(try channel.readInbound(as: [UInt8].self) == nil)
    }

    @Test("Partial frame waits for more data")
    func partialFrameWaits() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]
        let frame = buildFrame(pdu: pdu)

        // Write only first 5 bytes (partial MBAP header)
        var buffer1 = channel.allocator.buffer(capacity: 5)
        buffer1.writeBytes(Array(frame[0 ..< 5]))
        try channel.writeInbound(buffer1)

        // No frame decoded yet
        #expect(try channel.readInbound(as: [UInt8].self) == nil)

        // Write remaining bytes
        var buffer2 = channel.allocator.buffer(capacity: frame.count - 5)
        buffer2.writeBytes(Array(frame[5...]))
        try channel.writeInbound(buffer2)

        // Now frame should be decoded
        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)
    }

    @Test("Frame split at MBAP header boundary")
    func frameSplitAtHeaderBoundary() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let pdu: [UInt8] = [0x03, 0x02, 0xAB, 0xCD]
        let frame = buildFrame(pdu: pdu)

        // Write exactly MBAP header (7 bytes)
        var buffer1 = channel.allocator.buffer(capacity: MBAPConstants.headerSize)
        buffer1.writeBytes(Array(frame[0 ..< MBAPConstants.headerSize]))
        try channel.writeInbound(buffer1)

        // No frame yet — need PDU
        #expect(try channel.readInbound(as: [UInt8].self) == nil)

        // Write PDU
        var buffer2 = channel.allocator.buffer(capacity: pdu.count)
        buffer2.writeBytes(Array(frame[MBAPConstants.headerSize...]))
        try channel.writeInbound(buffer2)

        // Now complete
        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)
    }

    @Test("Multiple frames in single buffer")
    func multipleFramesInBuffer() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let pdu1: [UInt8] = [0x03, 0x02, 0x00, 0x01]
        let pdu2: [UInt8] = [0x04, 0x02, 0x00, 0x02]
        let frame1 = buildFrame(transactionId: 0x0001, pdu: pdu1)
        let frame2 = buildFrame(transactionId: 0x0002, pdu: pdu2)

        // Write both frames at once
        var buffer = channel.allocator.buffer(capacity: frame1.count + frame2.count)
        buffer.writeBytes(frame1)
        buffer.writeBytes(frame2)
        try channel.writeInbound(buffer)

        // Should decode both frames
        let decoded1 = try channel.readInbound(as: [UInt8].self)
        let decoded2 = try channel.readInbound(as: [UInt8].self)

        #expect(decoded1 == frame1)
        #expect(decoded2 == frame2)
        #expect(try channel.readInbound(as: [UInt8].self) == nil)
    }

    @Test("Byte-by-byte accumulation")
    func byteByByteAccumulation() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let pdu: [UInt8] = [0x03, 0x02, 0x12, 0x34]
        let frame = buildFrame(pdu: pdu)

        // Write one byte at a time
        for (index, byte) in frame.enumerated() {
            var buffer = channel.allocator.buffer(capacity: 1)
            buffer.writeBytes([byte])
            try channel.writeInbound(buffer)

            if index < frame.count - 1 {
                // Not complete yet
                #expect(try channel.readInbound(as: [UInt8].self) == nil)
            }
        }

        // After last byte, frame should be decoded
        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)
    }

    // MARK: - Invalid Frame Error Handling

    @Test("Zero length field throws invalidLength error")
    func zeroLengthThrows() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Invalid frame with length=0
        // Reference: goburrow/modbus rejects length=0, pymodbus expects length >= 1
        let invalidFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID (valid)
            0x00, 0x00, // Length = 0 (invalid)
            0x01, // Unit ID
        ]

        var buffer = channel.allocator.buffer(capacity: invalidFrame.count)
        buffer.writeBytes(invalidFrame)

        // Should throw invalidLength error
        #expect(throws: ModbusFrameDecoderError.invalidLength(0)) {
            try channel.writeInbound(buffer)
        }
    }

    @Test("Excessive length field throws invalidLength error")
    func excessiveLengthThrows() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Invalid frame with length > max (254)
        // Max valid length = 254 (260 max ADU - 7 header + 1)
        let invalidFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID (valid)
            0x01, 0x00, // Length = 256 (invalid, > 254)
            0x01, // Unit ID
        ]

        var buffer = channel.allocator.buffer(capacity: invalidFrame.count)
        buffer.writeBytes(invalidFrame)

        // Should throw invalidLength error
        #expect(throws: ModbusFrameDecoderError.invalidLength(256)) {
            try channel.writeInbound(buffer)
        }
    }

    @Test("Invalid protocol ID throws error")
    func invalidProtocolIdThrows() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Frame with wrong protocol ID (should be 0x0000)
        let invalidFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x01, // Protocol ID = 1 (invalid, must be 0)
            0x00, 0x03, // Length = 3
            0x01, // Unit ID
            0x03, 0x00, // PDU
        ]

        var buffer = channel.allocator.buffer(capacity: invalidFrame.count)
        buffer.writeBytes(invalidFrame)

        // Should throw invalidProtocolId error
        #expect(throws: ModbusFrameDecoderError.invalidProtocolId(1)) {
            try channel.writeInbound(buffer)
        }
    }

    @Test("High protocol ID throws error")
    func highProtocolIdThrows() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Frame with obviously wrong protocol ID
        let invalidFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0xFF, 0xFF, // Protocol ID = 0xFFFF (invalid)
            0x00, 0x03, // Length = 3
            0x01, // Unit ID
            0x03, 0x00, // PDU
        ]

        var buffer = channel.allocator.buffer(capacity: invalidFrame.count)
        buffer.writeBytes(invalidFrame)

        #expect(throws: ModbusFrameDecoderError.invalidProtocolId(0xFFFF)) {
            try channel.writeInbound(buffer)
        }
    }

    // MARK: - Edge Cases

    @Test("Minimum valid frame (FC only)")
    func minimumValidFrame() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Minimum PDU: just function code
        let pdu: [UInt8] = [0x03]
        let frame = buildFrame(pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)

        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)
        #expect(frame.count == MBAPConstants.minimumADUSize)
    }

    @Test("Maximum valid frame size")
    func maximumValidFrame() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Maximum PDU: 253 bytes (260 - 7 header)
        let maxPduSize = MBAPConstants.maximumADUSize - MBAPConstants.headerSize
        var pdu = [UInt8](repeating: 0x00, count: maxPduSize)
        pdu[0] = 0x03 // Function code

        let frame = buildFrame(pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)

        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame)
        #expect(frame.count == MBAPConstants.maximumADUSize)
    }

    @Test("Less than header size waits")
    func lessThanHeaderWaits() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Write only 6 bytes (less than 7-byte header)
        var buffer = channel.allocator.buffer(capacity: 6)
        buffer.writeBytes([0x00, 0x01, 0x00, 0x00, 0x00, 0x02])
        try channel.writeInbound(buffer)

        // Should not decode anything
        #expect(try channel.readInbound(as: [UInt8].self) == nil)
    }

    // MARK: - Transaction ID Variations

    @Test("Various transaction IDs preserved")
    func transactionIdPreserved() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let testIds: [UInt16] = [0x0000, 0x0001, 0x00FF, 0xFF00, 0xFFFF, 0x1234]
        let pdu: [UInt8] = [0x03, 0x02, 0x00, 0x01]

        for txId in testIds {
            let frame = buildFrame(transactionId: txId, pdu: pdu)
            var buffer = channel.allocator.buffer(capacity: frame.count)
            buffer.writeBytes(frame)
            try channel.writeInbound(buffer)

            let decoded = try channel.readInbound(as: [UInt8].self)
            #expect(decoded == frame)

            // Verify transaction ID in decoded frame
            if let decoded {
                let decodedTxId = (UInt16(decoded[0]) << 8) | UInt16(decoded[1])
                #expect(decodedTxId == txId)
            }
        }
    }

    // MARK: - Channel Lifecycle and decodeLast

    @Test("Empty buffer does nothing")
    func emptyBufferNoOp() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let buffer = channel.allocator.buffer(capacity: 0)
        try channel.writeInbound(buffer)

        #expect(try channel.readInbound(as: [UInt8].self) == nil)
    }

    @Test("Partial frame at channel close throws incompleteFrameAtEOF")
    func partialFrameAtCloseThrows() throws {
        let channel = try makeChannel()

        // Write incomplete frame (only partial header)
        let partialFrame: [UInt8] = [0x00, 0x01, 0x00, 0x00, 0x00]
        var buffer = channel.allocator.buffer(capacity: partialFrame.count)
        buffer.writeBytes(partialFrame)
        try channel.writeInbound(buffer)

        // No frame decoded (incomplete)
        #expect(try channel.readInbound(as: [UInt8].self) == nil)

        // Channel close with partial data should throw
        #expect(throws: ModbusFrameDecoderError.incompleteFrameAtEOF(5)) {
            try channel.finish()
        }
    }

    @Test("Partial PDU at channel close throws incompleteFrameAtEOF")
    func partialPduAtCloseThrows() throws {
        let channel = try makeChannel()

        // Write complete header but incomplete PDU
        // MBAP: txId=1, protocolId=0, length=5 (unit + 4 bytes PDU)
        // But we only send header + 2 bytes instead of 4
        let partialFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x05, // Length = 5 (unit ID + 4 bytes PDU)
            0x01, // Unit ID
            0x03, 0x02, // Partial PDU (need 2 more bytes)
        ]
        var buffer = channel.allocator.buffer(capacity: partialFrame.count)
        buffer.writeBytes(partialFrame)
        try channel.writeInbound(buffer)

        // No frame decoded (incomplete)
        #expect(try channel.readInbound(as: [UInt8].self) == nil)

        // Channel close should throw with remaining bytes count
        #expect(throws: ModbusFrameDecoderError.incompleteFrameAtEOF(9)) {
            try channel.finish()
        }
    }

    @Test("Complete frame followed by partial at close decodes first then throws")
    func completeFrameThenPartialThrows() throws {
        let channel = try makeChannel()

        // First: complete frame
        let pdu: [UInt8] = [0x03, 0x02, 0x00, 0x01]
        let completeFrame = buildFrame(transactionId: 0x0001, pdu: pdu)

        // Second: incomplete frame (just transaction ID)
        let partialFrame: [UInt8] = [0x00, 0x02]

        var buffer = channel.allocator.buffer(capacity: completeFrame.count + partialFrame.count)
        buffer.writeBytes(completeFrame)
        buffer.writeBytes(partialFrame)
        try channel.writeInbound(buffer)

        // Complete frame should be decoded
        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == completeFrame)

        // Channel close should throw for partial frame
        #expect(throws: ModbusFrameDecoderError.incompleteFrameAtEOF(2)) {
            try channel.finish()
        }
    }

    @Test("Clean channel close with no buffered data succeeds")
    func cleanCloseSucceeds() throws {
        let channel = try makeChannel()

        // Write and read complete frame
        let pdu: [UInt8] = [0x03, 0x02, 0x00, 0x01]
        let frame = buildFrame(pdu: pdu)
        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
        _ = try channel.readInbound(as: [UInt8].self)

        // Channel close with empty buffer should succeed
        try channel.finish()
    }

    @Test("Channel can be reused after frames")
    func channelReuse() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        let pdu: [UInt8] = [0x03, 0x02, 0x00, 0x01]

        // First frame
        let frame1 = buildFrame(transactionId: 0x0001, pdu: pdu)
        var buffer1 = channel.allocator.buffer(capacity: frame1.count)
        buffer1.writeBytes(frame1)
        try channel.writeInbound(buffer1)
        _ = try channel.readInbound(as: [UInt8].self)

        // Second frame after some time
        let frame2 = buildFrame(transactionId: 0x0002, pdu: pdu)
        var buffer2 = channel.allocator.buffer(capacity: frame2.count)
        buffer2.writeBytes(frame2)
        try channel.writeInbound(buffer2)

        let decoded = try channel.readInbound(as: [UInt8].self)
        #expect(decoded == frame2)
    }

    // MARK: Private

    // MARK: - Helper

    /// Creates an EmbeddedChannel with ModbusFrameDecoder installed.
    private func makeChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(ByteToMessageHandler(ModbusFrameDecoder())).wait()
        return channel
    }

    /// Safely finishes channel, ignoring errors.
    private func finishChannel(_ channel: EmbeddedChannel) {
        _ = try? channel.finish()
    }

    /// Builds a valid Modbus TCP frame for testing.
    ///
    /// - Parameters:
    ///   - transactionId: Transaction ID
    ///   - unitId: Unit identifier
    ///   - pdu: PDU bytes (function code + data)
    /// - Returns: Complete MBAP frame
    private func buildFrame(
        transactionId: UInt16 = 0x0001,
        unitId: UInt8 = 1,
        pdu: [UInt8],
    ) -> [UInt8] {
        buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)
    }
}
