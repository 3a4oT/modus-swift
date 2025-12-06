// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Read Holding Registers (0x03) and Read Input Registers (0x04).
///
/// Test vectors verified against:
/// - pymodbus test suite
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Read Registers PDU")
struct ReadRegistersTests {
    // MARK: - Function Code Constants

    @Test("Function code constants")
    func functionCodes() {
        // Verified: Modbus specification
        #expect(ModbusFunctionCode.readHoldingRegisters == 0x03)
        #expect(ModbusFunctionCode.readInputRegisters == 0x04)
        #expect(ModbusFunctionCode.exceptionFlag == 0x80)
    }

    @Test("PDU size constants")
    func pduSizes() {
        #expect(PDUSize.readRequest == 5)
        #expect(PDUSize.minimumReadResponse == 2)
        #expect(PDUSize.exceptionResponse == 2)
    }

    // MARK: - Request Builder Tests

    @Test("Build Read Holding Registers PDU - address 0, count 10")
    func buildReadHoldingRegisters() {
        // Verified: pymodbus ReadHoldingRegistersRequest(0, 10).encode()
        let pdu = buildReadHoldingRegistersPDU(address: 0, count: 10)

        let expected: [UInt8] = [
            0x03, // Function code
            0x00, 0x00, // Start address (BE)
            0x00, 0x0A, // Quantity (BE)
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.readRequest)
    }

    @Test("Build Read Holding Registers PDU - address 0x006B, count 3")
    func buildReadHoldingRegistersLargeAddress() {
        // Verified: pymodbus ReadHoldingRegistersRequest(0x006B, 3).encode()
        let pdu = buildReadHoldingRegistersPDU(address: 0x006B, count: 3)

        let expected: [UInt8] = [
            0x03, // Function code
            0x00, 0x6B, // Start address = 107 (BE)
            0x00, 0x03, // Quantity (BE)
        ]

        #expect(pdu == expected)
    }

    @Test("Build Read Holding Registers PDU - max address and count")
    func buildReadHoldingRegistersMax() {
        let pdu = buildReadHoldingRegistersPDU(address: 0xFFFF, count: 125)

        let expected: [UInt8] = [
            0x03,
            0xFF, 0xFF, // Max address
            0x00, 0x7D, // 125 in BE
        ]

        #expect(pdu == expected)
    }

    @Test("Build Read Input Registers PDU")
    func buildReadInputRegisters() {
        // Verified: pymodbus ReadInputRegistersRequest(0, 5).encode()
        let pdu = buildReadInputRegistersPDU(address: 0, count: 5)

        let expected: [UInt8] = [
            0x04, // Function code
            0x00, 0x00,
            0x00, 0x05,
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.readRequest)
    }

    // MARK: - Response Parser Tests

    @Test("Parse Read Registers response - 3 registers")
    func parseReadRegistersResponse() throws {
        // Response: 3 registers with values 0x0001, 0x0002, 0x0003
        let pdu: [UInt8] = [
            0x03, // Function code
            0x06, // Byte count (3 registers * 2 bytes)
            0x00, 0x01, // Register 0 = 1
            0x00, 0x02, // Register 1 = 2
            0x00, 0x03, // Register 2 = 3
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.functionCode == 0x03)
        #expect(response.count == 3)
        #expect(response.registers == [1, 2, 3])
    }

    @Test("Parse Read Registers response - large values")
    func parseReadRegistersLargeValues() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04, // 2 registers
            0xFF, 0xFF, // 65535
            0x12, 0x34, // 4660
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.registers == [0xFFFF, 0x1234])
        #expect(response.registers[0] == 65535)
        #expect(response.registers[1] == 4660)
    }

    @Test("Parse Read Input Registers response")
    func parseReadInputRegisters() throws {
        let pdu: [UInt8] = [
            0x04, // Function code for input registers
            0x02, // 1 register
            0xAB, 0xCD,
        ]

        let response = try parseReadRegistersPDU(pdu, expectedFunction: 0x04)

        #expect(response.functionCode == 0x04)
        #expect(response.registers == [0xABCD])
    }

    @Test("Parse response - PDU too short")
    func parseResponseTooShort() {
        let pdu: [UInt8] = [0x03] // Only function code

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse response - empty PDU")
    func parseEmptyPDU() {
        let pdu: [UInt8] = []

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse response - unexpected function code")
    func parseUnexpectedFunctionCode() {
        let pdu: [UInt8] = [
            0x04, // Input registers, not holding
            0x02,
            0x00, 0x01,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x03, got: 0x04)) {
            try parseReadRegistersPDU(pdu, expectedFunction: 0x03)
        }
    }

    @Test("Parse response - data shorter than byte count")
    func parseDataTooShort() {
        let pdu: [UInt8] = [
            0x03,
            0x06, // Claims 6 bytes of data
            0x00, 0x01, // Only 2 bytes
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    // MARK: - Security Edge Case Tests (CVE-style)

    // These tests verify protection against vulnerabilities found in
    // reference implementations (libmodbus CVE-2024-10918, pymodbus struct.unpack issues)

    @Test("Parse response - odd byte count rejected")
    func parseOddByteCount() {
        // Byte count must be even (2 bytes per register)
        // CVE-2023-26793 style: malformed byte count
        let pdu: [UInt8] = [
            0x03,
            0x05, // Odd byte count - invalid
            0x00, 0x01, 0x02, 0x03, 0x04,
        ]

        #expect(throws: PDUError.byteCountMismatch(expected: 5, got: 5)) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse response - maximum byte count (250 registers)")
    func parseMaxByteCount() throws {
        // Max per Modbus spec: 125 registers = 250 bytes
        // But we should handle larger values safely
        var pdu: [UInt8] = [0x03, 0xFA] // 250 bytes
        pdu.append(contentsOf: [UInt8](repeating: 0x12, count: 250))

        let response = try parseReadRegistersPDU(pdu)
        #expect(response.count == 125)
    }

    @Test("Parse response - byte count 0xFF with insufficient data")
    func parseByteCountFFInsufficientData() {
        // Attacker sends max byte count but minimal data
        // CVE-2024-10918 style: response length overflow
        let pdu: [UInt8] = [
            0x03,
            0xFF, // Claims 255 bytes
            0x00, 0x01, // Only 2 bytes of data
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse response - truncated mid-register")
    func parseTruncatedMidRegister() {
        // Data truncated in the middle of a 16-bit register
        // pymodbus struct.unpack issue: "unpack requires a buffer of 2 bytes"
        let pdu: [UInt8] = [
            0x03,
            0x04, // Claims 4 bytes (2 registers)
            0x00, 0x01, // First register OK
            0x02, // Second register truncated - only 1 byte
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse response - exception with truncated code")
    func parseExceptionTruncated() {
        // Exception flag set but no exception code
        let pdu: [UInt8] = [0x83] // Only exception FC, no code

        #expect(throws: PDUError.pduTooShort) {
            try parseReadRegistersPDU(pdu)
        }
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() {
        // Exception response: FC 0x03 + 0x80 = 0x83
        let pdu: [UInt8] = [
            0x83, // Exception flag set
            0x01, // Illegal Function
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse exception response - Illegal Data Address")
    func parseExceptionIllegalAddress() {
        let pdu: [UInt8] = [
            0x83,
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Busy")
    func parseExceptionSlaveBusy() {
        let pdu: [UInt8] = [
            0x83,
            0x06, // Slave Device Busy
        ]

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceBusy)) {
            try parseReadRegistersPDU(pdu)
        }
    }

    @Test("Parse exception response - unknown code")
    func parseExceptionUnknown() {
        let pdu: [UInt8] = [
            0x83,
            0xFF, // Unknown exception code
        ]

        #expect(throws: PDUError.unknownException(0xFF)) {
            try parseReadRegistersPDU(pdu)
        }
    }

    // MARK: - ReadRegistersResponse Value Accessors

    @Test("Response signed value accessor")
    func responseSignedValue() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0xFF, 0xFF, // -1 as Int16
            0x80, 0x00, // -32768 as Int16
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.signedValue(at: 0) == -1)
        #expect(response.signedValue(at: 1) == -32768)
        #expect(response.signedValue(at: 2) == nil) // Out of bounds
    }

    @Test("Response value accessor with bounds checking")
    func responseValueAccessor() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0x12, 0x34,
            0xAB, 0xCD,
        ]

        let response = try parseReadRegistersPDU(pdu)

        // Valid indices
        #expect(response.value(at: 0) == 0x1234)
        #expect(response.value(at: 1) == 0xABCD)

        // Out of bounds returns nil
        #expect(response.value(at: 2) == nil)
        #expect(response.value(at: -1) == nil)
    }

    @Test("Response UInt32 value accessor")
    func responseUInt32Value() throws {
        // Two registers forming 0x12345678
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0x12, 0x34, // High word
            0x56, 0x78, // Low word
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.uint32Value(at: 0) == 0x1234_5678)
        #expect(response.uint32Value(at: 1) == nil) // Not enough registers
    }

    @Test("Response Int32 value accessor")
    func responseInt32Value() throws {
        // Two registers forming -1 (0xFFFFFFFF)
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0xFF, 0xFF,
            0xFF, 0xFF,
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.int32Value(at: 0) == -1)
    }

    // MARK: - Round-trip Tests

    @Test("Build and parse round-trip")
    func roundTrip() throws {
        // Build request
        let requestPDU = buildReadHoldingRegistersPDU(address: 100, count: 5)

        // Verify request structure
        #expect(requestPDU[0] == 0x03)
        #expect(requestPDU[1] == 0x00)
        #expect(requestPDU[2] == 0x64) // 100
        #expect(requestPDU[3] == 0x00)
        #expect(requestPDU[4] == 0x05)

        // Simulate response (5 registers)
        let responsePDU: [UInt8] = [
            0x03,
            0x0A, // 10 bytes = 5 registers
            0x00, 0x01,
            0x00, 0x02,
            0x00, 0x03,
            0x00, 0x04,
            0x00, 0x05,
        ]

        let response = try parseReadRegistersPDU(responsePDU)

        #expect(response.count == 5)
        #expect(response.registers == [1, 2, 3, 4, 5])
    }
}
