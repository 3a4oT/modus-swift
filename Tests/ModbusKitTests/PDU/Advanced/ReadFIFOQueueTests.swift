// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Read FIFO Queue (0x18).
///
/// Test vectors verified against:
/// - goburrow/modbus ReadFIFOQueue
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Read FIFO Queue PDU")
struct ReadFIFOQueueTests {
    @Test("Build Read FIFO Queue PDU")
    func buildReadFIFOQueue() {
        // Verified: goburrow/modbus ReadFIFOQueue
        let pdu = buildReadFIFOQueuePDU(address: 0x04DE)

        let expected: [UInt8] = [
            0x18, // Function code
            0x04, 0xDE, // Address
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.readFIFOQueueRequest)
    }

    @Test("Parse Read FIFO Queue response - empty")
    func parseReadFIFOQueueEmpty() throws {
        let pdu: [UInt8] = [
            0x18, // Function code
            0x00, 0x02, // Byte count = 2
            0x00, 0x00, // FIFO count = 0
        ]

        let response = try parseReadFIFOQueuePDU(pdu)

        #expect(response.fifoCount == 0)
        #expect(response.registers.isEmpty)
    }

    @Test("Parse Read FIFO Queue response - with data")
    func parseReadFIFOQueueWithData() throws {
        // Per Modbus spec example
        let pdu: [UInt8] = [
            0x18, // Function code
            0x00, 0x08, // Byte count = 8
            0x00, 0x03, // FIFO count = 3
            0x01, 0xB8, // Register 1 = 440
            0x12, 0x84, // Register 2 = 4740
            0x13, 0x22, // Register 3 = 4898
        ]

        let response = try parseReadFIFOQueuePDU(pdu)

        #expect(response.fifoCount == 3)
        #expect(response.registers.count == 3)
        #expect(response.registers[0] == 0x01B8)
        #expect(response.registers[1] == 0x1284)
        #expect(response.registers[2] == 0x1322)
    }

    @Test("Parse Read FIFO Queue - exception response")
    func parseReadFIFOQueueException() {
        let pdu: [UInt8] = [
            0x98, // 0x18 + 0x80
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseReadFIFOQueuePDU(pdu)
        }
    }

    @Test("Parse Read FIFO Queue - byte count mismatch")
    func parseReadFIFOQueueByteCountMismatch() {
        // byteCount should be 2 + fifoCount * 2
        let pdu: [UInt8] = [
            0x18,
            0x00, 0x06, // Wrong: should be 8 for 3 registers
            0x00, 0x03, // FIFO count = 3
            0x01, 0xB8,
            0x12, 0x84,
            0x13, 0x22,
        ]

        #expect(throws: PDUError.byteCountMismatch(expected: 8, got: 6)) {
            try parseReadFIFOQueuePDU(pdu)
        }
    }

    @Test("Parse Read FIFO Queue - PDU too short")
    func parseReadFIFOQueueTooShort() {
        let pdu: [UInt8] = [0x18, 0x00] // Only 2 bytes

        #expect(throws: PDUError.pduTooShort) {
            try parseReadFIFOQueuePDU(pdu)
        }
    }

    @Test("Parse Read FIFO Queue - wrong function code")
    func parseReadFIFOQueueWrongFC() {
        let pdu: [UInt8] = [
            0x03, // Wrong FC
            0x00, 0x02,
            0x00, 0x00,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x18, got: 0x03)) {
            try parseReadFIFOQueuePDU(pdu)
        }
    }

    @Test("Parse Read FIFO Queue - max count (31)")
    func parseReadFIFOQueueMaxCount() throws {
        // Max FIFO count per Modbus spec is 31
        var pdu: [UInt8] = [
            0x18,
            0x00, 0x40, // Byte count = 64
            0x00, 0x1F, // FIFO count = 31
        ]
        // Add 31 register values
        for i: UInt16 in 0 ..< 31 {
            pdu.append(UInt8(i >> 8))
            pdu.append(UInt8(i & 0xFF))
        }

        let response = try parseReadFIFOQueuePDU(pdu)

        #expect(response.fifoCount == 31)
        #expect(response.registers.count == 31)
        #expect(response.registers[0] == 0)
        #expect(response.registers[30] == 30)
    }

    @Test("Read FIFO Queue round-trip")
    func readFIFOQueueRoundTrip() throws {
        let requestPDU = buildReadFIFOQueuePDU(address: 0x1234)

        #expect(requestPDU[0] == 0x18)
        #expect(requestPDU[1] == 0x12)
        #expect(requestPDU[2] == 0x34)

        // Parse valid response
        let responsePDU: [UInt8] = [
            0x18,
            0x00, 0x04, // Byte count = 4
            0x00, 0x01, // FIFO count = 1
            0x12, 0x34, // Register value
        ]

        let response = try parseReadFIFOQueuePDU(responsePDU)

        #expect(response.fifoCount == 1)
        #expect(response.registers[0] == 0x1234)
    }
}
