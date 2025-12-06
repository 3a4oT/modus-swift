// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read Holding Registers Builder

/// Builds a Read Holding Registers request PDU (Function Code 0x03).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x03)
/// [1-2] Starting Address
/// [3-4] Quantity of Registers
/// ```
///
/// API based on pymodbus `read_holding_registers(address, count)`.
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - count: Number of registers to read (1-125)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadHoldingRegistersPDU(
    address: UInt16,
    count: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.readRequest)

    // Function code
    pdu.append(ModbusFunctionCode.readHoldingRegisters)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: count >> 8))
    pdu.append(UInt8(truncatingIfNeeded: count))

    return pdu
}

// MARK: - Read Input Registers Builder

/// Builds a Read Input Registers request PDU (Function Code 0x04).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x04)
/// [1-2] Starting Address
/// [3-4] Quantity of Registers
/// ```
///
/// API based on pymodbus `read_input_registers(address, count)`.
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - count: Number of registers to read (1-125)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadInputRegistersPDU(
    address: UInt16,
    count: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.readRequest)

    // Function code
    pdu.append(ModbusFunctionCode.readInputRegisters)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: count >> 8))
    pdu.append(UInt8(truncatingIfNeeded: count))

    return pdu
}

// MARK: - ReadRegistersResponse

/// Parsed response for Read Holding/Input Registers.
///
/// API based on pymodbus `ReadHoldingRegistersResponse.registers`.
public struct ReadRegistersResponse: Equatable, Sendable {
    // MARK: Lifecycle

    /// Internal initializer for parser
    @usableFromInline
    init(functionCode: UInt8, registers: [UInt16]) {
        self.functionCode = functionCode
        self.registers = registers
    }

    // MARK: Public

    /// Function code from response (0x03 or 0x04)
    public let functionCode: UInt8

    /// Register values (each UInt16 in native byte order)
    ///
    /// Matches pymodbus `response.registers` property.
    public let registers: [UInt16]

    /// Number of registers in response
    public var count: Int {
        registers.count
    }

    /// Reads a UInt16 register value at the given index.
    ///
    /// Provides safe bounds-checked access to register values.
    ///
    /// - Parameter index: Register index (0-based)
    /// - Returns: Register value, or nil if out of bounds
    public func value(at index: Int) -> UInt16? {
        guard index >= 0, index < registers.count else {
            return nil
        }
        return registers[index]
    }

    /// Reads a signed Int16 register value at the given index.
    ///
    /// - Parameter index: Register index (0-based)
    /// - Returns: Register value as signed integer, or nil if out of bounds
    public func signedValue(at index: Int) -> Int16? {
        guard index >= 0, index < registers.count else {
            return nil
        }
        return Int16(bitPattern: registers[index])
    }

    /// Reads a UInt32 value from two consecutive registers.
    ///
    /// Default word order: High word first (AB_CD / Big Endian).
    ///
    /// - Parameter index: Starting register index
    /// - Returns: 32-bit value, or nil if out of bounds
    public func uint32Value(at index: Int) -> UInt32? {
        guard index >= 0, index + 1 < registers.count else {
            return nil
        }
        let high = registers[index]
        let low = registers[index + 1]
        return (UInt32(high) << 16) | UInt32(low)
    }

    /// Reads a signed Int32 value from two consecutive registers.
    ///
    /// - Parameter index: Starting register index
    /// - Returns: 32-bit signed value, or nil if out of bounds
    public func int32Value(at index: Int) -> Int32? {
        guard let unsigned = uint32Value(at: index) else {
            return nil
        }
        return Int32(bitPattern: unsigned)
    }
}

// MARK: - Read Registers Parser

/// Parses a Read Registers response PDU.
///
/// Response PDU format:
/// ```
/// [0]   Function Code (0x03 or 0x04)
/// [1]   Byte Count (N)
/// [2..] Register Data (N bytes, Big Endian per register)
/// ```
///
/// - Parameters:
///   - pdu: PDU bytes (without MBAP header)
///   - expectedFunction: Expected function code (default: 0x03)
/// - Returns: Parsed response with registers
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadRegistersPDU(
    _ pdu: Span<UInt8>,
    expectedFunction: UInt8 = ModbusFunctionCode.readHoldingRegisters,
) throws(PDUError) -> ReadRegistersResponse {
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
    guard functionCode == expectedFunction else {
        throw .unexpectedFunctionCode(expected: expectedFunction, got: functionCode)
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

    return ReadRegistersResponse(
        functionCode: functionCode,
        registers: registers,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseReadRegistersPDU(
    _ pdu: [UInt8],
    expectedFunction: UInt8 = ModbusFunctionCode.readHoldingRegisters,
) throws(PDUError) -> ReadRegistersResponse {
    try parseReadRegistersPDU(pdu.span, expectedFunction: expectedFunction)
}
