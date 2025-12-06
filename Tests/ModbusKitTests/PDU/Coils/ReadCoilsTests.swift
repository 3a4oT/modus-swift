// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Read Coils (0x01) and Read Discrete Inputs (0x02).
///
/// Test vectors verified against:
/// - pymodbus test suite
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Read Coils PDU")
struct ReadCoilsTests {
    // MARK: - Read Coils (0x01) Tests

    @Test("Build Read Coils PDU")
    func buildReadCoils() {
        // Verified: pymodbus ReadCoilsRequest(0, 19).encode()
        let pdu = buildReadCoilsPDU(address: 0x0013, count: 0x0013)

        let expected: [UInt8] = [
            0x01, // Function code
            0x00, 0x13, // Starting address (BE)
            0x00, 0x13, // Quantity of coils (BE)
        ]

        #expect(pdu == expected)
        #expect(pdu.count == PDUSize.readRequest)
    }

    @Test("Build Read Coils PDU - max count")
    func buildReadCoilsMaxCount() {
        // Per Modbus spec: max 2000 coils (MODBUS_MAX_READ_BITS)
        // Reference: libmodbus modbus.h
        let pdu = buildReadCoilsPDU(address: 0, count: ModbusLimits.maxReadCoils)

        #expect(pdu[3] == 0x07) // 2000 = 0x07D0
        #expect(pdu[4] == 0xD0)
        #expect(pdu.count == PDUSize.readRequest)
    }

    @Test("Build Read Coils PDU - boundary count values")
    func buildReadCoilsBoundaryCount() {
        // Test boundary values per libmodbus send_crafted_request approach
        // Reference: libmodbus tests/unit-test-client.c

        // Count = 1 (minimum valid)
        let pdu1 = buildReadCoilsPDU(address: 0, count: 1)
        #expect(pdu1[3] == 0x00)
        #expect(pdu1[4] == 0x01)

        // Count = 2000 (maximum valid per Modbus spec)
        let pduMax = buildReadCoilsPDU(address: 0, count: 2000)
        #expect(pduMax[3] == 0x07)
        #expect(pduMax[4] == 0xD0)
    }

    @Test("Parse Read Coils response")
    func parseReadCoilsResponse() throws {
        // Response: 19 coils, CD 6B 05 = 1100 1101, 0110 1011, 0000 0101
        let pdu: [UInt8] = [
            0x01, // Function code
            0x03, // Byte count
            0xCD, 0x6B, 0x05,
        ]

        let response = try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 19)

        #expect(response.functionCode == 0x01)
        #expect(response.byteCount == 3)
        #expect(response.count == 19)
        // Verify LSB-first bit unpacking
        // 0xCD = 1100 1101 → bits 0-7: true,false,true,true,false,false,true,true
        #expect(response.bits[0] == true) // bit 0 of 0xCD
        #expect(response.bits[1] == false) // bit 1 of 0xCD
        #expect(response.bits[7] == true) // bit 7 of 0xCD
    }

    @Test("Parse Read Coils - exception response")
    func parseReadCoilsException() {
        let pdu: [UInt8] = [
            0x81, // 0x01 + 0x80
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 10)
        }
    }

    @Test("Parse Read Coils - PDU too short")
    func parseReadCoilsTooShort() {
        let pdu: [UInt8] = [0x01] // Only function code

        #expect(throws: PDUError.pduTooShort) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 10)
        }
    }

    @Test("Parse Read Coils - wrong function code")
    func parseReadCoilsWrongFC() {
        let pdu: [UInt8] = [
            0x02, // Wrong FC (should be 0x01)
            0x01,
            0xFF,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x01, got: 0x02)) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 8)
        }
    }

    @Test("Parse Read Coils - byte count mismatch")
    func parseReadCoilsByteCountMismatch() {
        // Request 19 coils → need 3 bytes, but response says 2
        let pdu: [UInt8] = [
            0x01,
            0x02, // Wrong: should be 3 for 19 coils
            0xCD, 0x6B,
        ]

        #expect(throws: PDUError.byteCountMismatch(expected: 3, got: 2)) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 19)
        }
    }

    @Test("Read Coils round-trip")
    func readCoilsRoundTrip() throws {
        let requestPDU = buildReadCoilsPDU(address: 0x0100, count: 8)

        #expect(requestPDU[0] == 0x01)
        #expect(requestPDU.count == 5)

        // Response for 8 coils (1 byte)
        let responsePDU: [UInt8] = [
            0x01,
            0x01, // 1 byte for 8 coils
            0xAA, // 1010 1010
        ]

        let response = try parseReadBitsPDU(responsePDU, expectedFunction: 0x01, requestedCount: 8)

        #expect(response.count == 8)
        #expect(response.value(at: 0) == false) // bit 0 of 0xAA
        #expect(response.value(at: 1) == true) // bit 1 of 0xAA
        #expect(response.value(at: 7) == true) // bit 7 of 0xAA
    }

    @Test("ReadBitsResponse value accessor")
    func readBitsResponseValueAccessor() throws {
        let pdu: [UInt8] = [0x01, 0x01, 0xFF]
        let response = try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 8)

        #expect(response.value(at: 0) == true)
        #expect(response.value(at: 7) == true)
        #expect(response.value(at: 8) == nil) // Out of bounds
        #expect(response.value(at: -1) == nil) // Negative index
    }

    // MARK: - Maximum Coil Response Parsing Tests

    @Test("Parse maximum coil response (2000 coils)")
    func parseMaximumCoilResponse() throws {
        // Test parsing response with maximum valid coils per Modbus spec
        // 2000 coils = ceil(2000/8) = 250 bytes
        // Reference: libmodbus MODBUS_MAX_READ_BITS = 2000
        let byteCount: UInt8 = 250 // 2000 coils / 8 = 250 bytes

        var pdu: [UInt8] = [
            0x01, // Function code
            byteCount, // Byte count
        ]

        // Fill with alternating pattern (0xAA = 10101010)
        for _ in 0 ..< Int(byteCount) {
            pdu.append(0xAA)
        }

        let response = try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 2000)

        #expect(response.functionCode == 0x01)
        #expect(response.byteCount == 250)
        #expect(response.count == 2000)

        // Verify bit pattern (0xAA = 10101010, LSB first: false,true,false,true,...)
        #expect(response.bits[0] == false) // bit 0
        #expect(response.bits[1] == true) // bit 1
        #expect(response.bits[1999] == true) // last bit (1999 % 8 = 7, bit 7 of 0xAA)
    }

    @Test("Parse coil response - byte count boundary (max UInt8)")
    func parseCoilResponseByteCountBoundary() throws {
        // Test that byteCount 250 (max for 2000 coils) works correctly
        // This is the largest valid byteCount for coil responses
        // byteCount = 250 fits in UInt8 (max 255)
        let byteCount: UInt8 = 250

        var pdu: [UInt8] = [0x01, byteCount]
        pdu.append(contentsOf: [UInt8](repeating: 0xFF, count: Int(byteCount)))

        let response = try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 2000)

        // All bits should be true (0xFF = 11111111)
        #expect(response.bits.allSatisfy { $0 == true })
        #expect(response.count == 2000)
    }

    // MARK: - Read Discrete Inputs (0x02) Tests

    @Test("Build Read Discrete Inputs PDU")
    func buildReadDiscreteInputs() {
        // Verified: pymodbus ReadDiscreteInputsRequest(0x00C4, 22).encode()
        let pdu = buildReadDiscreteInputsPDU(address: 0x00C4, count: 22)

        let expected: [UInt8] = [
            0x02, // Function code
            0x00, 0xC4, // Starting address
            0x00, 0x16, // Quantity (22)
        ]

        #expect(pdu == expected)
    }

    @Test("Parse Read Discrete Inputs response")
    func parseReadDiscreteInputsResponse() throws {
        // Response: 22 inputs, AC DB 35 = 1010 1100, 1101 1011, 0011 0101
        let pdu: [UInt8] = [
            0x02,
            0x03, // 3 bytes for 22 inputs
            0xAC, 0xDB, 0x35,
        ]

        let response = try parseReadBitsPDU(pdu, expectedFunction: 0x02, requestedCount: 22)

        #expect(response.functionCode == 0x02)
        #expect(response.count == 22)
    }

    @Test("Parse Read Discrete Inputs - exception response")
    func parseReadDiscreteInputsException() {
        let pdu: [UInt8] = [
            0x82, // 0x02 + 0x80
            0x01, // Illegal Function
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x02, requestedCount: 10)
        }
    }

    @Test("Parse Read Discrete Inputs - wrong function code")
    func parseReadDiscreteInputsWrongFC() {
        let pdu: [UInt8] = [
            0x01, // Wrong FC
            0x01,
            0xFF,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x02, got: 0x01)) {
            try parseReadBitsPDU(pdu, expectedFunction: 0x02, requestedCount: 8)
        }
    }

    @Test("Read Discrete Inputs round-trip")
    func readDiscreteInputsRoundTrip() throws {
        let requestPDU = buildReadDiscreteInputsPDU(address: 0x0000, count: 16)

        #expect(requestPDU[0] == 0x02)

        let responsePDU: [UInt8] = [
            0x02,
            0x02, // 2 bytes for 16 inputs
            0xFF, 0x00,
        ]

        let response = try parseReadBitsPDU(responsePDU, expectedFunction: 0x02, requestedCount: 16)

        #expect(response.count == 16)
        // First byte all true, second all false
        for i in 0 ..< 8 {
            #expect(response.bits[i] == true)
        }
        for i in 8 ..< 16 {
            #expect(response.bits[i] == false)
        }
    }
}
