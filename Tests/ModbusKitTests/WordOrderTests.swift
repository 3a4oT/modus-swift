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
}
