// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Mask Write Register (0x16).
///
/// Test vectors verified against:
/// - goburrow/modbus ClientTestMaskWriteRegisters
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Mask Write Register PDU")
struct MaskWriteRegisterTests {
    @Test("Build Mask Write Register PDU")
    func buildMaskWriteRegister() {
        // Test vector: goburrow/modbus ClientTestMaskWriteRegisters
        let pdu = buildMaskWriteRegisterPDU(address: 0x0004, andMask: 0x00F2, orMask: 0x0025)

        let expected: [UInt8] = [
            0x16, // Function code
            0x00, 0x04, // Address
            0x00, 0xF2, // AND mask
            0x00, 0x25, // OR mask
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.maskWriteRegister)
    }

    @Test("Parse Mask Write Register response")
    func parseMaskWriteRegisterResponse() throws {
        // Response is echo of request per Modbus spec
        let pdu: [UInt8] = [
            0x16, // Function code
            0x00, 0x04, // Address
            0x00, 0xF2, // AND mask
            0x00, 0x25, // OR mask
        ]

        let response = try parseMaskWriteRegisterPDU(pdu)

        #expect(response.address == 0x0004)
        #expect(response.andMask == 0x00F2)
        #expect(response.orMask == 0x0025)
    }

    @Test("Parse Mask Write Register - exception response")
    func parseMaskWriteRegisterException() {
        let pdu: [UInt8] = [
            0x96, // 0x16 + 0x80
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseMaskWriteRegisterPDU(pdu)
        }
    }

    @Test("Parse Mask Write Register - PDU too short")
    func parseMaskWriteRegisterTooShort() {
        let pdu: [UInt8] = [0x16, 0x00, 0x04] // Only 3 bytes, need 7

        #expect(throws: PDUError.pduTooShort) {
            try parseMaskWriteRegisterPDU(pdu)
        }
    }

    @Test("Parse Mask Write Register - wrong function code")
    func parseMaskWriteRegisterWrongFC() {
        let pdu: [UInt8] = [
            0x06, // Wrong FC
            0x00, 0x04,
            0x00, 0xF2,
            0x00, 0x25,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x16, got: 0x06)) {
            try parseMaskWriteRegisterPDU(pdu)
        }
    }

    @Test("Mask Write Register round-trip")
    func maskWriteRegisterRoundTrip() throws {
        let requestPDU = buildMaskWriteRegisterPDU(address: 0x1234, andMask: 0xFF00, orMask: 0x00FF)

        // Response is echo of request
        let response = try parseMaskWriteRegisterPDU(requestPDU)

        #expect(response.address == 0x1234)
        #expect(response.andMask == 0xFF00)
        #expect(response.orMask == 0x00FF)
    }

    @Test("Build Mask Write Register - boundary values")
    func buildMaskWriteRegisterBoundary() {
        // Max address and masks
        let pdu = buildMaskWriteRegisterPDU(address: 0xFFFF, andMask: 0xFFFF, orMask: 0xFFFF)

        #expect(pdu[1] == 0xFF)
        #expect(pdu[2] == 0xFF)
        #expect(pdu[3] == 0xFF)
        #expect(pdu[4] == 0xFF)
        #expect(pdu[5] == 0xFF)
        #expect(pdu[6] == 0xFF)
    }
}
