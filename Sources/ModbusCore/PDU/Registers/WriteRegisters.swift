// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Write Single Register Builder

/// Builds a Write Single Register request PDU (Function Code 0x06).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x06)
/// [1-2] Register Address
/// [3-4] Register Value
/// ```
///
/// API based on pymodbus `write_register(address, value)`.
///
/// - Parameters:
///   - address: Register address (0-65535)
///   - value: Value to write (0-65535)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildWriteSingleRegisterPDU(
    address: UInt16,
    value: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.writeSingleRegister)

    // Function code
    pdu.append(ModbusFunctionCode.writeSingleRegister)

    // Register address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Register value (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: value >> 8))
    pdu.append(UInt8(truncatingIfNeeded: value))

    return pdu
}

// MARK: - Write Multiple Registers Builder

/// Builds a Write Multiple Registers request PDU (Function Code 0x10).
///
/// PDU format (6 + N×2 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x10)
/// [1-2] Starting Address
/// [3-4] Quantity of Registers
/// [5]   Byte Count (N = Quantity × 2)
/// [6..] Register Values (N bytes)
/// ```
///
/// API based on pymodbus `write_registers(address, values)`.
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - values: Values to write (1-123 registers per Modbus spec)
/// - Returns: PDU ready for MBAP wrapping
@inlinable
public func buildWriteMultipleRegistersPDU(
    address: UInt16,
    values: [UInt16],
) -> [UInt8] {
    let quantity = UInt16(values.count)
    let byteCount = UInt8(values.count * 2)

    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.writeMultipleRegistersRequestHeader + Int(byteCount))

    // Function code
    pdu.append(ModbusFunctionCode.writeMultipleRegisters)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: quantity >> 8))
    pdu.append(UInt8(truncatingIfNeeded: quantity))

    // Byte count
    pdu.append(byteCount)

    // Register values (Big Endian)
    for value in values {
        pdu.append(UInt8(truncatingIfNeeded: value >> 8))
        pdu.append(UInt8(truncatingIfNeeded: value))
    }

    return pdu
}

// MARK: - WriteSingleRegisterResponse

/// Parsed response for Write Single Register (0x06).
///
/// Response is echo of request: address + value written.
/// API based on pymodbus `WriteSingleRegisterResponse`.
public struct WriteSingleRegisterResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(address: UInt16, value: UInt16) {
        self.address = address
        self.value = value
    }

    // MARK: Public

    /// Register address that was written
    public let address: UInt16

    /// Value that was written
    public let value: UInt16
}

// MARK: - WriteMultipleRegistersResponse

/// Parsed response for Write Multiple Registers (0x10).
///
/// Response confirms address and quantity written.
/// API based on pymodbus `WriteMultipleRegistersResponse`.
public struct WriteMultipleRegistersResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(address: UInt16, quantity: UInt16) {
        self.address = address
        self.quantity = quantity
    }

    // MARK: Public

    /// Starting address that was written
    public let address: UInt16

    /// Number of registers written
    public let quantity: UInt16
}

// MARK: - Write Single Register Parser

/// Parses a Write Single Register response PDU (0x06).
///
/// Response PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x06)
/// [1-2] Register Address (echo)
/// [3-4] Register Value (echo)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with address and value
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseWriteSingleRegisterPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> WriteSingleRegisterResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response FIRST (before size validation)
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Now validate full response size
    guard pdu.count >= PDUSize.writeSingleRegister else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.writeSingleRegister else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.writeSingleRegister,
            got: functionCode,
        )
    }

    // Parse address and value (Big Endian)
    guard
        let address = readUInt16BE(pdu, at: 1),
        let value = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }

    return WriteSingleRegisterResponse(address: address, value: value)
}

/// Convenience overload for Array input.
@inlinable
public func parseWriteSingleRegisterPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> WriteSingleRegisterResponse {
    try parseWriteSingleRegisterPDU(pdu.span)
}

// MARK: - Write Multiple Registers Parser

/// Parses a Write Multiple Registers response PDU (0x10).
///
/// Response PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x10)
/// [1-2] Starting Address
/// [3-4] Quantity of Registers
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with address and quantity
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseWriteMultipleRegistersPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> WriteMultipleRegistersResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response FIRST (before size validation)
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Now validate full response size
    guard pdu.count >= PDUSize.writeMultipleRegistersResponse else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.writeMultipleRegisters else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.writeMultipleRegisters,
            got: functionCode,
        )
    }

    // Parse address and quantity (Big Endian)
    guard
        let address = readUInt16BE(pdu, at: 1),
        let quantity = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }

    return WriteMultipleRegistersResponse(address: address, quantity: quantity)
}

/// Convenience overload for Array input.
@inlinable
public func parseWriteMultipleRegistersPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> WriteMultipleRegistersResponse {
    try parseWriteMultipleRegistersPDU(pdu.span)
}
