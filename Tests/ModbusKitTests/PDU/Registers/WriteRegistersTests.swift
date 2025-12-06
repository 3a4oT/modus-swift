// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Write Single Register (0x06) and Write Multiple Registers (0x10).
///
/// Test vectors verified against:
/// - pymodbus test suite
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Write Registers PDU")
struct WriteRegistersTests {
    // MARK: - Write Single Register (0x06) Tests

    @Test("Build Write Single Register PDU")
    func buildWriteSingleRegister() {
        // Verified: pymodbus WriteSingleRegisterRequest(0x0001, 0x0003).encode()
        let pdu = buildWriteSingleRegisterPDU(address: 0x0001, value: 0x0003)

        let expected: [UInt8] = [
            0x06, // Function code
            0x00, 0x01, // Register address
            0x00, 0x03, // Register value
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.writeSingleRegister)
    }

    @Test("Build Write Single Register - max value")
    func buildWriteSingleRegisterMaxValue() {
        let pdu = buildWriteSingleRegisterPDU(address: 0xFFFF, value: 0xFFFF)

        #expect(pdu[1] == 0xFF)
        #expect(pdu[2] == 0xFF)
        #expect(pdu[3] == 0xFF)
        #expect(pdu[4] == 0xFF)
    }

    @Test("Parse Write Single Register response")
    func parseWriteSingleRegisterResponse() throws {
        // Response is echo of request
        let pdu: [UInt8] = [
            0x06,
            0x00, 0x01,
            0x00, 0x03,
        ]

        let response = try parseWriteSingleRegisterPDU(pdu)

        #expect(response.address == 0x0001)
        #expect(response.value == 0x0003)
    }

    @Test("Parse Write Single Register - exception response")
    func parseWriteSingleRegisterException() {
        let pdu: [UInt8] = [
            0x86, // 0x06 + 0x80
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Single Register - PDU too short")
    func parseWriteSingleRegisterTooShort() {
        let pdu: [UInt8] = [0x06, 0x00, 0x01] // Only 3 bytes, need 5

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Single Register - wrong function code")
    func parseWriteSingleRegisterWrongFC() {
        let pdu: [UInt8] = [
            0x05, // Wrong FC
            0x00, 0x01,
            0x00, 0x03,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x06, got: 0x05)) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Write Single Register round-trip")
    func writeSingleRegisterRoundTrip() throws {
        let requestPDU = buildWriteSingleRegisterPDU(address: 0x1234, value: 0xABCD)

        // Response is echo
        let response = try parseWriteSingleRegisterPDU(requestPDU)

        #expect(response.address == 0x1234)
        #expect(response.value == 0xABCD)
    }

    // MARK: - Write Multiple Registers (0x10) Tests

    @Test("Build Write Multiple Registers PDU")
    func buildWriteMultipleRegisters() {
        // Verified: pymodbus WriteMultipleRegistersRequest(0x0001, [0x000A, 0x0102]).encode()
        let pdu = buildWriteMultipleRegistersPDU(address: 0x0001, values: [0x000A, 0x0102])

        let expected: [UInt8] = [
            0x10, // Function code
            0x00, 0x01, // Starting address
            0x00, 0x02, // Quantity of registers
            0x04, // Byte count
            0x00, 0x0A, // Register 1
            0x01, 0x02, // Register 2
        ]

        #expect(pdu == expected)
    }

    @Test("Build Write Multiple Registers - single register")
    func buildWriteMultipleRegistersSingle() {
        let pdu = buildWriteMultipleRegistersPDU(address: 0, values: [0xFFFF])

        #expect(pdu[0] == 0x10)
        #expect(pdu[4] == 0x01) // Quantity = 1
        #expect(pdu[5] == 0x02) // Byte count = 2
        #expect(pdu[6] == 0xFF)
        #expect(pdu[7] == 0xFF)
    }

    @Test("Build Write Multiple Registers - max count")
    func buildWriteMultipleRegistersMaxCount() {
        // Per Modbus spec: max 123 registers
        let values = [UInt16](repeating: 0x1234, count: 123)
        let pdu = buildWriteMultipleRegistersPDU(address: 0, values: values)

        #expect(pdu[3] == 0x00)
        #expect(pdu[4] == 0x7B) // 123
        #expect(pdu[5] == 0xF6) // Byte count = 246
        #expect(pdu.count == 6 + 246)
    }

    @Test("Parse Write Multiple Registers response")
    func parseWriteMultipleRegistersResponse() throws {
        let pdu: [UInt8] = [
            0x10, // Function code
            0x00, 0x01, // Starting address
            0x00, 0x02, // Quantity written
        ]

        let response = try parseWriteMultipleRegistersPDU(pdu)

        #expect(response.address == 0x0001)
        #expect(response.quantity == 2)
    }

    @Test("Parse Write Multiple Registers - exception response")
    func parseWriteMultipleRegistersException() {
        let pdu: [UInt8] = [
            0x90, // 0x10 + 0x80
            0x03, // Illegal Data Value
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataValue)) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers - PDU too short")
    func parseWriteMultipleRegistersTooShort() {
        let pdu: [UInt8] = [0x10, 0x00, 0x01, 0x00] // Only 4 bytes, need 5

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers - wrong function code")
    func parseWriteMultipleRegistersWrongFC() {
        let pdu: [UInt8] = [
            0x06, // Wrong FC
            0x00, 0x01,
            0x00, 0x02,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x10, got: 0x06)) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Write Multiple Registers round-trip")
    func writeMultipleRegistersRoundTrip() throws {
        let values: [UInt16] = [0x1234, 0x5678, 0x9ABC]
        let requestPDU = buildWriteMultipleRegistersPDU(address: 0x0100, values: values)

        #expect(requestPDU[0] == 0x10)
        #expect(requestPDU[4] == 0x03) // 3 registers

        let responsePDU: [UInt8] = [
            0x10,
            0x01, 0x00, // Address
            0x00, 0x03, // Quantity
        ]

        let response = try parseWriteMultipleRegistersPDU(responsePDU)

        #expect(response.address == 0x0100)
        #expect(response.quantity == 3)
    }

    // MARK: - Truncated Data Tests (Security-Critical)

    // These tests verify that truncated PDUs are properly rejected.
    // Reference: pymodbus has known bugs from insufficient bounds checking
    // before struct.unpack, causing crashes on malformed network data.

    @Test("Parse Write Single Register - truncated after function code")
    func parseWriteSingleRegisterTruncatedAfterFC() {
        // Only function code, no address or value
        let pdu: [UInt8] = [0x06]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Single Register - truncated address")
    func parseWriteSingleRegisterTruncatedAddress() {
        // FC + 1 byte of address (need 2)
        let pdu: [UInt8] = [0x06, 0x00]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Single Register - truncated value")
    func parseWriteSingleRegisterTruncatedValue() {
        // FC + address + 1 byte of value (need 2)
        let pdu: [UInt8] = [0x06, 0x00, 0x01, 0x00]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers - truncated after function code")
    func parseWriteMultipleRegistersTruncatedAfterFC() {
        let pdu: [UInt8] = [0x10]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers - truncated address")
    func parseWriteMultipleRegistersTruncatedAddress() {
        // FC + 1 byte of address (need 2)
        let pdu: [UInt8] = [0x10, 0x00]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers - truncated quantity")
    func parseWriteMultipleRegistersTruncatedQuantity() {
        // FC + address + 1 byte of quantity (need 2)
        let pdu: [UInt8] = [0x10, 0x00, 0x01, 0x00]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Write Single Register exception - truncated")
    func parseWriteSingleRegisterExceptionTruncated() {
        // Exception flag but no exception code
        let pdu: [UInt8] = [0x86]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleRegisterPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Registers exception - truncated")
    func parseWriteMultipleRegistersExceptionTruncated() {
        // Exception flag but no exception code
        let pdu: [UInt8] = [0x90]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleRegistersPDU(pdu)
        }
    }
}
