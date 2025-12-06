// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for Write Single Coil (0x05) and Write Multiple Coils (0x0F).
///
/// Test vectors verified against:
/// - pymodbus test suite
/// - Modbus Application Protocol Specification V1.1b3
@Suite("Write Coils PDU")
struct WriteCoilsTests {
    // MARK: - Write Single Coil (0x05) Tests

    @Test("Build Write Single Coil PDU - ON")
    func buildWriteSingleCoilOn() {
        // Verified: pymodbus WriteSingleCoilRequest(0x00AC, True).encode()
        let pdu = buildWriteSingleCoilPDU(address: 0x00AC, value: true)

        let expected: [UInt8] = [
            0x05, // Function code
            0x00, 0xAC, // Output address
            0xFF, 0x00, // ON value
        ]

        #expect(pdu == expected)
    }

    @Test("Build Write Single Coil PDU - OFF")
    func buildWriteSingleCoilOff() {
        let pdu = buildWriteSingleCoilPDU(address: 0x00AC, value: false)

        let expected: [UInt8] = [
            0x05,
            0x00, 0xAC,
            0x00, 0x00, // OFF value
        ]

        #expect(pdu == expected)
    }

    @Test("Parse Write Single Coil response")
    func parseWriteSingleCoilResponse() throws {
        // Response is echo of request
        let pdu: [UInt8] = [
            0x05,
            0x00, 0xAC,
            0xFF, 0x00,
        ]

        let response = try parseWriteSingleCoilPDU(pdu)

        #expect(response.address == 0x00AC)
        #expect(response.value == true)
    }

    @Test("Parse Write Single Coil - OFF response")
    func parseWriteSingleCoilOffResponse() throws {
        let pdu: [UInt8] = [
            0x05,
            0x00, 0xAC,
            0x00, 0x00,
        ]

        let response = try parseWriteSingleCoilPDU(pdu)

        #expect(response.value == false)
    }

    @Test("Parse Write Single Coil - exception response")
    func parseWriteSingleCoilException() {
        let pdu: [UInt8] = [
            0x85, // 0x05 + 0x80
            0x02, // Illegal Data Address
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseWriteSingleCoilPDU(pdu)
        }
    }

    @Test("Parse Write Single Coil - PDU too short")
    func parseWriteSingleCoilTooShort() {
        let pdu: [UInt8] = [0x05, 0x00, 0xAC] // Only 3 bytes, need 5

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteSingleCoilPDU(pdu)
        }
    }

    @Test("Parse Write Single Coil - wrong function code")
    func parseWriteSingleCoilWrongFC() {
        let pdu: [UInt8] = [
            0x06, // Wrong FC
            0x00, 0xAC,
            0xFF, 0x00,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x05, got: 0x06)) {
            try parseWriteSingleCoilPDU(pdu)
        }
    }

    @Test("Write Single Coil round-trip")
    func writeSingleCoilRoundTrip() throws {
        let requestPDU = buildWriteSingleCoilPDU(address: 0x1234, value: true)

        // Response is echo
        let response = try parseWriteSingleCoilPDU(requestPDU)

        #expect(response.address == 0x1234)
        #expect(response.value == true)
    }

    // MARK: - Write Multiple Coils (0x0F) Tests

    @Test("Build Write Multiple Coils PDU")
    func buildWriteMultipleCoils() {
        // Verified: pymodbus WriteMultipleCoilsRequest(0x0013, [True,False,True,True,False,False,True,True,True,False]).encode()
        let values: [Bool] = [true, false, true, true, false, false, true, true, true, false]
        let pdu = buildWriteMultipleCoilsPDU(address: 0x0013, values: values)

        let expected: [UInt8] = [
            0x0F, // Function code
            0x00, 0x13, // Starting address
            0x00, 0x0A, // Quantity (10)
            0x02, // Byte count
            0xCD, // 1100 1101 (LSB first: true,false,true,true,false,false,true,true)
            0x01, // 0000 0001 (LSB first: true,false + padding)
        ]

        #expect(pdu == expected)
    }

    @Test("Build Write Multiple Coils - single coil")
    func buildWriteMultipleCoilsSingle() {
        let pdu = buildWriteMultipleCoilsPDU(address: 0, values: [true])

        #expect(pdu[0] == 0x0F)
        #expect(pdu[3] == 0x00)
        #expect(pdu[4] == 0x01) // Quantity = 1
        #expect(pdu[5] == 0x01) // Byte count = 1
        #expect(pdu[6] == 0x01) // Value
    }

    @Test("Build Write Multiple Coils - max count (1968)")
    func buildWriteMultipleCoilsMaxCount() {
        // Per Modbus spec: max 1968 coils (MODBUS_MAX_WRITE_BITS)
        // Reference: libmodbus modbus.h
        // 1968 coils = ceil(1968/8) = 246 bytes
        let values = [Bool](repeating: true, count: Int(ModbusLimits.maxWriteCoils))
        let pdu = buildWriteMultipleCoilsPDU(address: 0, values: values)

        #expect(pdu[0] == 0x0F) // Function code
        #expect(pdu[3] == 0x07) // 1968 = 0x07B0 high byte
        #expect(pdu[4] == 0xB0) // 1968 = 0x07B0 low byte
        #expect(pdu[5] == 246) // Byte count = ceil(1968/8) = 246

        // Total PDU size: FC(1) + addr(2) + qty(2) + byteCount(1) + data(246) = 252 bytes
        #expect(pdu.count == 252)
    }

    @Test("Build Write Multiple Coils - boundary values")
    func buildWriteMultipleCoilsBoundary() {
        // Test boundary values per libmodbus approach
        // Reference: libmodbus tests/unit-test-client.c

        // Count = 1 (minimum valid)
        let pdu1 = buildWriteMultipleCoilsPDU(address: 0, values: [true])
        #expect(pdu1[3] == 0x00)
        #expect(pdu1[4] == 0x01) // Quantity = 1

        // Count = 8 (exactly 1 byte)
        let pdu8 = buildWriteMultipleCoilsPDU(address: 0, values: [Bool](repeating: true, count: 8))
        #expect(pdu8[5] == 0x01) // Byte count = 1

        // Count = 9 (spans 2 bytes)
        let pdu9 = buildWriteMultipleCoilsPDU(address: 0, values: [Bool](repeating: true, count: 9))
        #expect(pdu9[5] == 0x02) // Byte count = 2
    }

    @Test("Parse Write Multiple Coils response")
    func parseWriteMultipleCoilsResponse() throws {
        let pdu: [UInt8] = [
            0x0F, // Function code
            0x00, 0x13, // Starting address
            0x00, 0x0A, // Quantity (10)
        ]

        let response = try parseWriteMultipleCoilsPDU(pdu)

        #expect(response.address == 0x0013)
        #expect(response.quantity == 10)
    }

    @Test("Parse Write Multiple Coils - exception response")
    func parseWriteMultipleCoilsException() {
        let pdu: [UInt8] = [
            0x8F, // 0x0F + 0x80
            0x03, // Illegal Data Value
        ]

        #expect(throws: PDUError.exceptionResponse(.illegalDataValue)) {
            try parseWriteMultipleCoilsPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Coils - PDU too short")
    func parseWriteMultipleCoilsTooShort() {
        let pdu: [UInt8] = [0x0F, 0x00, 0x13, 0x00] // Only 4 bytes, need 5

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteMultipleCoilsPDU(pdu)
        }
    }

    @Test("Parse Write Multiple Coils - wrong function code")
    func parseWriteMultipleCoilsWrongFC() {
        let pdu: [UInt8] = [
            0x05, // Wrong FC
            0x00, 0x13,
            0x00, 0x0A,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x0F, got: 0x05)) {
            try parseWriteMultipleCoilsPDU(pdu)
        }
    }

    @Test("Write Multiple Coils round-trip")
    func writeMultipleCoilsRoundTrip() throws {
        let values: [Bool] = [true, true, false, false, true, true, false, false]
        let requestPDU = buildWriteMultipleCoilsPDU(address: 0x0100, values: values)

        #expect(requestPDU[0] == 0x0F)
        #expect(requestPDU[4] == 0x08) // 8 coils

        let responsePDU: [UInt8] = [
            0x0F,
            0x01, 0x00, // Address
            0x00, 0x08, // Quantity
        ]

        let response = try parseWriteMultipleCoilsPDU(responsePDU)

        #expect(response.address == 0x0100)
        #expect(response.quantity == 8)
    }
}
