// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read Exception Status Builder

/// Builds a Read Exception Status request PDU (Function Code 0x07).
///
/// PDU format (1 byte):
/// ```
/// [0]   Function Code (0x07)
/// ```
///
/// This function is designated for Serial Line only per Modbus spec.
/// The request has no data payload — only the function code.
///
/// The response returns the status of eight Exception Status outputs,
/// packed into a single byte with one bit per output (LSB = output 0).
///
/// API based on pymodbus `ReadExceptionStatusRequest`.
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.7
///
/// - Returns: 1-byte PDU ready for RTU framing
@inlinable
public func buildReadExceptionStatusPDU() -> [UInt8] {
    [ModbusFunctionCode.readExceptionStatus]
}

// MARK: - ReadExceptionStatusResponse

/// Parsed response for Read Exception Status (FC 0x07).
///
/// Contains the status of eight Exception Status outputs packed into one byte.
/// Each bit represents one output (LSB = output 0, MSB = output 7).
///
/// The meaning of each bit is device-specific. Common uses:
/// - Operational mode indicators
/// - Error/warning flags
/// - Device-specific status bits
///
/// API based on pymodbus `ReadExceptionStatusResponse`.
public struct ReadExceptionStatusResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(status: UInt8) {
        self.status = status
    }

    // MARK: Public

    /// Exception status byte containing 8 status bits.
    ///
    /// Bit 0 (LSB) = Exception Status output 0
    /// Bit 7 (MSB) = Exception Status output 7
    public let status: UInt8

    /// Returns all 8 outputs as an array of booleans.
    ///
    /// Index 0 corresponds to output 0 (LSB), index 7 to output 7 (MSB).
    public var outputs: [Bool] {
        (0 ..< 8).map { (status & (1 << $0)) != 0 }
    }

    /// Returns the status of a specific output (0-7).
    ///
    /// - Parameter output: Output number (0-7)
    /// - Returns: `true` if output is ON, `false` if OFF, `nil` if out of range
    public func output(at index: Int) -> Bool? {
        guard index >= 0, index < 8 else {
            return nil
        }
        return (status & (1 << index)) != 0
    }
}

// MARK: - Read Exception Status Parser

/// Parses a Read Exception Status response PDU (FC 0x07).
///
/// Response PDU format (2 bytes):
/// ```
/// [0]   Function Code (0x07)
/// [1]   Output Data (8 bits, one per exception status output)
/// ```
///
/// - Parameter pdu: PDU bytes (without RTU header/CRC)
/// - Returns: Parsed response with status byte
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadExceptionStatusPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> ReadExceptionStatusResponse {
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
    guard functionCode == ModbusFunctionCode.readExceptionStatus else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readExceptionStatus,
            got: functionCode,
        )
    }

    // Parse status byte
    guard let status = readUInt8(pdu, at: 1) else {
        throw .pduTooShort
    }

    return ReadExceptionStatusResponse(status: status)
}

/// Convenience overload for Array input.
@inlinable
public func parseReadExceptionStatusPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> ReadExceptionStatusResponse {
    try parseReadExceptionStatusPDU(pdu.span)
}
