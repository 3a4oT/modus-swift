// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Get Comm Event Counter Builder

/// Builds a Get Comm Event Counter request PDU (Function Code 0x0B).
///
/// PDU format (1 byte):
/// ```
/// [0]   Function Code (0x0B)
/// ```
///
/// This function is designated for Serial Line only per Modbus spec.
/// The request has no data payload — only the function code.
///
/// Used to get a status word and event count from the remote device's
/// communication event counter. By fetching the count before and after
/// a series of messages, a client can determine if messages were handled
/// normally.
///
/// API based on pymodbus `GetCommEventCounterRequest`.
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.9
///
/// - Returns: 1-byte PDU ready for RTU framing
@inlinable
public func buildGetCommEventCounterPDU() -> [UInt8] {
    [ModbusFunctionCode.getCommEventCounter]
}

// MARK: - GetCommEventCounterResponse

/// Parsed response for Get Comm Event Counter (FC 0x0B).
///
/// Contains a status word and an event count from the device's
/// communication event counter.
///
/// The event counter is incremented once for each successful message
/// completion. It is NOT incremented for:
/// - Exception responses
/// - Poll commands
/// - Fetch event counter commands
///
/// The counter can be reset via Diagnostics (FC 0x08) with sub-functions:
/// - Restart Communications Option (0x0001)
/// - Clear Counters and Diagnostic Register (0x000A)
///
/// API based on pymodbus `GetCommEventCounterResponse`.
public struct GetCommEventCounterResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(status: UInt16, count: UInt16) {
        self.status = status
        self.count = count
    }

    // MARK: Public

    /// Raw status word from the device.
    ///
    /// Per Modbus spec:
    /// - 0x0000: Device is ready (not busy)
    /// - 0xFFFF: Device is busy (processing a previous command)
    ///
    /// Verified against pymodbus: ModbusStatus.READY = 0x0000, ModbusStatus.WAITING = 0xFFFF
    public let status: UInt16

    /// Communication event counter value.
    ///
    /// Incremented for each successful message completion.
    public let count: UInt16

    /// Returns `true` if device is ready (not busy).
    ///
    /// Per Modbus spec: "status word will be zero" when ready.
    /// Per pymodbus: ModbusStatus.READY = 0x0000
    public var isReady: Bool {
        status == 0x0000
    }

    /// Returns `true` if device is busy processing a previous command.
    ///
    /// Per Modbus spec: "status word will be all ones (FF FF hex) if... busy condition exists"
    /// Per pymodbus: ModbusStatus.WAITING = 0xFFFF
    public var isBusy: Bool {
        status == 0xFFFF
    }
}

// MARK: - Get Comm Event Counter Parser

/// Parses a Get Comm Event Counter response PDU (FC 0x0B).
///
/// Response PDU format (5 bytes):
/// ```
/// [0]     Function Code (0x0B)
/// [1-2]   Status (Big Endian): 0x0000 = ready, 0xFFFF = busy
/// [3-4]   Event Count (Big Endian)
/// ```
///
/// Verified against pymodbus test vectors:
/// - status=True (ready): encodes to `b"\x00\x00\x00\x12"` (status=0x0000, count=0x12)
/// - status=False (busy): encodes to `b"\xFF\xFF\x00\x12"` (status=0xFFFF, count=0x12)
///
/// - Parameter pdu: PDU bytes (without RTU header/CRC)
/// - Returns: Parsed response with status and count
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseGetCommEventCounterPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> GetCommEventCounterResponse {
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
    guard functionCode == ModbusFunctionCode.getCommEventCounter else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.getCommEventCounter,
            got: functionCode,
        )
    }

    // Parse status and count with safe access
    guard
        let status = readUInt16BE(pdu, at: 1),
        let count = readUInt16BE(pdu, at: 3) else
    {
        throw .pduTooShort
    }

    return GetCommEventCounterResponse(status: status, count: count)
}

/// Convenience overload for Array input.
@inlinable
public func parseGetCommEventCounterPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> GetCommEventCounterResponse {
    try parseGetCommEventCounterPDU(pdu.span)
}
