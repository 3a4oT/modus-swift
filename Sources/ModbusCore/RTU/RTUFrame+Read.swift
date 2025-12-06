// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Read Request Builders

/// Builds a Modbus RTU Read Holding Registers request frame (FC 0x03).
///
/// Frame structure (Big Endian for multi-byte values):
/// - Unit ID: 1 byte
/// - Function Code: 0x03
/// - Address: 2 bytes (BE)
/// - Count: 2 bytes (BE)
/// - CRC-16: 2 bytes (LE)
///
/// API based on pymodbus `read_holding_registers(address, count, slave)`.
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - count: Number of registers to read (1-125)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadRequest(
    address: UInt16,
    count: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)

    // Unit ID
    frame.append(unitId)

    // Function code
    frame.append(ModbusFunctionCode.readHoldingRegisters)

    // Address (Big Endian)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))

    // Count (Big Endian)
    frame.append(UInt8(truncatingIfNeeded: count >> 8))
    frame.append(UInt8(truncatingIfNeeded: count))

    // Append CRC
    return appendModbusCRC(frame)
}

/// Builds a Modbus RTU Read Coils request frame (FC 0x01).
///
/// - Parameters:
///   - address: Starting coil address (0-65535)
///   - count: Number of coils to read (1-2000)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadCoilsRequest(
    address: UInt16,
    count: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readCoils)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: count >> 8))
    frame.append(UInt8(truncatingIfNeeded: count))
    return appendModbusCRC(frame)
}

/// Builds a Modbus RTU Read Discrete Inputs request frame (FC 0x02).
///
/// - Parameters:
///   - address: Starting input address (0-65535)
///   - count: Number of inputs to read (1-2000)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadDiscreteInputsRequest(
    address: UInt16,
    count: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readDiscreteInputs)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: count >> 8))
    frame.append(UInt8(truncatingIfNeeded: count))
    return appendModbusCRC(frame)
}

/// Builds a Modbus RTU Read Input Registers request frame (FC 0x04).
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - count: Number of registers to read (1-125)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadInputRegistersRequest(
    address: UInt16,
    count: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readInputRegisters)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: count >> 8))
    frame.append(UInt8(truncatingIfNeeded: count))
    return appendModbusCRC(frame)
}

// MARK: - RTU Read Response Parser

/// Parses a Modbus RTU Read Holding Registers response.
///
/// Performs validations in order:
/// 1. Minimum frame size
/// 2. CRC verification
/// 3. Exception check
/// 4. Unit ID match
/// 5. Function code match
/// 6. Byte count validation
///
/// API based on pymodbus response parsing.
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
///   - expectedFunction: Expected function code (default: 0x03)
/// - Returns: Parsed response with register data
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUReadResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8 = ModbusFunctionCode.readHoldingRegisters,
) throws(RTUError) -> RTUReadResponse {
    // Validate minimum size
    try validateRTUMinimumSize(frame)

    // Validate CRC
    try validateRTUCRC(frame)

    // Check for exception response
    if isRTUExceptionResponse(frame) {
        let exceptionCode = frame[2]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        // Unknown exception code - treat as illegal function
        throw .exceptionResponse(.illegalFunction)
    }

    // Validate unit ID
    let unitId = frame[0]
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    // Validate function code
    let functionCode = frame[1]
    guard functionCode == expectedFunction else {
        throw .unexpectedFunctionCode(expected: expectedFunction, got: functionCode)
    }

    // Get byte count
    let byteCount = frame[2]

    // Validate frame has enough bytes: unitId(1) + func(1) + count(1) + data(N) + crc(2)
    let expectedFrameSize = 3 + Int(byteCount) + RTUFrameSize.crc
    guard frame.count >= expectedFrameSize else {
        throw .frameTooShort
    }

    // Extract data bytes
    var data: [UInt8] = []
    data.reserveCapacity(Int(byteCount))
    for i in 0 ..< Int(byteCount) {
        data.append(frame[3 + i])
    }

    return RTUReadResponse(
        unitId: unitId,
        functionCode: functionCode,
        data: data,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUReadResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8 = ModbusFunctionCode.readHoldingRegisters,
) throws(RTUError) -> RTUReadResponse {
    try parseRTUReadResponse(frame.span, expectedUnitId: expectedUnitId, expectedFunction: expectedFunction)
}

/// Convenience overload for ArraySlice input (from V5 response).
@inlinable
public func parseRTUReadResponse(
    _ frame: ArraySlice<UInt8>,
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8 = ModbusFunctionCode.readHoldingRegisters,
) throws(RTUError) -> RTUReadResponse {
    try parseRTUReadResponse(frame.span, expectedUnitId: expectedUnitId, expectedFunction: expectedFunction)
}
