// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Get Comm Event Log Builder

/// Builds a Get Comm Event Log request PDU (Function Code 0x0C).
///
/// PDU format (1 byte):
/// ```
/// [0]   Function Code (0x0C)
/// ```
///
/// This function is designated for Serial Line only per Modbus spec.
/// The request has no data payload — only the function code.
///
/// Used to get a status word, event count, message count, and a field
/// of event bytes from the remote device. The event bytes contain the
/// status of communication events (sends, receives, errors) in chronological
/// order with the most recent event first.
///
/// API based on pymodbus `GetCommEventLogRequest`.
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.10
///
/// - Returns: 1-byte PDU ready for RTU framing
@inlinable
public func buildGetCommEventLogPDU() -> [UInt8] {
    [ModbusFunctionCode.getCommEventLog]
}

// MARK: - GetCommEventLogResponse

/// Parsed response for Get Comm Event Log (FC 0x0C).
///
/// Contains a status word, event count, message count, and up to 64 event bytes.
///
/// The status word and event count are identical to FC 0x0B (Get Comm Event Counter).
/// The message count contains the quantity of messages processed since restart.
///
/// Event bytes field contains 0-64 bytes, each representing one Modbus
/// send or receive operation. Byte 0 is the most recent event.
/// Each new event flushes the oldest event from the field.
///
/// API based on pymodbus `GetCommEventLogResponse`.
public struct GetCommEventLogResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(status: UInt16, eventCount: UInt16, messageCount: UInt16, events: [UInt8]) {
        self.status = status
        self.eventCount = eventCount
        self.messageCount = messageCount
        self.events = events
    }

    // MARK: Public

    /// Raw status word from the device.
    ///
    /// Per Modbus spec:
    /// - 0x0000: Device is ready (not busy)
    /// - 0xFFFF: Device is busy (processing a previous command)
    ///
    /// Identical to FC 0x0B status.
    public let status: UInt16

    /// Communication event counter value.
    ///
    /// Identical to FC 0x0B event count.
    public let eventCount: UInt16

    /// Message counter value.
    ///
    /// Quantity of messages processed since last restart, clear counters,
    /// or power-up. Identical to Diagnostics sub-function 0x0B.
    public let messageCount: UInt16

    /// Event bytes (0-64 bytes).
    ///
    /// Each byte represents one Modbus send or receive operation.
    /// Index 0 is the most recent event.
    /// Event byte format is defined by bit 7 (and bit 6 for further definition).
    public let events: [UInt8]

    /// Returns `true` if device is ready (not busy).
    public var isReady: Bool {
        status == 0x0000
    }

    /// Returns `true` if device is busy processing a previous command.
    public var isBusy: Bool {
        status == 0xFFFF
    }
}

// MARK: - Get Comm Event Log Parser

/// Parses a Get Comm Event Log response PDU (FC 0x0C).
///
/// Response PDU format (variable length, 8+ bytes):
/// ```
/// [0]     Function Code (0x0C)
/// [1]     Byte Count (N = 6 + events.count)
/// [2-3]   Status (Big Endian): 0x0000 = ready, 0xFFFF = busy
/// [4-5]   Event Count (Big Endian)
/// [6-7]   Message Count (Big Endian)
/// [8..N+1] Events (0-64 bytes, most recent first)
/// ```
///
/// Verified against pymodbus test vectors:
/// - Empty events: `b"\x06\x00\x00\x00\x12\x00\x12"` (byteCount=6, status=0x0000, eventCount=0x12, msgCount=0x12)
/// - Status=busy: `b"\x06\xff\xff\x00\x12\x00\x12"` (status=0xFFFF)
///
/// - Parameter pdu: PDU bytes (without RTU header/CRC)
/// - Returns: Parsed response with status, counts, and events
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseGetCommEventLogPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> GetCommEventLogResponse {
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
    guard functionCode == ModbusFunctionCode.getCommEventLog else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.getCommEventLog,
            got: functionCode,
        )
    }

    // Parse byte count
    guard let byteCount = readUInt8(pdu, at: 1) else {
        throw .pduTooShort
    }

    // Minimum byteCount is 6 (status + eventCount + messageCount, no events)
    guard byteCount >= 6 else {
        throw .byteCountMismatch(expected: 6, got: byteCount)
    }

    // Validate PDU has enough bytes: FC(1) + ByteCount(1) + Data(byteCount)
    let expectedSize = 2 + Int(byteCount)
    guard pdu.count >= expectedSize else {
        throw .pduTooShort
    }

    // Parse fixed fields with safe access
    guard
        let status = readUInt16BE(pdu, at: 2),
        let eventCount = readUInt16BE(pdu, at: 4),
        let messageCount = readUInt16BE(pdu, at: 6) else
    {
        throw .pduTooShort
    }

    // Parse event bytes (byteCount - 6 bytes)
    let eventBytesCount = Int(byteCount) - 6
    var events: [UInt8] = []
    events.reserveCapacity(eventBytesCount)

    for i in 0 ..< eventBytesCount {
        guard let eventByte = readUInt8(pdu, at: 8 + i) else {
            throw .pduTooShort
        }
        events.append(eventByte)
    }

    return GetCommEventLogResponse(
        status: status,
        eventCount: eventCount,
        messageCount: messageCount,
        events: events,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseGetCommEventLogPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> GetCommEventLogResponse {
    try parseGetCommEventLogPDU(pdu.span)
}
