// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus RTU response parsers.
///
/// Test vectors verified with Python CRC-16/MODBUS calculation.
@Suite("RTU Frame Parsers")
struct RTUFrameParserTests {
    // MARK: - Read Response Parser Tests

    @Test("Parse valid response with 3 registers")
    func parseValidResponse() throws {
        // Response: unitId=0x01, func=0x03, byteCount=6, data=[0x1234, 0x5678, 0x9ABC]
        // Verified CRC: 0x4369
        let frame: [UInt8] = [
            0x01, 0x03, 0x06,
            0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC,
            0x69, 0x43,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.unitId == 0x01)
        #expect(response.functionCode == 0x03)
        #expect(response.data == [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
        #expect(response.count == 3)
    }

    @Test("Parse single register response")
    func parseSingleRegister() throws {
        // Value 0x0155 = 341 decimal
        // Verified CRC: 0xEB79
        let frame: [UInt8] = [
            0x01, 0x03, 0x02, 0x01, 0x55, 0x79, 0xEB,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.count == 1)
        #expect(response.value(at: 0) == 0x0155)
        #expect(response.value(at: 0) == 341)
    }

    @Test("Parse battery SOC response")
    func parseBatterySOC() throws {
        // SOC 85% = 0x0055
        // Verified CRC: 0x7B78
        let frame: [UInt8] = [
            0x01, 0x03, 0x02, 0x00, 0x55, 0x78, 0x7B,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.value(at: 0) == 85)
    }

    @Test("Parse signed negative value")
    func parseSignedNegative() throws {
        // -2500W as int16 = 0xF63C
        // Verified CRC: 0xF5FF
        let frame: [UInt8] = [
            0x01, 0x03, 0x02, 0xF6, 0x3C, 0xFF, 0xF5,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.value(at: 0) == 0xF63C)
        #expect(response.signedValue(at: 0) == -2500)
    }

    @Test("Register value accessors return nil for out of bounds")
    func registerValueOutOfBounds() throws {
        // Single register 0x1234
        // Verified CRC: 0x33B5
        let frame: [UInt8] = [
            0x01, 0x03, 0x02, 0x12, 0x34, 0xB5, 0x33,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.value(at: 0) == 0x1234)
        #expect(response.value(at: 1) == nil) // Out of bounds
        #expect(response.value(at: -1) == nil) // Negative
    }

    @Test("Parse UInt32 from two registers")
    func parseUInt32() throws {
        // Two registers: 0x1234, 0x5678 = 0x12345678
        // Verified CRC: 0x0781
        let frame: [UInt8] = [
            0x01, 0x03, 0x04,
            0x12, 0x34, 0x56, 0x78,
            0x81, 0x07,
        ]

        let response = try parseRTUReadResponse(frame)

        #expect(response.uint32Value(at: 0) == 0x1234_5678)
    }

    // MARK: - Write Response Parser Tests

    @Test("Parse write single register response (FC 0x06)")
    func parseWriteSingleRegisterResponse() throws {
        // Echo response: address=0x0010, value=0x1234
        var frame: [UInt8] = [0x01, 0x06, 0x00, 0x10, 0x12, 0x34, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 6])
        frame[6] = crcLowByte(crc)
        frame[7] = crcHighByte(crc)

        let response = try parseRTUWriteResponse(
            frame,
            expectedFunction: ModbusFunctionCode.writeSingleRegister,
        )

        #expect(response.unitId == 0x01)
        #expect(response.functionCode == 0x06)
        #expect(response.address == 0x0010)
        #expect(response.value == 0x1234)

        let typed = response.toWriteSingleRegisterResponse()
        #expect(typed.address == 0x0010)
        #expect(typed.value == 0x1234)
    }

    @Test("Parse write multiple registers response (FC 0x10)")
    func parseWriteMultipleRegistersResponse() throws {
        // Response: address=0x0020, quantity=3
        var frame: [UInt8] = [0x01, 0x10, 0x00, 0x20, 0x00, 0x03, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 6])
        frame[6] = crcLowByte(crc)
        frame[7] = crcHighByte(crc)

        let response = try parseRTUWriteResponse(
            frame,
            expectedFunction: ModbusFunctionCode.writeMultipleRegisters,
        )

        #expect(response.address == 0x0020)
        #expect(response.quantity == 3)

        let typed = response.toWriteMultipleRegistersResponse()
        #expect(typed.address == 0x0020)
        #expect(typed.quantity == 3)
    }

    @Test("Parse write single coil response (FC 0x05)")
    func parseWriteSingleCoilResponse() throws {
        // Response: address=0x0005, value=ON (0xFF00)
        var frame: [UInt8] = [0x01, 0x05, 0x00, 0x05, 0xFF, 0x00, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 6])
        frame[6] = crcLowByte(crc)
        frame[7] = crcHighByte(crc)

        let response = try parseRTUWriteResponse(
            frame,
            expectedFunction: ModbusFunctionCode.writeSingleCoil,
        )

        #expect(response.address == 0x0005)
        #expect(response.value == 0xFF00)

        let typed = response.toWriteSingleCoilResponse()
        #expect(typed.address == 0x0005)
        #expect(typed.value == true)
    }

    @Test("Parse write multiple coils response (FC 0x0F)")
    func parseWriteMultipleCoilsResponse() throws {
        // Response: address=0x0000, quantity=10
        var frame: [UInt8] = [0x01, 0x0F, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 6])
        frame[6] = crcLowByte(crc)
        frame[7] = crcHighByte(crc)

        let response = try parseRTUWriteResponse(
            frame,
            expectedFunction: ModbusFunctionCode.writeMultipleCoils,
        )

        #expect(response.address == 0x0000)
        #expect(response.quantity == 10)

        let typed = response.toWriteMultipleCoilsResponse()
        #expect(typed.quantity == 10)
    }

    @Test("Parse mask write register response (FC 0x16)")
    func parseMaskWriteRegisterResponse() throws {
        // Response: address=0x0004, andMask=0x00F2, orMask=0x0025
        var frame: [UInt8] = [0x01, 0x16, 0x00, 0x04, 0x00, 0xF2, 0x00, 0x25, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 8])
        frame[8] = crcLowByte(crc)
        frame[9] = crcHighByte(crc)

        let response = try parseRTUWriteResponse(
            frame,
            expectedFunction: ModbusFunctionCode.maskWriteRegister,
        )

        #expect(response.address == 0x0004)

        let typed = response.toMaskWriteRegisterResponse()
        #expect(typed.address == 0x0004)
        #expect(typed.andMask == 0x00F2)
        #expect(typed.orMask == 0x0025)
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - illegal data address")
    func parseExceptionIllegalAddress() {
        // Function 0x83 = 0x03 + 0x80 (exception flag)
        // Exception code 0x02 = illegal data address
        // Verified CRC: 0xC0F1
        let frame: [UInt8] = [
            0x01, 0x83, 0x02, 0xC0, 0xF1,
        ]

        #expect(throws: RTUError.exceptionResponse(.illegalDataAddress)) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse exception response - illegal function")
    func parseExceptionIllegalFunction() {
        var frame: [UInt8] = [0x01, 0x83, 0x01, 0x00, 0x00]
        // Recalculate CRC
        let crc = calculateModbusCRC16(frame[0 ..< 3])
        frame[3] = crcLowByte(crc)
        frame[4] = crcHighByte(crc)

        #expect(throws: RTUError.exceptionResponse(.illegalFunction)) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse exception response - slave device busy")
    func parseExceptionBusy() {
        var frame: [UInt8] = [0x01, 0x83, 0x06, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 3])
        frame[3] = crcLowByte(crc)
        frame[4] = crcHighByte(crc)

        #expect(throws: RTUError.exceptionResponse(.slaveDeviceBusy)) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse write response exception")
    func parseWriteResponseException() {
        // Exception: FC 0x86 (0x06 + 0x80), code 0x02 (illegal data address)
        var frame: [UInt8] = [0x01, 0x86, 0x02, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 3])
        frame[3] = crcLowByte(crc)
        frame[4] = crcHighByte(crc)

        #expect(throws: RTUError.exceptionResponse(.illegalDataAddress)) {
            try parseRTUWriteResponse(frame, expectedFunction: ModbusFunctionCode.writeSingleRegister)
        }
    }

    // MARK: - Error Handling Tests

    @Test("Parse frame too short")
    func parseFrameTooShort() {
        let frame: [UInt8] = [0x01, 0x03, 0x02] // Missing data and CRC

        #expect(throws: RTUError.frameTooShort) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse empty frame")
    func parseEmptyFrame() {
        let frame: [UInt8] = []

        #expect(throws: RTUError.frameTooShort) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse invalid CRC")
    func parseInvalidCRC() {
        // Valid frame structure but wrong CRC
        let frame: [UInt8] = [
            0x01, 0x03, 0x02, 0x00, 0x55, 0x00, 0x00, // Wrong CRC
        ]

        #expect(throws: RTUError.invalidCRC) {
            try parseRTUReadResponse(frame)
        }
    }

    @Test("Parse unit ID mismatch")
    func parseUnitIdMismatch() throws {
        // Response from unit 0x02 but expecting 0x01
        var frame: [UInt8] = [0x02, 0x03, 0x02, 0x00, 0x55, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 5])
        frame[5] = crcLowByte(crc)
        frame[6] = crcHighByte(crc)

        #expect(throws: RTUError.unitIdMismatch(expected: 0x01, got: 0x02)) {
            try parseRTUReadResponse(frame, expectedUnitId: 0x01)
        }
    }

    @Test("Parse function code mismatch")
    func parseFunctionCodeMismatch() throws {
        // Response with function 0x04 but expecting 0x03
        var frame: [UInt8] = [0x01, 0x04, 0x02, 0x00, 0x55, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 5])
        frame[5] = crcLowByte(crc)
        frame[6] = crcHighByte(crc)

        #expect(throws: RTUError.unexpectedFunctionCode(expected: 0x03, got: 0x04)) {
            try parseRTUReadResponse(frame, expectedFunction: 0x03)
        }
    }

    @Test("Parse with custom expected unit ID")
    func parseCustomUnitId() throws {
        // Response from unit 0x02
        var frame: [UInt8] = [0x02, 0x03, 0x02, 0x00, 0x55, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 5])
        frame[5] = crcLowByte(crc)
        frame[6] = crcHighByte(crc)

        // Should succeed with expectedUnitId: 0x02
        let response = try parseRTUReadResponse(frame, expectedUnitId: 0x02)
        #expect(response.unitId == 0x02)
    }

    // MARK: - ArraySlice Input Tests

    @Test("Parse from ArraySlice (V5 response extraction)")
    func parseFromArraySlice() throws {
        // Simulates extracting Modbus frame from V5 response
        let v5Payload: [UInt8] = [
            0x00, 0x00, // Some V5 header bytes
            0x01, 0x03, 0x02, 0x00, 0x55, 0x78, 0x7B, // Modbus frame
            0x00, 0x00, // Some V5 trailer bytes
        ]

        let modbusSlice = v5Payload[2 ..< 9]
        let response = try parseRTUReadResponse(modbusSlice)

        #expect(response.value(at: 0) == 85)
    }

    // MARK: - Buffer Overflow Protection Tests

    @Test("Parse response with byte count larger than actual data")
    func parseByteCountOverflow() {
        // Byte count claims 10 bytes but only 2 bytes of data present
        // This should trigger frameTooShort since expected size > actual
        var frame: [UInt8] = [0x01, 0x03, 0x0A, 0x00, 0x55, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 5])
        frame[5] = crcLowByte(crc)
        frame[6] = crcHighByte(crc)

        #expect(throws: RTUError.frameTooShort) {
            try parseRTUReadResponse(frame)
        }
    }

    // MARK: - Broadcast Tests

    @Test("Parse response accepts broadcast unit ID 0")
    func parseResponseBroadcast() throws {
        // While broadcast writes don't get responses in real scenarios,
        // the parser should still handle unit ID 0 if explicitly expected
        var frame: [UInt8] = [0x00, 0x03, 0x02, 0x12, 0x34, 0x00, 0x00]
        let crc = calculateModbusCRC16(frame[0 ..< 5])
        frame[5] = crcLowByte(crc)
        frame[6] = crcHighByte(crc)

        let response = try parseRTUReadResponse(frame, expectedUnitId: 0x00)
        #expect(response.unitId == 0x00)
        #expect(response.value(at: 0) == 0x1234)
    }
}
