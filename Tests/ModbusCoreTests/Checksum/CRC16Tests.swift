// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus CRC-16 calculation
///
/// Algorithm: CRC-16/MODBUS
/// - Polynomial: 0x8005 (reversed: 0xA001)
/// - Initial: 0xFFFF
/// - Check value: 0x4B37 for "123456789"
///
/// References:
/// - https://crccalc.com/?method=CRC-16/MODBUS
/// - Modbus Serial Line Protocol V1.02
@Suite("Modbus CRC-16")
struct CRC16Tests {
    // MARK: - Standard Check Value

    @Test("Check value for '123456789' is 0x4B37")
    func standardCheckValue() {
        // ASCII "123456789" = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        let input: [UInt8] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        let crc = calculateModbusCRC16(input)
        #expect(crc == 0x4B37)
    }

    // MARK: - Basic Cases

    @Test("Empty input returns initial value 0xFFFF")
    func emptyInput() {
        let crc = calculateModbusCRC16([UInt8]())
        #expect(crc == 0xFFFF)
    }

    @Test("Single byte 0x00")
    func singleByteZero() {
        // Calculated: 0xFFFF ^ 0x00, then 8 iterations
        // Result: 0x40BF
        let crc = calculateModbusCRC16([0x00])
        #expect(crc == 0x40BF)
    }

    @Test("Single byte 0xFF")
    func singleByteFF() {
        // Verified via Python CRC-16/MODBUS implementation
        let crc = calculateModbusCRC16([0xFF])
        #expect(crc == 0x00FF)
    }

    // MARK: - Modbus Frame Examples

    @Test("Read Holding Registers request: 01 03 00 00 00 0A")
    func readHoldingRegistersRequest() {
        // Slave 1, Function 3, Start 0, Count 10
        let frame: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        let crc = calculateModbusCRC16(frame)

        // Expected CRC: 0xC5CD (low: 0xC5, high: 0xCD)
        #expect(crc == 0xCDC5)
        #expect(crcLowByte(crc) == 0xC5)
        #expect(crcHighByte(crc) == 0xCD)
    }

    @Test("Read Holding Registers request: 01 03 00 6B 00 03")
    func readHoldingRegistersRequest2() {
        // Slave 1, Function 3, Start 0x006B, Count 3
        let frame: [UInt8] = [0x01, 0x03, 0x00, 0x6B, 0x00, 0x03]
        let crc = calculateModbusCRC16(frame)

        // Verified via Python CRC-16/MODBUS: 0x1774 (low: 0x74, high: 0x17)
        #expect(crc == 0x1774)
        #expect(crcLowByte(crc) == 0x74)
        #expect(crcHighByte(crc) == 0x17)
    }

    // MARK: - CRC Byte Extraction

    @Test("CRC byte extraction")
    func crcByteExtraction() {
        let crc: UInt16 = 0xABCD
        #expect(crcLowByte(crc) == 0xCD)
        #expect(crcHighByte(crc) == 0xAB)
    }

    // MARK: - Frame Verification

    @Test("Verify valid frame")
    func verifyValidFrame() {
        // Frame with correct CRC appended
        let frame: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0xC5, 0xCD]
        #expect(verifyModbusCRC(frame) == true)
    }

    @Test("Verify invalid frame - wrong CRC")
    func verifyInvalidFrame() {
        // Frame with wrong CRC
        let frame: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00]
        #expect(verifyModbusCRC(frame) == false)
    }

    @Test("Verify frame too short")
    func verifyFrameTooShort() {
        #expect(verifyModbusCRC([UInt8]()) == false)
        #expect(verifyModbusCRC([0x01]) == false)
        #expect(verifyModbusCRC([0x01, 0x03]) == false)
    }

    // MARK: - Append CRC

    @Test("Append CRC to frame")
    func appendCRC() {
        let frame: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        let frameWithCRC = appendModbusCRC(frame)

        #expect(frameWithCRC.count == 8)
        #expect(frameWithCRC[6] == 0xC5) // CRC low
        #expect(frameWithCRC[7] == 0xCD) // CRC high

        // Verify the result
        #expect(verifyModbusCRC(frameWithCRC) == true)
    }

    // MARK: - Span Input

    @Test("Span input works correctly")
    func spanInput() {
        let array: [UInt8] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]
        let result = array.withUnsafeBufferPointer { buffer in
            let span = Span<UInt8>(_unsafeStart: buffer.baseAddress!, count: buffer.count)
            return calculateModbusCRC16(span)
        }
        #expect(result == 0x4B37)
    }

    // MARK: - ArraySlice Input

    @Test("ArraySlice input works correctly")
    func arraySliceInput() {
        // Full frame with CRC
        let fullFrame: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0xC5, 0xCD]
        // Calculate CRC only over data portion
        let dataSlice = fullFrame[0 ..< 6]
        let crc = calculateModbusCRC16(dataSlice)
        #expect(crc == 0xCDC5)
    }
}
