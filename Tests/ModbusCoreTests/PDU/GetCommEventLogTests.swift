// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Get Comm Event Log (FC 0x0C).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.10
/// Test vectors verified against pymodbus GetCommEventLogRequest/Response.
///
/// Key spec points:
/// - Status 0x0000 = device ready, 0xFFFF = device busy (same as FC 0x0B)
/// - Event bytes: 0-64 bytes, most recent event at index 0
/// - Byte count = 6 + events.count
@Suite("Get Comm Event Log PDU")
struct GetCommEventLogTests {
    // MARK: - Function Code Constant

    @Test("Function code constant")
    func functionCodeConstant() {
        #expect(ModbusFunctionCode.getCommEventLog == 0x0C)
    }

    // MARK: - Request Builder Tests

    @Test("Build request PDU")
    func buildRequestPDU() {
        // Verified: pymodbus GetCommEventLogRequest().encode() == b''
        // Request is just the function code (no payload)
        let pdu = buildGetCommEventLogPDU()

        #expect(pdu == [0x0C])
        #expect(pdu.count == 1)
    }

    // MARK: - Response Parser Tests (pymodbus verified)

    @Test("Parse response - device ready, no events")
    func parseResponseReadyNoEvents() throws {
        // Verified: pymodbus GetCommEventLogResponse(status=True, event_count=0x12, message_count=0x12)
        // encodes to b"\x06\x00\x00\x00\x12\x00\x12"
        let pdu: [UInt8] = [0x0C, 0x06, 0x00, 0x00, 0x00, 0x12, 0x00, 0x12]

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.eventCount == 0x0012)
        #expect(response.messageCount == 0x0012)
        #expect(response.events.isEmpty)
        #expect(response.isReady == true)
        #expect(response.isBusy == false)
    }

    @Test("Parse response - device busy")
    func parseResponseBusy() throws {
        // Verified: pymodbus GetCommEventLogResponse(status=False, event_count=0x12, message_count=0x12)
        // encodes to b"\x06\xff\xff\x00\x12\x00\x12"
        let pdu: [UInt8] = [0x0C, 0x06, 0xFF, 0xFF, 0x00, 0x12, 0x00, 0x12]

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.status == 0xFFFF)
        #expect(response.eventCount == 0x0012)
        #expect(response.messageCount == 0x0012)
        #expect(response.events.isEmpty)
        #expect(response.isReady == false)
        #expect(response.isBusy == true)
    }

    @Test("Parse response - with events")
    func parseResponseWithEvents() throws {
        // byteCount = 6 + 3 events = 9
        let pdu: [UInt8] = [
            0x0C, // FC
            0x09, // Byte count (6 + 3)
            0x00, 0x00, // Status: ready
            0x00, 0x05, // Event count: 5
            0x00, 0x10, // Message count: 16
            0xAA, 0xBB, 0xCC, // 3 event bytes
        ]

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.eventCount == 5)
        #expect(response.messageCount == 16)
        #expect(response.events == [0xAA, 0xBB, 0xCC])
    }

    @Test("Parse response - max events (64)")
    func parseResponseMaxEvents() throws {
        // byteCount = 6 + 64 events = 70
        var pdu: [UInt8] = [
            0x0C, // FC
            70, // Byte count (6 + 64)
            0x00, 0x00, // Status: ready
            0x00, 0x40, // Event count: 64
            0x01, 0x00, // Message count: 256
        ]
        // Add 64 event bytes
        for i: UInt8 in 0 ..< 64 {
            pdu.append(i)
        }

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.eventCount == 64)
        #expect(response.messageCount == 256)
        #expect(response.events.count == 64)
        #expect(response.events[0] == 0)
        #expect(response.events[63] == 63)
    }

    @Test("Parse response - zero counts")
    func parseResponseZeroCounts() throws {
        let pdu: [UInt8] = [0x0C, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.eventCount == 0)
        #expect(response.messageCount == 0)
        #expect(response.events.isEmpty)
    }

    @Test("Parse response - max counts")
    func parseResponseMaxCounts() throws {
        let pdu: [UInt8] = [0x0C, 0x06, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]

        let response = try parseGetCommEventLogPDU(pdu)

        #expect(response.eventCount == 0xFFFF)
        #expect(response.messageCount == 0xFFFF)
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() throws {
        let pdu: [UInt8] = [0x8C, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Failure")
    func parseExceptionSlaveDeviceFailure() throws {
        let pdu: [UInt8] = [0x8C, 0x04] // FC|0x80 + SlaveDeviceFailure

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceFailure)) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    // MARK: - Error Cases

    @Test("Parse PDU too short - empty")
    func parsePDUTooShortEmpty() {
        let pdu: [UInt8] = []

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    @Test("Parse PDU too short - only function code")
    func parsePDUTooShortOnlyFC() {
        let pdu: [UInt8] = [0x0C]

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    @Test("Parse PDU too short - missing data")
    func parsePDUTooShortMissingData() {
        // byteCount says 6, but only 4 bytes of data
        let pdu: [UInt8] = [0x0C, 0x06, 0x00, 0x00, 0x00, 0x12]

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    @Test("Parse byte count too small")
    func parseByteCountTooSmall() {
        // byteCount must be at least 6
        let pdu: [UInt8] = [0x0C, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00]

        #expect(throws: PDUError.byteCountMismatch(expected: 6, got: 5)) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() {
        let pdu: [UInt8] = [0x03, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x0C, got: 0x03)) {
            try parseGetCommEventLogPDU(pdu)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Request is minimal (1 byte)")
    func requestIsMinimal() {
        let pdu = buildGetCommEventLogPDU()

        #expect(pdu.count == 1)
        #expect(pdu[0] == ModbusFunctionCode.getCommEventLog)
    }

    @Test("Response PDU minimum size is 8 bytes")
    func responsePDUMinSize() throws {
        // FC(1) + ByteCount(1) + Status(2) + EventCount(2) + MessageCount(2) = 8
        let pdu: [UInt8] = [0x0C, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

        let response = try parseGetCommEventLogPDU(pdu)
        #expect(response.events.isEmpty)
    }
}
