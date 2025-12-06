// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Write Single Coil Request Builder

/// Builds a Modbus RTU Write Single Coil request frame (FC 0x05).
///
/// - Parameters:
///   - address: Coil address (0-65535)
///   - value: True for ON (0xFF00), False for OFF (0x0000)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUWriteSingleCoilRequest(
    address: UInt16,
    value: Bool,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.writeSingleCoil)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    // ON = 0xFF00, OFF = 0x0000 (Big Endian)
    frame.append(value ? 0xFF : 0x00)
    frame.append(0x00)
    return appendModbusCRC(frame)
}

// MARK: - RTU Write Single Register Request Builder

/// Builds a Modbus RTU Write Single Register request frame (FC 0x06).
///
/// - Parameters:
///   - address: Register address (0-65535)
///   - value: Value to write (0-65535)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUWriteSingleRegisterRequest(
    address: UInt16,
    value: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(8)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.writeSingleRegister)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: value >> 8))
    frame.append(UInt8(truncatingIfNeeded: value))
    return appendModbusCRC(frame)
}

// MARK: - RTU Write Multiple Coils Request Builder

/// Builds a Modbus RTU Write Multiple Coils request frame (FC 0x0F).
///
/// - Parameters:
///   - address: Starting coil address (0-65535)
///   - values: Coil values to write (1-1968 coils)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUWriteMultipleCoilsRequest(
    address: UInt16,
    values: [Bool],
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    let quantity = UInt16(values.count)
    let byteCount = UInt8((values.count + 7) / 8)

    var frame: [UInt8] = []
    frame.reserveCapacity(9 + Int(byteCount))
    frame.append(unitId)
    frame.append(ModbusFunctionCode.writeMultipleCoils)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: quantity >> 8))
    frame.append(UInt8(truncatingIfNeeded: quantity))
    frame.append(byteCount)

    // Pack coils into bytes (LSB first)
    var currentByte: UInt8 = 0
    for (i, value) in values.enumerated() {
        let bitIndex = i % 8
        if value {
            currentByte |= (1 << bitIndex)
        }
        if bitIndex == 7 || i == values.count - 1 {
            frame.append(currentByte)
            currentByte = 0
        }
    }

    return appendModbusCRC(frame)
}

// MARK: - RTU Write Multiple Registers Request Builder

/// Builds a Modbus RTU Write Multiple Registers request frame (FC 0x10).
///
/// - Parameters:
///   - address: Starting register address (0-65535)
///   - values: Values to write (1-123 registers)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUWriteMultipleRegistersRequest(
    address: UInt16,
    values: [UInt16],
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    let quantity = UInt16(values.count)
    let byteCount = UInt8(values.count * 2)

    var frame: [UInt8] = []
    frame.reserveCapacity(9 + Int(byteCount))
    frame.append(unitId)
    frame.append(ModbusFunctionCode.writeMultipleRegisters)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: quantity >> 8))
    frame.append(UInt8(truncatingIfNeeded: quantity))
    frame.append(byteCount)

    for value in values {
        frame.append(UInt8(truncatingIfNeeded: value >> 8))
        frame.append(UInt8(truncatingIfNeeded: value))
    }

    return appendModbusCRC(frame)
}

// MARK: - RTU Mask Write Register Request Builder

/// Builds a Modbus RTU Mask Write Register request frame (FC 0x16).
///
/// The formula applied: `Result = (Current_Value AND And_Mask) OR Or_Mask`
///
/// - Parameters:
///   - address: Register address (0-65535)
///   - andMask: AND mask for bitwise operation
///   - orMask: OR mask for bitwise operation
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUMaskWriteRegisterRequest(
    address: UInt16,
    andMask: UInt16,
    orMask: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(10)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.maskWriteRegister)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    frame.append(UInt8(truncatingIfNeeded: andMask >> 8))
    frame.append(UInt8(truncatingIfNeeded: andMask))
    frame.append(UInt8(truncatingIfNeeded: orMask >> 8))
    frame.append(UInt8(truncatingIfNeeded: orMask))
    return appendModbusCRC(frame)
}

// MARK: - RTU Write Response Parser

/// Parses a Modbus RTU write response (FC 0x05, 0x06, 0x0F, 0x10, 0x16).
///
/// Validates CRC and checks for exceptions.
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
///   - expectedFunction: Expected function code
/// - Returns: Parsed response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUWriteResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8,
) throws(RTUError) -> RTUWriteResponse {
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

    // Extract data bytes (everything except unitId, functionCode, and CRC)
    var data: [UInt8] = []
    let dataLength = frame.count - 4 // subtract unitId(1) + func(1) + crc(2)
    data.reserveCapacity(dataLength)
    for i in 0 ..< dataLength {
        data.append(frame[2 + i])
    }

    return RTUWriteResponse(
        unitId: unitId,
        functionCode: functionCode,
        data: data,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUWriteResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8,
) throws(RTUError) -> RTUWriteResponse {
    try parseRTUWriteResponse(frame.span, expectedUnitId: expectedUnitId, expectedFunction: expectedFunction)
}

/// Convenience overload for ArraySlice input.
@inlinable
public func parseRTUWriteResponse(
    _ frame: ArraySlice<UInt8>,
    expectedUnitId: UInt8 = 0x01,
    expectedFunction: UInt8,
) throws(RTUError) -> RTUWriteResponse {
    try parseRTUWriteResponse(frame.span, expectedUnitId: expectedUnitId, expectedFunction: expectedFunction)
}
