// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Read/Write Multiple Registers (0x17).
///
/// Test vectors verified against:
/// - Modbus Application Protocol Specification V1.1b3 section 6.17
@Suite("Read/Write Multiple Registers PDU")
struct ReadWriteRegistersTests {
    @Test("Build Read/Write Multiple Registers PDU")
    func buildReadWriteMultipleRegisters() {
        // Verified: Modbus spec V1.1b3 section 6.17
        let pdu = buildReadWriteMultipleRegistersPDU(
            readAddress: 0x0003,
            readCount: 6,
            writeAddress: 0x000E,
            writeValues: [0x00FF, 0x00FF, 0x00FF],
        )

        let expected: [UInt8] = [
            0x17, // Function code
            0x00, 0x03, // Read address
            0x00, 0x06, // Read count
            0x00, 0x0E, // Write address
            0x00, 0x03, // Write count
            0x06, // Byte count
            0x00, 0xFF, // Value 1
            0x00, 0xFF, // Value 2
            0x00, 0xFF, // Value 3
        ]

        #expect(pdu == expected)
        #expect(pdu.count == 16)
    }

    @Test("Parse Read/Write Multiple Registers response")
    func parseReadWriteMultipleRegistersResponse() throws {
        // Response contains only read data per Modbus spec
        let pdu: [UInt8] = [
            0x17, // Function code
            0x0C, // Byte count = 12 (6 registers)
            0x00, 0xFE, // Register 1
            0x0A, 0xCD, // Register 2
            0x00, 0x01, // Register 3
            0x00, 0x03, // Register 4
            0x00, 0x0D, // Register 5
            0x00, 0xFF, // Register 6
        ]

        let response = try parseReadWriteMultipleRegistersPDU(pdu)

        #expect(response.count == 6)
        #expect(response.registers[0] == 0x00FE)
        #expect(response.registers[1] == 0x0ACD)
        #expect(response.registers[5] == 0x00FF)
    }

    @Test("Parse Read/Write Multiple Registers - exception response")
    func parseReadWriteMultipleRegistersException() {
        let pdu: [UInt8] = [
            0x97, // 0x17 + 0x80
            0x03, // Illegal Data Value
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataValue)) {
            try parseReadWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Read/Write Multiple Registers - PDU too short")
    func parseReadWriteMultipleRegistersTooShort() {
        let pdu: [UInt8] = [0x17] // Only function code

        #expect(throws: PDUError.pduTooShort) {
            try parseReadWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Read/Write Multiple Registers - wrong function code")
    func parseReadWriteMultipleRegistersWrongFC() {
        let pdu: [UInt8] = [
            0x03, // Wrong FC
            0x04,
            0x00, 0x01,
            0x00, 0x02,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x17, got: 0x03)) {
            try parseReadWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Parse Read/Write Multiple Registers - odd byte count")
    func parseReadWriteMultipleRegistersOddByteCount() {
        // Byte count must be even (2 bytes per register)
        let pdu: [UInt8] = [
            0x17,
            0x03, // Odd byte count
            0x00, 0x01, 0x02,
        ]

        #expect(throws: PDUError.byteCountMismatch(expected: 3, got: 3)) {
            try parseReadWriteMultipleRegistersPDU(pdu)
        }
    }

    @Test("Build Read/Write Multiple Registers - max read count")
    func buildReadWriteMaxReadCount() {
        // Per Modbus spec: max read = 125 registers
        let pdu = buildReadWriteMultipleRegistersPDU(
            readAddress: 0,
            readCount: 125,
            writeAddress: 0,
            writeValues: [0x0001],
        )

        #expect(pdu[3] == 0x00)
        #expect(pdu[4] == 0x7D) // 125
    }

    @Test("Build Read/Write Multiple Registers - max write count")
    func buildReadWriteMaxWriteCount() {
        // Per Modbus spec: max write = 121 registers
        let writeValues = [UInt16](repeating: 0xFFFF, count: 121)
        let pdu = buildReadWriteMultipleRegistersPDU(
            readAddress: 0,
            readCount: 1,
            writeAddress: 0,
            writeValues: writeValues,
        )

        #expect(pdu[7] == 0x00)
        #expect(pdu[8] == 0x79) // 121
        #expect(pdu[9] == 0xF2) // Byte count = 242
        #expect(pdu.count == 10 + 242)
    }

    @Test("Read/Write Multiple Registers round-trip")
    func readWriteMultipleRegistersRoundTrip() throws {
        // Build request
        let requestPDU = buildReadWriteMultipleRegistersPDU(
            readAddress: 0x0100,
            readCount: 2,
            writeAddress: 0x0200,
            writeValues: [0xABCD, 0x1234],
        )

        #expect(requestPDU[0] == 0x17)
        #expect(requestPDU.count == 14) // 10 header + 4 data

        // Response contains only read registers
        let responsePDU: [UInt8] = [
            0x17,
            0x04, // 2 registers
            0x00, 0x01,
            0x00, 0x02,
        ]

        let response = try parseReadWriteMultipleRegistersPDU(responsePDU)

        #expect(response.count == 2)
        #expect(response.registers == [0x0001, 0x0002])
    }
}
