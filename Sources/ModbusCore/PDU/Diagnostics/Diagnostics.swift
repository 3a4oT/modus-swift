// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - DiagnosticSubFunction

/// Diagnostic sub-function codes for FC 0x08.
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.8
/// Verified against: pymodbus DiagnosticStatus enum, libmodbus
///
/// **Note:** This function is designated for Serial Line only per Modbus spec.
public enum DiagnosticSubFunction: UInt16, Sendable, CaseIterable {
    /// Return Query Data (0x0000) — Loopback test
    /// Data: Any 16-bit value, echoed back unchanged
    case returnQueryData = 0x0000

    /// Restart Communications Option (0x0001)
    /// Data: 0x0000 = normal, 0xFF00 = clear log
    case restartCommunications = 0x0001

    /// Return Diagnostic Register (0x0002)
    /// Data: 0x0000 (ignored), returns diagnostic register value
    case returnDiagnosticRegister = 0x0002

    /// Change ASCII Input Delimiter (0x0003)
    /// Data: New delimiter character (high byte), low byte = 0x00
    case changeAsciiInputDelimiter = 0x0003

    /// Force Listen Only Mode (0x0004)
    /// Data: 0x0000 (ignored), puts device in listen-only mode
    case forceListenOnlyMode = 0x0004

    /// Clear Counters and Diagnostic Register (0x000A)
    /// Data: 0x0000 (ignored), clears all counters
    case clearCounters = 0x000A

    /// Return Bus Message Count (0x000B)
    /// Data: 0x0000 (ignored), returns message count
    case returnBusMessageCount = 0x000B

    /// Return Bus Communication Error Count (0x000C)
    /// Data: 0x0000 (ignored), returns CRC error count
    case returnBusCommunicationErrorCount = 0x000C

    /// Return Bus Exception Error Count (0x000D)
    /// Data: 0x0000 (ignored), returns exception count
    case returnBusExceptionErrorCount = 0x000D

    /// Return Server Message Count (0x000E)
    /// Data: 0x0000 (ignored), returns messages addressed to this server
    case returnServerMessageCount = 0x000E

    /// Return Server No Response Count (0x000F)
    /// Data: 0x0000 (ignored), returns no-response count
    case returnServerNoResponseCount = 0x000F

    /// Return Server NAK Count (0x0010)
    /// Data: 0x0000 (ignored), returns NAK count
    case returnServerNAKCount = 0x0010

    /// Return Server Busy Count (0x0011)
    /// Data: 0x0000 (ignored), returns busy count
    case returnServerBusyCount = 0x0011

    /// Return Bus Character Overrun Count (0x0012)
    /// Data: 0x0000 (ignored), returns overrun count
    case returnBusCharacterOverrunCount = 0x0012

    /// Clear Overrun Counter and Flag (0x0014)
    /// Data: 0x0000 (ignored), clears overrun counter
    case clearOverrunCounter = 0x0014
}

// MARK: - Diagnostics Request Builder

/// Builds a Diagnostics request PDU (Function Code 0x08).
///
/// PDU format (5 bytes):
/// ```
/// [0]     Function Code (0x08)
/// [1-2]   Sub-function Code (Big Endian)
/// [3-4]   Data (Big Endian)
/// ```
///
/// This function is designated for Serial Line only per Modbus spec.
/// API based on pymodbus `DiagnosticStatusRequest`.
///
/// - Parameters:
///   - subFunction: Diagnostic sub-function code
///   - data: 16-bit data value (meaning depends on sub-function)
/// - Returns: 5-byte PDU ready for RTU framing
@inlinable
public func buildDiagnosticsPDU(
    subFunction: DiagnosticSubFunction,
    data: UInt16,
) -> [UInt8] {
    [
        ModbusFunctionCode.diagnostics,
        UInt8(subFunction.rawValue >> 8),
        UInt8(subFunction.rawValue & 0xFF),
        UInt8(data >> 8),
        UInt8(data & 0xFF),
    ]
}

/// Builds a Diagnostics request PDU with raw sub-function code.
///
/// Use this for vendor-specific sub-functions not defined in `DiagnosticSubFunction`.
///
/// - Parameters:
///   - subFunctionCode: Raw sub-function code (0x0000-0xFFFF)
///   - data: 16-bit data value
/// - Returns: 5-byte PDU ready for RTU framing
@inlinable
public func buildDiagnosticsPDU(
    subFunctionCode: UInt16,
    data: UInt16,
) -> [UInt8] {
    [
        ModbusFunctionCode.diagnostics,
        UInt8(subFunctionCode >> 8),
        UInt8(subFunctionCode & 0xFF),
        UInt8(data >> 8),
        UInt8(data & 0xFF),
    ]
}

// MARK: - DiagnosticsResponse

/// Parsed response for Diagnostics (FC 0x08).
///
/// The response echoes the sub-function and contains response data.
/// For most sub-functions, the data is simply echoed back.
/// For counter queries, the data contains the counter value.
///
/// API based on pymodbus `DiagnosticStatusResponse`.
public struct DiagnosticsResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(subFunction: UInt16, data: UInt16) {
        self.subFunction = subFunction
        self.data = data
    }

    // MARK: Public

    /// Sub-function code (echoed from request)
    public let subFunction: UInt16

    /// Response data (meaning depends on sub-function)
    ///
    /// - For `returnQueryData`: Echoed query data
    /// - For counter queries: Counter value
    /// - For other: Echo of request data
    public let data: UInt16

    /// Returns the sub-function as typed enum if recognized.
    public var subFunctionType: DiagnosticSubFunction? {
        DiagnosticSubFunction(rawValue: subFunction)
    }
}

// MARK: - Diagnostics Parser

/// Parses a Diagnostics response PDU (FC 0x08).
///
/// Response PDU format (5 bytes):
/// ```
/// [0]     Function Code (0x08)
/// [1-2]   Sub-function Code (Big Endian, echo)
/// [3-4]   Data (Big Endian)
/// ```
///
/// - Parameter pdu: PDU bytes (without RTU header/CRC)
/// - Returns: Parsed response with sub-function and data
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseDiagnosticsPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> DiagnosticsResponse {
    // Defense in depth: validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    // Defense in depth: use safe access for function code
    guard let functionCode = readUInt8(pdu, at: 0) else {
        throw .pduTooShort
    }

    // Check for exception response FIRST (before normal response validation)
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        guard let exceptionCode = readUInt8(pdu, at: 1) else {
            throw .pduTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.diagnostics else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.diagnostics,
            got: functionCode,
        )
    }

    // Parse sub-function and data with safe access
    guard
        let subFunction = readUInt16BE(pdu, at: 1),
        let data = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }

    return DiagnosticsResponse(subFunction: subFunction, data: data)
}

/// Convenience overload for Array input.
@inlinable
public func parseDiagnosticsPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> DiagnosticsResponse {
    try parseDiagnosticsPDU(pdu.span)
}
