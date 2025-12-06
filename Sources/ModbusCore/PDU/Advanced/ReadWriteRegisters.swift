// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read/Write Multiple Registers Builder

/// Builds a Read/Write Multiple Registers request PDU (Function Code 0x17).
///
/// PDU format (10 + N×2 bytes, Big Endian):
/// ```
/// [0]     Function Code (0x17)
/// [1-2]   Read Starting Address
/// [3-4]   Quantity to Read (1-125)
/// [5-6]   Write Starting Address
/// [7-8]   Quantity to Write (1-121)
/// [9]     Write Byte Count (N = Quantity × 2)
/// [10..]  Write Values (N bytes)
/// ```
///
/// API based on pymodbus `readwrite_registers(read_address, read_count, write_address, write_registers)`.
///
/// - Parameters:
///   - readAddress: Starting address for read operation
///   - readCount: Number of registers to read (1-125)
///   - writeAddress: Starting address for write operation
///   - writeValues: Values to write (1-121 registers)
/// - Returns: PDU ready for MBAP wrapping
@inlinable
public func buildReadWriteMultipleRegistersPDU(
    readAddress: UInt16,
    readCount: UInt16,
    writeAddress: UInt16,
    writeValues: [UInt16],
) -> [UInt8] {
    let writeQuantity = UInt16(writeValues.count)
    let writeByteCount = UInt8(writeValues.count * 2)

    var pdu = [UInt8]()
    pdu.reserveCapacity(10 + Int(writeByteCount))

    // Function code
    pdu.append(ModbusFunctionCode.readWriteMultipleRegisters)

    // Read starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: readAddress >> 8))
    pdu.append(UInt8(truncatingIfNeeded: readAddress))

    // Quantity to read (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: readCount >> 8))
    pdu.append(UInt8(truncatingIfNeeded: readCount))

    // Write starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: writeAddress >> 8))
    pdu.append(UInt8(truncatingIfNeeded: writeAddress))

    // Quantity to write (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: writeQuantity >> 8))
    pdu.append(UInt8(truncatingIfNeeded: writeQuantity))

    // Write byte count
    pdu.append(writeByteCount)

    // Write values (Big Endian)
    for value in writeValues {
        pdu.append(UInt8(truncatingIfNeeded: value >> 8))
        pdu.append(UInt8(truncatingIfNeeded: value))
    }

    return pdu
}

// MARK: - ReadWriteMultipleRegistersResponse

/// Parsed response for Read/Write Multiple Registers (0x17).
///
/// Response contains only the read register values.
/// API based on pymodbus `ReadWriteMultipleRegistersResponse`.
public struct ReadWriteMultipleRegistersResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(registers: [UInt16]) {
        self.registers = registers
    }

    // MARK: Public

    /// Read register values (each UInt16 in native byte order)
    public let registers: [UInt16]

    /// Number of registers in response
    public var count: Int {
        registers.count
    }
}

// MARK: - Read/Write Multiple Registers Parser

/// Parses a Read/Write Multiple Registers response PDU (0x17).
///
/// Response PDU format:
/// ```
/// [0]   Function Code (0x17)
/// [1]   Byte Count (N)
/// [2..] Read Register Data (N bytes, Big Endian per register)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with read registers
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadWriteMultipleRegistersPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> ReadWriteMultipleRegistersResponse {
    // Validate minimum size
    guard pdu.count >= PDUSize.minimumReadResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        guard pdu.count >= PDUSize.exceptionResponse else {
            throw .pduTooShort
        }
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.readWriteMultipleRegisters else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readWriteMultipleRegisters,
            got: functionCode,
        )
    }

    // Get byte count
    let byteCount = pdu[1]

    // Validate PDU has enough bytes
    let expectedPDUSize = 2 + Int(byteCount)
    guard pdu.count >= expectedPDUSize else {
        throw .pduTooShort
    }

    // Byte count must be even (2 bytes per register)
    guard byteCount % 2 == 0 else {
        throw .byteCountMismatch(expected: byteCount, got: byteCount)
    }

    // Parse registers (Big Endian)
    let registerCount = Int(byteCount) / 2
    var registers = [UInt16]()
    registers.reserveCapacity(registerCount)

    for i in 0 ..< registerCount {
        let offset = 2 + (i * 2)
        guard let value = readUInt16BE(pdu, at: offset) else {
            throw .pduTooShort
        }
        registers.append(value)
    }

    return ReadWriteMultipleRegistersResponse(registers: registers)
}

/// Convenience overload for Array input.
@inlinable
public func parseReadWriteMultipleRegistersPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> ReadWriteMultipleRegistersResponse {
    try parseReadWriteMultipleRegistersPDU(pdu.span)
}
