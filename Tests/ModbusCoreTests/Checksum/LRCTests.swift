// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus LRC (Longitudinal Redundancy Check) calculation.
///
/// Algorithm: Two's complement of sum of all bytes
/// - Sum all message bytes
/// - Return two's complement (-sum)
///
/// References:
/// - Modbus Serial Line Protocol V1.02, Section 2.5.1.2
/// - libmodbus `lcr8()` implementation
/// - https://www.modbustools.com/modbus.html
@Suite("Modbus LRC")
struct LRCTests {
    // MARK: - Specification Examples

    @Test("Spec example: F7 03 13 89 00 0A → LRC 60")
    func specExample() {
        // From Modbus spec: Address=247, Function=3, Data=19,137,0,10
        // Hex: F7 03 13 89 00 0A
        // Sum: 247 + 3 + 19 + 137 + 0 + 10 = 416 = 0x1A0
        // Two's complement of 0xA0 = 0x60
        let message: [UInt8] = [0xF7, 0x03, 0x13, 0x89, 0x00, 0x0A]
        let lrc = calculateModbusLRC(message)
        #expect(lrc == 0x60)
    }

    @Test("modbustools.com example: 04 01 00 0A 00 0D → LRC E4")
    func modbustoolsExample() {
        // Read 13 coils starting at address 10 from slave 4
        // Frame: :040100 0A00 0DE4 CRLF
        let message: [UInt8] = [0x04, 0x01, 0x00, 0x0A, 0x00, 0x0D]
        let lrc = calculateModbusLRC(message)
        #expect(lrc == 0xE4)
    }

    // MARK: - Basic Cases

    @Test("Empty input returns 0")
    func emptyInput() {
        let lrc = calculateModbusLRC([UInt8]())
        #expect(lrc == 0)
    }

    @Test("Single byte 0x00 returns 0")
    func singleByteZero() {
        // Sum = 0, -0 = 0
        let lrc = calculateModbusLRC([0x00])
        #expect(lrc == 0x00)
    }

    @Test("Single byte 0x01 returns 0xFF")
    func singleByteOne() {
        // Sum = 1, two's complement = 0xFF
        let lrc = calculateModbusLRC([0x01])
        #expect(lrc == 0xFF)
    }

    @Test("Single byte 0xFF returns 0x01")
    func singleByteFF() {
        // Sum = 0xFF, two's complement: ~0xFF + 1 = 0x00 + 1 = 0x01
        let lrc = calculateModbusLRC([0xFF])
        #expect(lrc == 0x01)
    }

    @Test("Two bytes 0x80 0x80 returns 0")
    func overflow() {
        // Sum = 0x80 + 0x80 = 0x100, but only keep lower 8 bits = 0x00
        // Two's complement of 0x00 = 0x00
        let lrc = calculateModbusLRC([0x80, 0x80])
        #expect(lrc == 0x00)
    }

    // MARK: - Modbus Frame Examples

    @Test("Read Holding Registers request: 01 03 00 00 00 0A")
    func readHoldingRegistersRequest() {
        // Slave 1, Function 3, Start 0, Count 10
        let message: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        // Sum: 1 + 3 + 0 + 0 + 0 + 10 = 14 = 0x0E
        // Two's complement: -14 = 0xF2
        let lrc = calculateModbusLRC(message)
        #expect(lrc == 0xF2)
    }

    @Test("Write Single Register request: 01 06 00 01 00 03")
    func writeSingleRegisterRequest() {
        // Slave 1, Function 6, Address 1, Value 3
        let message: [UInt8] = [0x01, 0x06, 0x00, 0x01, 0x00, 0x03]
        // Sum: 1 + 6 + 0 + 1 + 0 + 3 = 11 = 0x0B
        // Two's complement: -11 = 0xF5
        let lrc = calculateModbusLRC(message)
        #expect(lrc == 0xF5)
    }

    // MARK: - LRC Verification

    @Test("Verify valid message with LRC")
    func verifyValid() {
        // Message + LRC should sum to zero
        let message: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        let lrc = calculateModbusLRC(message)
        let messageWithLRC = message + [lrc]
        #expect(verifyModbusLRC(messageWithLRC) == true)
    }

    @Test("Verify invalid message - wrong LRC")
    func verifyInvalid() {
        let message: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A, 0x00]
        #expect(verifyModbusLRC(message) == false)
    }

    @Test("Verify message too short")
    func verifyTooShort() {
        #expect(verifyModbusLRC([UInt8]()) == false)
        #expect(verifyModbusLRC([0x01]) == false)
    }

    @Test("Verify spec example with LRC appended")
    func verifySpecExample() {
        // F7 03 13 89 00 0A 60
        let messageWithLRC: [UInt8] = [0xF7, 0x03, 0x13, 0x89, 0x00, 0x0A, 0x60]
        #expect(verifyModbusLRC(messageWithLRC) == true)
    }

    // MARK: - Append LRC

    @Test("Append LRC to message")
    func appendLRC() {
        let message: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        let messageWithLRC = appendModbusLRC(message)

        #expect(messageWithLRC.count == 7)
        #expect(messageWithLRC[6] == 0xF2) // LRC

        // Verify the result
        #expect(verifyModbusLRC(messageWithLRC) == true)
    }

    // MARK: - Span Input

    @Test("Span input works correctly")
    func spanInput() {
        let array: [UInt8] = [0xF7, 0x03, 0x13, 0x89, 0x00, 0x0A]
        let result = array.withUnsafeBufferPointer { buffer in
            let span = Span<UInt8>(_unsafeStart: buffer.baseAddress!, count: buffer.count)
            return calculateModbusLRC(span)
        }
        #expect(result == 0x60)
    }

    // MARK: - Property: Sum Including LRC Equals Zero

    @Test("Property: message + LRC sums to zero")
    func propertyMessagePlusLRCSumsToZero() {
        // Test with various messages
        let testCases: [[UInt8]] = [
            [0x01],
            [0x01, 0x03],
            [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A],
            [0xFF, 0xFF, 0xFF],
            [0x00, 0x00, 0x00, 0x00],
        ]

        for message in testCases {
            let lrc = calculateModbusLRC(message)
            var sum: UInt8 = 0
            for byte in message {
                sum &+= byte
            }
            sum &+= lrc
            #expect(sum == 0, "Sum should be zero for message: \(message)")
        }
    }
}
