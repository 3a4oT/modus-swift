// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for word order decoding.
///
/// Test vectors verified against pymodbus BinaryPayloadDecoder.
/// Value 0x12345678 is used as reference throughout.
@Suite("Word Order")
struct WordOrderTests {
    // MARK: - Test Value Constants

    // For 0x12345678:
    // A=0x12, B=0x34, C=0x56, D=0x78
    // AB = 0x1234 (high word, big endian)
    // CD = 0x5678 (low word, big endian)
    // BA = 0x3412 (high word, little endian bytes)
    // DC = 0x7856 (low word, little endian bytes)

    let expectedValue: UInt32 = 0x1234_5678

    // MARK: - UInt32 Decoding Tests

    @Test("AB_CD: Big Endian words, Big Endian bytes")
    func decodeABCD() {
        // Registers: [0x1234, 0x5678] → 0x12345678
        let result = decodeUInt32((0x1234, 0x5678), order: .abcd)
        #expect(result == expectedValue)
    }

    @Test("BA_DC: Big Endian words, Little Endian bytes")
    func decodeBADC() {
        // Registers: [0x3412, 0x7856] → 0x12345678
        // Each register has bytes swapped
        let result = decodeUInt32((0x3412, 0x7856), order: .badc)
        #expect(result == expectedValue)
    }

    @Test("CD_AB: Little Endian words, Big Endian bytes")
    func decodeCDAB() {
        // Registers: [0x5678, 0x1234] → 0x12345678
        // Word order swapped
        let result = decodeUInt32((0x5678, 0x1234), order: .cdab)
        #expect(result == expectedValue)
    }

    @Test("DC_BA: Little Endian words, Little Endian bytes")
    func decodeDCBA() {
        // Registers: [0x7856, 0x3412] → 0x12345678
        // Both word order and byte order swapped
        let result = decodeUInt32((0x7856, 0x3412), order: .dcba)
        #expect(result == expectedValue)
    }

    // MARK: - Edge Cases

    @Test("Decode zero")
    func decodeZero() {
        #expect(decodeUInt32((0x0000, 0x0000), order: .abcd) == 0)
        #expect(decodeUInt32((0x0000, 0x0000), order: .cdab) == 0)
        #expect(decodeUInt32((0x0000, 0x0000), order: .badc) == 0)
        #expect(decodeUInt32((0x0000, 0x0000), order: .dcba) == 0)
    }

    @Test("Decode max UInt32")
    func decodeMax() {
        #expect(decodeUInt32((0xFFFF, 0xFFFF), order: .abcd) == UInt32.max)
        #expect(decodeUInt32((0xFFFF, 0xFFFF), order: .cdab) == UInt32.max)
        #expect(decodeUInt32((0xFFFF, 0xFFFF), order: .badc) == UInt32.max)
        #expect(decodeUInt32((0xFFFF, 0xFFFF), order: .dcba) == UInt32.max)
    }

    @Test("Decode value with high word only")
    func decodeHighWordOnly() {
        // Value 0xABCD0000
        #expect(decodeUInt32((0xABCD, 0x0000), order: .abcd) == 0xABCD_0000)
        #expect(decodeUInt32((0x0000, 0xABCD), order: .cdab) == 0xABCD_0000)
    }

    @Test("Decode value with low word only")
    func decodeLowWordOnly() {
        // Value 0x0000ABCD
        #expect(decodeUInt32((0x0000, 0xABCD), order: .abcd) == 0x0000_ABCD)
        #expect(decodeUInt32((0xABCD, 0x0000), order: .cdab) == 0x0000_ABCD)
    }

    // MARK: - Int32 Decoding Tests

    @Test("Decode positive Int32")
    func decodePositiveInt32() {
        // 0x12345678 = 305419896
        let result = decodeInt32((0x1234, 0x5678), order: .abcd)
        #expect(result == 305_419_896)
    }

    @Test("Decode negative Int32")
    func decodeNegativeInt32() {
        // 0xFFFFFFFF = -1
        let result = decodeInt32((0xFFFF, 0xFFFF), order: .abcd)
        #expect(result == -1)
    }

    @Test("Decode Int32 min value")
    func decodeInt32Min() {
        // 0x80000000 = -2147483648 (Int32.min)
        let result = decodeInt32((0x8000, 0x0000), order: .abcd)
        #expect(result == Int32.min)
    }

    @Test("Decode negative Int32 with CD_AB order")
    func decodeNegativeInt32CDAB() {
        // -1000 = 0xFFFFFC18
        // AB_CD: [0xFFFF, 0xFC18]
        // CD_AB: [0xFC18, 0xFFFF]
        let result = decodeInt32((0xFC18, 0xFFFF), order: .cdab)
        #expect(result == -1000)
    }

    // MARK: - Float32 Decoding Tests

    @Test("Decode Float32 - 1.0")
    func decodeFloat1() {
        // IEEE 754: 1.0 = 0x3F800000
        // AB_CD: [0x3F80, 0x0000]
        let result = decodeFloat32((0x3F80, 0x0000), order: .abcd)
        #expect(result == 1.0)
    }

    @Test("Decode Float32 - -1.0")
    func decodeFloatNeg1() {
        // IEEE 754: -1.0 = 0xBF800000
        // AB_CD: [0xBF80, 0x0000]
        let result = decodeFloat32((0xBF80, 0x0000), order: .abcd)
        #expect(result == -1.0)
    }

    @Test("Decode Float32 - 123.456")
    func decodeFloat123() {
        // IEEE 754: 123.456 ≈ 0x42F6E979
        // AB_CD: [0x42F6, 0xE979]
        let result = decodeFloat32((0x42F6, 0xE979), order: .abcd)
        #expect(abs(result - 123.456) < 0.001)
    }

    @Test("Decode Float32 with CD_AB order")
    func decodeFloatCDAB() {
        // IEEE 754: 1.0 = 0x3F800000
        // CD_AB: [0x0000, 0x3F80]
        let result = decodeFloat32((0x0000, 0x3F80), order: .cdab)
        #expect(result == 1.0)
    }

    // MARK: - ReadRegistersResponse Extension Tests

    @Test("Response uint32Value with word order")
    func responseUInt32WithOrder() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04, // 2 registers
            0x12, 0x34, // Register 0
            0x56, 0x78, // Register 1
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.uint32Value(at: 0, order: .abcd) == 0x1234_5678)
        #expect(response.uint32Value(at: 0, order: .cdab) == 0x5678_1234)
    }

    @Test("Response int32Value with word order")
    func responseInt32WithOrder() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0xFF, 0xFF, // -1 high word
            0xFF, 0xFF, // -1 low word
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.int32Value(at: 0, order: .abcd) == -1)
        #expect(response.int32Value(at: 0, order: .cdab) == -1)
    }

    @Test("Response float32Value with word order")
    func responseFloat32WithOrder() throws {
        // 1.0 = 0x3F800000 → [0x3F80, 0x0000] in AB_CD
        let pdu: [UInt8] = [
            0x03,
            0x04,
            0x3F, 0x80, // 0x3F80
            0x00, 0x00, // 0x0000
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.float32Value(at: 0, order: .abcd) == 1.0)
    }

    @Test("Response value out of bounds returns nil")
    func responseOutOfBounds() throws {
        let pdu: [UInt8] = [
            0x03,
            0x02, // Only 1 register
            0x12, 0x34,
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.uint32Value(at: 0, order: .abcd) == nil)
        #expect(response.int32Value(at: 0, order: .abcd) == nil)
        #expect(response.float32Value(at: 0, order: .abcd) == nil)
    }

    // MARK: - Real-World Scenarios

    @Test("Deye inverter total energy (AB_CD)")
    func deyeTotalEnergy() {
        // Deye uses AB_CD (Big Endian)
        // Total energy: 12345.6 kWh stored as 123456 (scaled by 10)
        // 123456 = 0x0001E240
        let result = decodeUInt32((0x0001, 0xE240), order: .abcd)
        #expect(result == 123_456)
    }

    @Test("Modicon PLC value (CD_AB)")
    func modiconValue() {
        // Some Modicon PLCs use CD_AB (word-swapped)
        // Value: 0x12345678
        let result = decodeUInt32((0x5678, 0x1234), order: .cdab)
        #expect(result == 0x1234_5678)
    }

    // MARK: - UInt64 Decoding Tests

    @Test("64-bit AB_CD: Big Endian")
    func decode64ABCD() {
        // Value: 0x123456789ABCDEF0
        // Registers: [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let result = decodeUInt64((0x1234, 0x5678, 0x9ABC, 0xDEF0), order: .abcd)
        #expect(result == 0x1234_5678_9ABC_DEF0)
    }

    @Test("64-bit CD_AB: Little Endian words")
    func decode64CDAB() {
        // Value: 0x123456789ABCDEF0
        // CD_AB: r0 is LSW, r3 is MSW
        // Registers: [0xDEF0, 0x9ABC, 0x5678, 0x1234]
        let result = decodeUInt64((0xDEF0, 0x9ABC, 0x5678, 0x1234), order: .cdab)
        #expect(result == 0x1234_5678_9ABC_DEF0)
    }

    @Test("64-bit decode zero")
    func decode64Zero() {
        #expect(decodeUInt64((0, 0, 0, 0), order: .abcd) == 0)
        #expect(decodeUInt64((0, 0, 0, 0), order: .cdab) == 0)
    }

    @Test("64-bit decode max")
    func decode64Max() {
        #expect(decodeUInt64((0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF), order: .abcd) == UInt64.max)
    }

    @Test("Int64 negative value")
    func decode64Negative() {
        // -1 = 0xFFFFFFFFFFFFFFFF
        let result = decodeInt64((0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF), order: .abcd)
        #expect(result == -1)
    }

    @Test("Float64 decode 1.0")
    func decode64Float1() {
        // IEEE 754 double: 1.0 = 0x3FF0000000000000
        // AB_CD: [0x3FF0, 0x0000, 0x0000, 0x0000]
        let result = decodeFloat64((0x3FF0, 0x0000, 0x0000, 0x0000), order: .abcd)
        #expect(result == 1.0)
    }

    // MARK: - Response 64-bit Extension Tests

    @Test("Response uint64Value")
    func responseUInt64() throws {
        let pdu: [UInt8] = [
            0x03,
            0x08, // 4 registers
            0x12, 0x34,
            0x56, 0x78,
            0x9A, 0xBC,
            0xDE, 0xF0,
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.uint64Value(at: 0, order: .abcd) == 0x1234_5678_9ABC_DEF0)
    }

    @Test("Response uint64Value out of bounds")
    func responseUInt64OutOfBounds() throws {
        let pdu: [UInt8] = [
            0x03,
            0x04, // Only 2 registers
            0x12, 0x34,
            0x56, 0x78,
        ]

        let response = try parseReadRegistersPDU(pdu)

        #expect(response.uint64Value(at: 0, order: .abcd) == nil)
    }

    // MARK: - RegisterArray Tests

    @Test("decodeRegistersLE with 2 registers")
    func decodeRegistersLE2() {
        // Device Alarm: 2 registers, bit 1 set (Fan failure)
        let registers: [UInt16] = [0x0002, 0x0000]
        let result = decodeRegistersLE(registers)
        #expect(result == 0x0000_0002)
    }

    @Test("decodeRegistersLE with 4 registers")
    func decodeRegistersLE4() {
        // Device Fault: 4 registers, bit 6 set
        let registers: [UInt16] = [0x0040, 0x0000, 0x0000, 0x0000]
        let result = decodeRegistersLE(registers)
        #expect(result == 0x0000_0040)
    }

    @Test("decodeRegistersLE with single register")
    func decodeRegistersLE1() {
        let registers: [UInt16] = [0xABCD]
        let result = decodeRegistersLE(registers)
        #expect(result == 0xABCD)
    }

    @Test("decodeRegistersLE empty returns nil")
    func decodeRegistersLEEmpty() {
        let registers: [UInt16] = []
        #expect(decodeRegistersLE(registers) == nil)
    }

    @Test("decodeRegistersBE with 2 registers")
    func decodeRegistersBE2() {
        // Big Endian: [0x1234, 0x5678] → 0x12345678
        let registers: [UInt16] = [0x1234, 0x5678]
        let result = decodeRegistersBE(registers)
        #expect(result == 0x1234_5678)
    }

    @Test("Array extension uint64LE")
    func arrayExtensionLE() {
        let registers: [UInt16] = [0xDEF0, 0x9ABC, 0x5678, 0x1234]
        #expect(registers.uint64LE == 0x1234_5678_9ABC_DEF0)
    }

    @Test("Array extension uint64BE")
    func arrayExtensionBE() {
        let registers: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        #expect(registers.uint64BE == 0x1234_5678_9ABC_DEF0)
    }

    // MARK: - Real-World Alarm/Fault Scenarios

    @Test("Deye Device Alarm - Fan failure (bit 1)")
    func deyeDeviceAlarmFanFailure() {
        // Registers: [0x0065, 0x0066] = 2 registers
        // Bit 1 set = Fan failure
        let registers: [UInt16] = [0x0002, 0x0000]
        let bits = decodeRegistersLE(registers)!

        #expect((bits & (1 << 1)) != 0) // Bit 1 is set
        #expect((bits & (1 << 2)) == 0) // Bit 2 is not set
    }

    @Test("Deye Device Fault - DC/DC Soft Start (bit 6)")
    func deyeDeviceFaultDCDC() {
        // Registers: [0x0067, 0x0068, 0x0069, 0x006A] = 4 registers
        // Bit 6 set = DC/DC Soft Start failure
        let registers: [UInt16] = [0x0040, 0x0000, 0x0000, 0x0000]
        let bits = decodeRegistersLE(registers)!

        #expect((bits & (1 << 6)) != 0) // Bit 6 is set
    }

    @Test("Deye Device Fault - Temperature high (bit 63)")
    func deyeDeviceFaultTemperature() {
        // Bit 63 = Temperature is too high
        // In LE: bit 63 is in the MSW (register 3), bit 15
        let registers: [UInt16] = [0x0000, 0x0000, 0x0000, 0x8000]
        let bits = decodeRegistersLE(registers)!

        #expect((bits & (1 << 63)) != 0) // Bit 63 is set
    }
}
