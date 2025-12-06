// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Get Comm Event Counter (FC 0x0B).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.9
/// Test vectors verified against pymodbus GetCommEventCounterRequest/Response.
///
/// Key spec points:
/// - Status 0x0000 = device ready (not busy)
/// - Status 0xFFFF = device busy (processing previous command)
/// - pymodbus: ModbusStatus.READY = 0x0000, ModbusStatus.WAITING = 0xFFFF
@Suite("Get Comm Event Counter PDU")
struct GetCommEventCounterTests {
    // MARK: - Function Code Constant

    @Test("Function code constant")
    func functionCodeConstant() {
        #expect(ModbusFunctionCode.getCommEventCounter == 0x0B)
    }

    // MARK: - Request Builder Tests

    @Test("Build request PDU")
    func buildRequestPDU() {
        // Verified: pymodbus GetCommEventCounterRequest().encode() == b''
        // Request is just the function code (no payload)
        let pdu = buildGetCommEventCounterPDU()

        #expect(pdu == [0x0B])
        #expect(pdu.count == 1)
    }

    // MARK: - Response Parser Tests (pymodbus verified)

    @Test("Parse response - device ready (status=0x0000)")
    func parseResponseDeviceReady() throws {
        // Verified: pymodbus GetCommEventCounterResponse(status=True, count=0x12)
        // encodes to b"\x00\x00\x00\x12"
        let pdu: [UInt8] = [0x0B, 0x00, 0x00, 0x00, 0x12]

        let response = try parseGetCommEventCounterPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.count == 0x12)
        #expect(response.isReady == true)
        #expect(response.isBusy == false)
    }

    @Test("Parse response - device busy (status=0xFFFF)")
    func parseResponseDeviceBusy() throws {
        // Verified: pymodbus GetCommEventCounterResponse(status=False, count=0x12)
        // encodes to b"\xFF\xFF\x00\x12"
        let pdu: [UInt8] = [0x0B, 0xFF, 0xFF, 0x00, 0x12]

        let response = try parseGetCommEventCounterPDU(pdu)

        #expect(response.status == 0xFFFF)
        #expect(response.count == 0x12)
        #expect(response.isReady == false)
        #expect(response.isBusy == true)
    }

    @Test("Parse response - zero count")
    func parseResponseZeroCount() throws {
        let pdu: [UInt8] = [0x0B, 0x00, 0x00, 0x00, 0x00]

        let response = try parseGetCommEventCounterPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.count == 0x0000)
        #expect(response.isReady == true)
    }

    @Test("Parse response - max count")
    func parseResponseMaxCount() throws {
        let pdu: [UInt8] = [0x0B, 0x00, 0x00, 0xFF, 0xFF]

        let response = try parseGetCommEventCounterPDU(pdu)

        #expect(response.status == 0x0000)
        #expect(response.count == 0xFFFF)
    }

    @Test("Parse response - arbitrary status value")
    func parseResponseArbitraryStatus() throws {
        // Non-standard status value (neither 0x0000 nor 0xFFFF)
        let pdu: [UInt8] = [0x0B, 0x12, 0x34, 0x56, 0x78]

        let response = try parseGetCommEventCounterPDU(pdu)

        #expect(response.status == 0x1234)
        #expect(response.count == 0x5678)
        // Neither ready nor busy for non-standard values
        #expect(response.isReady == false)
        #expect(response.isBusy == false)
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() throws {
        let pdu: [UInt8] = [0x8B, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Failure")
    func parseExceptionSlaveDeviceFailure() throws {
        let pdu: [UInt8] = [0x8B, 0x04] // FC|0x80 + SlaveDeviceFailure

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceFailure)) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    // MARK: - Error Cases

    @Test("Parse PDU too short - empty")
    func parsePDUTooShortEmpty() {
        let pdu: [UInt8] = []

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    @Test("Parse PDU too short - only function code")
    func parsePDUTooShortOnlyFC() {
        let pdu: [UInt8] = [0x0B]

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    @Test("Parse PDU too short - missing count bytes")
    func parsePDUTooShortMissingCount() {
        let pdu: [UInt8] = [0x0B, 0x00, 0x00] // Only status, no count

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    @Test("Parse PDU too short - partial count")
    func parsePDUTooShortPartialCount() {
        let pdu: [UInt8] = [0x0B, 0x00, 0x00, 0x00] // Status + 1 byte of count

        #expect(throws: PDUError.pduTooShort) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() {
        let pdu: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x12] // FC 0x03 instead of 0x0B

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x0B, got: 0x03)) {
            try parseGetCommEventCounterPDU(pdu)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Request is minimal (1 byte)")
    func requestIsMinimal() {
        let pdu = buildGetCommEventCounterPDU()

        #expect(pdu.count == 1)
        #expect(pdu[0] == ModbusFunctionCode.getCommEventCounter)
    }

    @Test("Response PDU size is 5 bytes")
    func responsePDUSize() throws {
        let pdu: [UInt8] = [0x0B, 0x00, 0x00, 0x00, 0x00]

        _ = try parseGetCommEventCounterPDU(pdu)
        #expect(pdu.count == 5)
    }
}
