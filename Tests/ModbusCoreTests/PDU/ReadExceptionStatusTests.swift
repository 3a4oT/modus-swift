// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Read Exception Status (FC 0x07).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.7
/// Test vectors verified against pymodbus ReadExceptionStatusRequest/Response.
@Suite("Read Exception Status PDU")
struct ReadExceptionStatusTests {
    // MARK: - Function Code Constant

    @Test("Function code constant")
    func functionCodeConstant() {
        #expect(ModbusFunctionCode.readExceptionStatus == 0x07)
    }

    // MARK: - Request Builder Tests

    @Test("Build request PDU")
    func buildRequestPDU() {
        // Verified: pymodbus ReadExceptionStatusRequest().encode() == b''
        // Request is just the function code (no payload)
        let pdu = buildReadExceptionStatusPDU()

        #expect(pdu == [0x07])
        #expect(pdu.count == 1)
    }

    // MARK: - Response Parser Tests

    @Test("Parse response with status 0x12")
    func parseResponseStatus0x12() throws {
        // Verified: pymodbus ReadExceptionStatusResponse(status=0x12).encode() == b'\x12'
        let pdu: [UInt8] = [0x07, 0x12]

        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.status == 0x12)
    }

    @Test("Parse response with status 0x6D")
    func parseResponseStatus0x6D() throws {
        // Per Modbus spec example: 6D hex = 0110 1101 binary
        // Outputs: OFF-ON-ON-OFF-ON-ON-OFF-ON (MSB to LSB display)
        // In bit order: bit0=1, bit1=0, bit2=1, bit3=1, bit4=0, bit5=1, bit6=1, bit7=0
        let pdu: [UInt8] = [0x07, 0x6D]

        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.status == 0x6D)
        // Verify individual bits (LSB first)
        #expect(response.output(at: 0) == true) // bit 0 = 1
        #expect(response.output(at: 1) == false) // bit 1 = 0
        #expect(response.output(at: 2) == true) // bit 2 = 1
        #expect(response.output(at: 3) == true) // bit 3 = 1
        #expect(response.output(at: 4) == false) // bit 4 = 0
        #expect(response.output(at: 5) == true) // bit 5 = 1
        #expect(response.output(at: 6) == true) // bit 6 = 1
        #expect(response.output(at: 7) == false) // bit 7 = 0
    }

    @Test("Parse response with all outputs ON")
    func parseResponseAllOn() throws {
        let pdu: [UInt8] = [0x07, 0xFF]

        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.status == 0xFF)
        #expect(response.outputs.allSatisfy { $0 == true })
    }

    @Test("Parse response with all outputs OFF")
    func parseResponseAllOff() throws {
        let pdu: [UInt8] = [0x07, 0x00]

        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.status == 0x00)
        #expect(response.outputs.allSatisfy { $0 == false })
    }

    // MARK: - Response Output Accessors

    @Test("Output accessor returns nil for invalid index")
    func outputAccessorInvalidIndex() throws {
        let pdu: [UInt8] = [0x07, 0xFF]
        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.output(at: -1) == nil)
        #expect(response.output(at: 8) == nil)
        #expect(response.output(at: 100) == nil)
    }

    @Test("Outputs array has 8 elements")
    func outputsArrayCount() throws {
        let pdu: [UInt8] = [0x07, 0xAA] // 1010 1010
        let response = try parseReadExceptionStatusPDU(pdu)

        #expect(response.outputs.count == 8)
        // 0xAA = 10101010: bits 1,3,5,7 are ON
        #expect(response.outputs == [false, true, false, true, false, true, false, true])
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() throws {
        let pdu: [UInt8] = [0x87, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseReadExceptionStatusPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Failure")
    func parseExceptionSlaveDeviceFailure() throws {
        let pdu: [UInt8] = [0x87, 0x04] // FC|0x80 + SlaveDeviceFailure

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceFailure)) {
            try parseReadExceptionStatusPDU(pdu)
        }
    }

    // MARK: - Error Cases

    @Test("Parse PDU too short - empty")
    func parsePDUTooShortEmpty() {
        let pdu: [UInt8] = []

        #expect(throws: PDUError.pduTooShort) {
            try parseReadExceptionStatusPDU(pdu)
        }
    }

    @Test("Parse PDU too short - only function code")
    func parsePDUTooShortOnlyFC() {
        let pdu: [UInt8] = [0x07]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadExceptionStatusPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() {
        let pdu: [UInt8] = [0x03, 0x12] // FC 0x03 instead of 0x07

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x07, got: 0x03)) {
            try parseReadExceptionStatusPDU(pdu)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Request is minimal (1 byte)")
    func requestIsMinimal() {
        let pdu = buildReadExceptionStatusPDU()

        #expect(pdu.count == 1)
        #expect(pdu[0] == ModbusFunctionCode.readExceptionStatus)
    }

    @Test("Response round-trip")
    func responseRoundTrip() throws {
        // Build response PDU manually
        let responsePDU: [UInt8] = [0x07, 0x55] // 01010101

        let response = try parseReadExceptionStatusPDU(responsePDU)

        #expect(response.status == 0x55)
        // Verify alternating pattern
        for i in 0 ..< 8 {
            #expect(response.output(at: i) == (i % 2 == 0))
        }
    }

    // MARK: - Boundary Value Tests

    @Test("All possible status values parse correctly")
    func allStatusValuesParse() throws {
        // Test a sample of boundary values
        let testValues: [UInt8] = [0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF]

        for value in testValues {
            let pdu: [UInt8] = [0x07, value]
            let response = try parseReadExceptionStatusPDU(pdu)
            #expect(response.status == value)
        }
    }
}
