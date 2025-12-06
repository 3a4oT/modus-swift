// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Report Server ID Builder

/// Builds a Report Server ID request PDU (Function Code 0x11).
///
/// PDU format (1 byte):
/// ```
/// [0]   Function Code (0x11)
/// ```
///
/// This function is designated for Serial Line only per Modbus spec.
/// The request has no data payload — only the function code.
///
/// API based on pymodbus `ReportDeviceIdRequest`.
///
/// - Returns: 1-byte PDU ready for RTU framing
@inlinable
public func buildReportServerIdPDU() -> [UInt8] {
    [ModbusFunctionCode.reportServerId]
}

// MARK: - ReportServerIdResponse

/// Parsed response for Report Server ID (0x11).
///
/// Contains device identification information and run status.
/// The identifier format is device-dependent (raw bytes).
///
/// API based on pymodbus `ReportDeviceIdResponse`.
public struct ReportServerIdResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(identifier: [UInt8], status: Bool) {
        self.identifier = identifier
        self.status = status
    }

    // MARK: Public

    /// Device identifier (device-dependent format).
    ///
    /// Common formats include:
    /// - ASCII string with device name/model
    /// - Vendor-specific binary data
    public let identifier: [UInt8]

    /// Run indicator status.
    ///
    /// - `true` (0xFF): Device is in RUN mode
    /// - `false` (0x00): Device is in STOP/IDLE mode
    public let status: Bool

    /// Device identifier as UTF-8 string (if valid).
    ///
    /// Returns `nil` if identifier is not valid UTF-8.
    public var identifierString: String? {
        String(validating: identifier, as: UTF8.self)
    }
}

// MARK: - Report Server ID Parser

/// Parses a Report Server ID response PDU (0x11).
///
/// Response PDU format:
/// ```
/// [0]     Function Code (0x11)
/// [1]     Byte Count (N = identifier length + 1 for status)
/// [2..N]  Server ID (identifier, variable length)
/// [N+1]   Run Indicator Status (0xFF = ON, 0x00 = OFF)
/// ```
///
/// - Parameter pdu: PDU bytes (without RTU header/CRC)
/// - Returns: Parsed response with identifier and status
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReportServerIdPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> ReportServerIdResponse {
    // Defense in depth: validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    // Defense in depth: use safe access for function code
    guard let functionCode = readUInt8(pdu, at: 0) else {
        throw .pduTooShort
    }

    // Check for exception response FIRST (before normal response validation)
    // Exception responses are only 2 bytes: FC|0x80 + ExceptionCode
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
    guard functionCode == ModbusFunctionCode.reportServerId else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.reportServerId,
            got: functionCode,
        )
    }

    // Defense in depth: use safe access for byte count
    guard let byteCount = readUInt8(pdu, at: 1) else {
        throw .pduTooShort
    }

    // Byte count must be at least 1 (for status byte)
    // byteCount = identifier_length + 1, so minimum is 1 (empty identifier + status)
    guard byteCount >= 1 else {
        throw .byteCountMismatch(expected: 1, got: byteCount)
    }

    // Validate PDU has enough bytes: FC(1) + ByteCount(1) + Data(byteCount)
    let expectedSize = 2 + Int(byteCount)
    guard pdu.count >= expectedSize else {
        throw .pduTooShort
    }

    // Parse identifier (all bytes except last status byte)
    let identifierLength = Int(byteCount) - 1
    var identifier = [UInt8]()
    identifier.reserveCapacity(identifierLength)

    for i in 0 ..< identifierLength {
        guard let byte = readUInt8(pdu, at: 2 + i) else {
            throw .pduTooShort
        }
        identifier.append(byte)
    }

    // Parse status byte (last byte in data)
    guard let statusByte = readUInt8(pdu, at: 2 + identifierLength) else {
        throw .pduTooShort
    }

    // Status: 0xFF = ON (true), 0x00 = OFF (false)
    let status = statusByte == 0xFF

    return ReportServerIdResponse(identifier: identifier, status: status)
}

/// Convenience overload for Array input.
@inlinable
public func parseReportServerIdPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> ReportServerIdResponse {
    try parseReportServerIdPDU(pdu.span)
}
