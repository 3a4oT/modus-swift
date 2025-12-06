// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Write Single Coil Builder

/// Builds a Write Single Coil request PDU (Function Code 0x05).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x05)
/// [1-2] Output Address
/// [3-4] Output Value (0xFF00=ON, 0x0000=OFF)
/// ```
///
/// API based on pymodbus `write_coil(address, value)`.
///
/// - Parameters:
///   - address: Coil address (0-65535)
///   - value: True for ON (0xFF00), False for OFF (0x0000)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildWriteSingleCoilPDU(
    address: UInt16,
    value: Bool,
) -> [UInt8] {
    let coilValue: UInt16 = value ? CoilOn : CoilOff

    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.writeSingleRegister) // Same size as write single register

    // Function code
    pdu.append(ModbusFunctionCode.writeSingleCoil)

    // Output address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Output value (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: coilValue >> 8))
    pdu.append(UInt8(truncatingIfNeeded: coilValue))

    return pdu
}

// MARK: - Write Multiple Coils Builder

/// Builds a Write Multiple Coils request PDU (Function Code 0x0F).
///
/// PDU format (6 + N bytes, Big Endian):
/// ```
/// [0]   Function Code (0x0F)
/// [1-2] Starting Address
/// [3-4] Quantity of Outputs (1-1968)
/// [5]   Byte Count (N = ceil(quantity/8))
/// [6..] Output Values (N bytes, LSB first per byte)
/// ```
///
/// API based on pymodbus `write_coils(address, values)`.
///
/// - Parameters:
///   - address: Starting coil address (0-65535)
///   - values: Coil values to write (1-1968 coils)
/// - Returns: PDU ready for MBAP wrapping
@inlinable
public func buildWriteMultipleCoilsPDU(
    address: UInt16,
    values: [Bool],
) -> [UInt8] {
    let quantity = UInt16(values.count)
    let byteCount = UInt8((values.count + 7) / 8)

    var pdu = [UInt8]()
    pdu.reserveCapacity(6 + Int(byteCount))

    // Function code
    pdu.append(ModbusFunctionCode.writeMultipleCoils)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: quantity >> 8))
    pdu.append(UInt8(truncatingIfNeeded: quantity))

    // Byte count
    pdu.append(byteCount)

    // Pack coils into bytes (LSB first)
    var currentByte: UInt8 = 0
    for (i, value) in values.enumerated() {
        let bitIndex = i % 8
        if value {
            currentByte |= (1 << bitIndex)
        }
        // Emit byte when we've filled 8 bits or reached the end
        if bitIndex == 7 || i == values.count - 1 {
            pdu.append(currentByte)
            currentByte = 0
        }
    }

    return pdu
}

// MARK: - WriteSingleCoilResponse

/// Parsed response for Write Single Coil (0x05).
///
/// Response is echo of request: address + value written.
/// API based on pymodbus `WriteSingleCoilResponse`.
public struct WriteSingleCoilResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(address: UInt16, value: Bool) {
        self.address = address
        self.value = value
    }

    // MARK: Public

    /// Coil address that was written
    public let address: UInt16

    /// Value that was written (true = ON, false = OFF)
    public let value: Bool
}

// MARK: - WriteMultipleCoilsResponse

/// Parsed response for Write Multiple Coils (0x0F).
///
/// Response confirms address and quantity written.
/// API based on pymodbus `WriteMultipleCoilsResponse`.
public struct WriteMultipleCoilsResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(address: UInt16, quantity: UInt16) {
        self.address = address
        self.quantity = quantity
    }

    // MARK: Public

    /// Starting address that was written
    public let address: UInt16

    /// Number of coils written
    public let quantity: UInt16
}

// MARK: - Write Single Coil Parser

/// Parses a Write Single Coil response PDU (0x05).
///
/// Response PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x05)
/// [1-2] Output Address (echo)
/// [3-4] Output Value (echo: 0xFF00=ON, 0x0000=OFF)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with address and value
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseWriteSingleCoilPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> WriteSingleCoilResponse {
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

    // Now validate full response size (same as write single register: 5 bytes)
    guard pdu.count >= PDUSize.writeSingleRegister else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.writeSingleCoil else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.writeSingleCoil,
            got: functionCode,
        )
    }

    // Parse address and value (Big Endian)
    guard
        let address = readUInt16BE(pdu, at: 1),
        let rawValue = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }
    let value = rawValue == CoilOn

    return WriteSingleCoilResponse(address: address, value: value)
}

/// Convenience overload for Array input.
@inlinable
public func parseWriteSingleCoilPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> WriteSingleCoilResponse {
    try parseWriteSingleCoilPDU(pdu.span)
}

// MARK: - Write Multiple Coils Parser

/// Parses a Write Multiple Coils response PDU (0x0F).
///
/// Response PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x0F)
/// [1-2] Starting Address
/// [3-4] Quantity of Outputs
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with address and quantity
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseWriteMultipleCoilsPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> WriteMultipleCoilsResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response FIRST
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Response is 5 bytes (same as write multiple registers)
    guard pdu.count >= PDUSize.writeMultipleRegistersResponse else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.writeMultipleCoils else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.writeMultipleCoils,
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

    return WriteMultipleCoilsResponse(address: address, quantity: quantity)
}

/// Convenience overload for Array input.
@inlinable
public func parseWriteMultipleCoilsPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> WriteMultipleCoilsResponse {
    try parseWriteMultipleCoilsPDU(pdu.span)
}
