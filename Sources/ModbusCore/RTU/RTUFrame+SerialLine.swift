// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Read Exception Status (FC 0x07)

/// Builds a Modbus RTU Read Exception Status request (FC 0x07).
///
/// Serial Line only function code. Reads the status of eight Exception Status
/// outputs (coils 1-8 in a sequential device).
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x07)
/// [2-3]   CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.7
///
/// - Parameter unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (4 bytes total)
@inlinable
public func buildRTUReadExceptionStatusRequest(
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(RTUFrameSize.readExceptionStatusRequest)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readExceptionStatus)
    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Read Exception Status response (FC 0x07).
///
/// Response frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x07)
/// [2]     Output Data (8 bits)
/// [3-4]   CRC-16
/// ```
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed Read Exception Status response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUReadExceptionStatusResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadExceptionStatusResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.readExceptionStatus else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readExceptionStatus,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseReadExceptionStatusPDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case .unknownException,
             .byteCountMismatch,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUReadExceptionStatusResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadExceptionStatusResponse {
    try parseRTUReadExceptionStatusResponse(frame.span, expectedUnitId: expectedUnitId)
}

// MARK: - RTU Diagnostics (FC 0x08)

/// Builds a Modbus RTU Diagnostics request (FC 0x08).
///
/// Serial Line only function code. Provides tests for checking the
/// communication system and serial line status.
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x08)
/// [2-3]   Sub-function (Big Endian)
/// [4-5]   Data (Big Endian)
/// [6-7]   CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.8
///
/// - Parameters:
///   - subFunction: Diagnostics sub-function code
///   - data: Data value (interpretation depends on sub-function)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (8 bytes total)
@inlinable
public func buildRTUDiagnosticsRequest(
    subFunction: DiagnosticSubFunction,
    data: UInt16 = 0x0000,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(RTUFrameSize.diagnosticsRequest)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.diagnostics)
    frame.append(UInt8(truncatingIfNeeded: subFunction.rawValue >> 8))
    frame.append(UInt8(truncatingIfNeeded: subFunction.rawValue))
    frame.append(UInt8(truncatingIfNeeded: data >> 8))
    frame.append(UInt8(truncatingIfNeeded: data))
    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Diagnostics response (FC 0x08).
///
/// Response is normally an echo of the request (for most sub-functions).
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed Diagnostics response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUDiagnosticsResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> DiagnosticsResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.diagnostics else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.diagnostics,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseDiagnosticsPDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case .unknownException,
             .byteCountMismatch,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUDiagnosticsResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> DiagnosticsResponse {
    try parseRTUDiagnosticsResponse(frame.span, expectedUnitId: expectedUnitId)
}

// MARK: - RTU Get Comm Event Counter (FC 0x0B)

/// Builds a Modbus RTU Get Comm Event Counter request (FC 0x0B).
///
/// Serial Line only function code. Returns a status word and event count
/// from the remote device's communication event counter.
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x0B)
/// [2-3]   CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.9
///
/// - Parameter unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (4 bytes total)
@inlinable
public func buildRTUGetCommEventCounterRequest(
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(RTUFrameSize.getCommEventCounterRequest)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.getCommEventCounter)
    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Get Comm Event Counter response (FC 0x0B).
///
/// Response frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x0B)
/// [2-3]   Status (Big Endian)
/// [4-5]   Event Count (Big Endian)
/// [6-7]   CRC-16
/// ```
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed Get Comm Event Counter response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUGetCommEventCounterResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> GetCommEventCounterResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.getCommEventCounter else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.getCommEventCounter,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseGetCommEventCounterPDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case .unknownException,
             .byteCountMismatch,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUGetCommEventCounterResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> GetCommEventCounterResponse {
    try parseRTUGetCommEventCounterResponse(frame.span, expectedUnitId: expectedUnitId)
}

// MARK: - RTU Get Comm Event Log (FC 0x0C)

/// Builds a Modbus RTU Get Comm Event Log request (FC 0x0C).
///
/// Serial Line only function code. Returns a status word, event count,
/// message count, and a field of event bytes from the remote device.
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x0C)
/// [2-3]   CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.10
///
/// - Parameter unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (4 bytes total)
@inlinable
public func buildRTUGetCommEventLogRequest(
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(RTUFrameSize.getCommEventLogRequest)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.getCommEventLog)
    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Get Comm Event Log response (FC 0x0C).
///
/// Response frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x0C)
/// [2]     Byte Count (N)
/// [3-4]   Status (Big Endian)
/// [5-6]   Event Count (Big Endian)
/// [7-8]   Message Count (Big Endian)
/// [9..N]  Events (0-64 bytes)
/// [N+1..] CRC-16
/// ```
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed Get Comm Event Log response
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUGetCommEventLogResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> GetCommEventLogResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.getCommEventLog else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.getCommEventLog,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseGetCommEventLogPDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case .unknownException,
             .byteCountMismatch,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUGetCommEventLogResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> GetCommEventLogResponse {
    try parseRTUGetCommEventLogResponse(frame.span, expectedUnitId: expectedUnitId)
}
