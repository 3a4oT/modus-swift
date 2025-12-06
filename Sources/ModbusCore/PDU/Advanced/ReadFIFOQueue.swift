// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read FIFO Queue Builder

/// Builds a Read FIFO Queue request PDU (Function Code 0x18).
///
/// PDU format (3 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x18)
/// [1-2] FIFO Pointer Address
/// ```
///
/// API based on goburrow/modbus `ReadFIFOQueue`.
///
/// - Parameter address: FIFO pointer address (0-65535)
/// - Returns: 3-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadFIFOQueuePDU(
    address: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.readFIFOQueueRequest)

    // Function code
    pdu.append(ModbusFunctionCode.readFIFOQueue)

    // FIFO pointer address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    return pdu
}

// MARK: - ReadFIFOQueueResponse

/// Parsed response for Read FIFO Queue (0x18).
///
/// Response contains the FIFO count and register values.
/// API based on goburrow/modbus.
public struct ReadFIFOQueueResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(fifoCount: UInt16, registers: [UInt16]) {
        self.fifoCount = fifoCount
        self.registers = registers
    }

    // MARK: Public

    /// FIFO count (number of registers in the FIFO)
    public let fifoCount: UInt16

    /// FIFO register values (each UInt16 in native byte order)
    public let registers: [UInt16]
}

// MARK: - Read FIFO Queue Parser

/// Parses a Read FIFO Queue response PDU (0x18).
///
/// Response PDU format:
/// ```
/// [0]     Function Code (0x18)
/// [1-2]   Byte Count (total bytes following this field)
/// [3-4]   FIFO Count (number of registers, 0-31)
/// [5..]   FIFO Register Data (FIFO Count × 2 bytes, Big Endian)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with FIFO count and registers
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadFIFOQueuePDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> ReadFIFOQueueResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Minimum response: func(1) + byteCount(2) + fifoCount(2) = 5
    guard pdu.count >= 5 else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.readFIFOQueue else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readFIFOQueue,
            got: functionCode,
        )
    }

    // Parse byte count and FIFO count (Big Endian)
    guard
        let byteCount = readUInt16BE(pdu, at: 1),
        let fifoCount = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }

    // Validate byte count matches FIFO count
    // byteCount = 2 (for fifoCount field) + fifoCount * 2 (for register data)
    let expectedByteCount = 2 + (fifoCount * 2)
    guard byteCount == expectedByteCount else {
        throw .byteCountMismatch(expected: UInt8(min(expectedByteCount, 255)), got: UInt8(min(byteCount, 255)))
    }

    // Validate PDU has enough bytes
    let expectedPDUSize = 5 + Int(fifoCount) * 2
    guard pdu.count >= expectedPDUSize else {
        throw .pduTooShort
    }

    // Parse FIFO registers (Big Endian)
    var registers = [UInt16]()
    registers.reserveCapacity(Int(fifoCount))

    for i in 0 ..< Int(fifoCount) {
        let offset = 5 + (i * 2)
        guard let value = readUInt16BE(pdu, at: offset) else {
            throw .pduTooShort
        }
        registers.append(value)
    }

    return ReadFIFOQueueResponse(fifoCount: fifoCount, registers: registers)
}

/// Convenience overload for Array input.
@inlinable
public func parseReadFIFOQueuePDU(
    _ pdu: [UInt8],
) throws(PDUError) -> ReadFIFOQueueResponse {
    try parseReadFIFOQueuePDU(pdu.span)
}
