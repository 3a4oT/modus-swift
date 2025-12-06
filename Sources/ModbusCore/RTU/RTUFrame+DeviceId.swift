// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Read Device Identification Request Builder

/// Builds a Modbus RTU Read Device Identification request frame (FC 0x2B / MEI 0x0E).
///
/// - Parameters:
///   - readCode: Read device ID code (.basic, .regular, .extended, .specific)
///   - objectId: Starting object ID (default 0x00) or specific object for .specific
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadDeviceIdentificationRequest(
    readCode: ReadDeviceIdCode,
    objectId: UInt8 = 0x00,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(6) // unitId + FC + MEI + readCode + objectId + CRC(2)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.encapsulatedInterface)
    frame.append(MEIType.readDeviceIdentification)
    frame.append(readCode.rawValue)
    frame.append(objectId)
    return appendModbusCRC(frame)
}

// MARK: - RTU Device Identification Response Parser

/// Parses a Modbus RTU Read Device Identification response (FC 0x2B / MEI 0x0E).
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed device identification response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUDeviceIdentificationResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> DeviceIdentificationResponse {
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
    guard functionCode == ModbusFunctionCode.encapsulatedInterface else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.encapsulatedInterface,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3 // unitId(1) + CRC(2)
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        pdu.append(frame[i])
    }

    // Use existing PDU parser
    do {
        return try parseDeviceIdentificationPDU(pdu)
    } catch {
        // Map PDU errors to RTU errors (error is PDUError due to typed throws)
        switch error {
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case .pduTooShort:
            throw .frameTooShort
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            throw .byteCountMismatch(expected: expected, got: got)
        case .unknownException,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUDeviceIdentificationResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> DeviceIdentificationResponse {
    try parseRTUDeviceIdentificationResponse(frame.span, expectedUnitId: expectedUnitId)
}

// MARK: - RTU Report Server ID Request Builder

/// Builds a Modbus RTU Report Server ID request frame (FC 0x11).
///
/// This function is designated for Serial Line only per Modbus spec.
/// The request has no data payload — only unit ID, function code, and CRC.
///
/// API based on pymodbus `ReportDeviceIdRequest`.
///
/// - Parameter unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (4 bytes total)
@inlinable
public func buildRTUReportServerIdRequest(
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(RTUFrameSize.reportServerIdRequest)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.reportServerId)
    return appendModbusCRC(frame)
}

// MARK: - RTU Report Server ID Response Parser

/// Parses a Modbus RTU Report Server ID response (FC 0x11).
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed Report Server ID response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUReportServerIdResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReportServerIdResponse {
    // Validate minimum size
    try validateRTUMinimumSize(frame)

    // Validate CRC
    try validateRTUCRC(frame)

    // Check for exception response
    if isRTUExceptionResponse(frame) {
        // Defense in depth: use safe access
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    // Defense in depth: use safe access for unit ID
    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    // Defense in depth: use safe access for function code
    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.reportServerId else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.reportServerId,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3 // unitId(1) + CRC(2)
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        // Defense in depth: use safe access
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    // Use existing PDU parser
    do {
        return try parseReportServerIdPDU(pdu)
    } catch {
        // Map PDU errors to RTU errors
        switch error {
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case .pduTooShort:
            throw .frameTooShort
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            throw .byteCountMismatch(expected: expected, got: got)
        case .unknownException,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUReportServerIdResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReportServerIdResponse {
    try parseRTUReportServerIdResponse(frame.span, expectedUnitId: expectedUnitId)
}
