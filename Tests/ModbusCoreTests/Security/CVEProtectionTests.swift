// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests verifying protection against known CVEs and common vulnerabilities
/// found in Modbus library implementations.
///
/// References:
/// - CVE-2024-10918: libmodbus stack buffer overflow (response length)
/// - CVE-2023-26793: libmodbus heap overflow in read_io_status
/// - CVE-2022-0367: libmodbus heap overflow in modbus_reply
/// - pymodbus struct.unpack crashes from insufficient bounds checking
///
/// These tests ensure our implementation doesn't have similar vulnerabilities.
@Suite("CVE Protection")
struct CVEProtectionTests {
    // MARK: - CVE-2024-10918: Response Length Overflow

    /// CVE-2024-10918: Stack-based buffer overflow in libmodbus v3.1.10
    /// when response length exceeds allocated buffer.
    ///
    /// Attack: Send byteCount larger than actual data.
    /// Our protection: `guard pdu.count >= 2 + byteCount` + Optional helpers
    @Suite("CVE-2024-10918 Style")
    struct CVE2024_10918 {
        @Test("byteCount 0xFF with minimal data")
        func byteCountFFMinimalData() {
            let pdu: [UInt8] = [
                0x03, // FC: Read Holding Registers
                0xFF, // Claims 255 bytes of data
                0x00, 0x01, // Only 2 bytes actual data
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("byteCount exceeds PDU by 1 byte")
        func byteCountExceedsByOne() {
            let pdu: [UInt8] = [
                0x03,
                0x06, // Claims 6 bytes
                0x00, 0x01, 0x00, 0x02, 0x00, // Only 5 bytes
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("maximum byteCount with empty data")
        func maxByteCountEmptyData() {
            let pdu: [UInt8] = [
                0x03,
                0xFA, // 250 bytes (max for 125 registers)
                // No actual data
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("Write Multiple Registers - byteCount overflow")
        func writeMultipleByteCountOverflow() {
            let pdu: [UInt8] = [
                0x10, // FC: Write Multiple Registers response
                0x00, 0x01, // Address
                0x00, // Truncated quantity
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseWriteMultipleRegistersPDU(pdu)
            }
        }
    }

    // MARK: - CVE-2023-26793: Heap Overflow in read_io_status

    /// CVE-2023-26793: Heap-based buffer overflow in libmodbus read_io_status.
    ///
    /// Attack: Malformed coil/discrete input response with wrong byteCount.
    /// Our protection: `byteCount == expectedByteCount` validation
    @Suite("CVE-2023-26793 Style")
    struct CVE2023_26793 {
        @Test("Coils byteCount mismatch - too large")
        func coilsByteCountTooLarge() {
            let pdu: [UInt8] = [
                0x01, // FC: Read Coils
                0x10, // Claims 16 bytes (128 coils)
                0xFF, 0xFF, // Only 2 bytes of data
            ]

            // Request was for 8 coils, expects 1 byte
            #expect(throws: PDUError.byteCountMismatch(expected: 1, got: 16)) {
                try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 8)
            }
        }

        @Test("Coils byteCount mismatch - too small")
        func coilsByteCountTooSmall() {
            let pdu: [UInt8] = [
                0x01, // FC: Read Coils
                0x01, // Claims 1 byte
                0xFF, // 1 byte of data
            ]

            // Request was for 16 coils, expects 2 bytes
            #expect(throws: PDUError.byteCountMismatch(expected: 2, got: 1)) {
                try parseReadBitsPDU(pdu, expectedFunction: 0x01, requestedCount: 16)
            }
        }

        @Test("Discrete inputs byteCount zero")
        func discreteInputsByteCountZero() {
            let pdu: [UInt8] = [
                0x02, // FC: Read Discrete Inputs
                0x00, // Claims 0 bytes
            ]

            // Request was for 8 inputs, expects 1 byte
            #expect(throws: PDUError.byteCountMismatch(expected: 1, got: 0)) {
                try parseReadBitsPDU(pdu, expectedFunction: 0x02, requestedCount: 8)
            }
        }
    }

    // MARK: - CVE-2022-0367: Heap Overflow in modbus_reply

    /// CVE-2022-0367: Heap-based buffer overflow in libmodbus modbus_reply.
    /// The bug was in FC 0x17 (Read/Write Multiple Registers) server-side code
    /// where write address wasn't validated against mapping bounds.
    ///
    /// While this is server-side (we're client), we test our FC 0x17 parser
    /// handles malformed responses safely.
    @Suite("CVE-2022-0367 Style")
    struct CVE2022_0367 {
        @Test("FC 0x17 response - truncated")
        func fc17ResponseTruncated() {
            let pdu: [UInt8] = [
                0x17, // FC: Read/Write Multiple Registers
                0x04, // Claims 4 bytes (2 registers)
                0x00, 0x01, // Only 1 register
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadWriteMultipleRegistersPDU(pdu)
            }
        }

        @Test("FC 0x17 response - odd byteCount")
        func fc17ResponseOddByteCount() {
            let pdu: [UInt8] = [
                0x17,
                0x03, // Odd - invalid for registers
                0x00, 0x01, 0x02,
            ]

            #expect(throws: PDUError.byteCountMismatch(expected: 3, got: 3)) {
                try parseReadWriteMultipleRegistersPDU(pdu)
            }
        }

        @Test("FC 0x17 exception - truncated")
        func fc17ExceptionTruncated() {
            let pdu: [UInt8] = [
                0x97, // FC 0x17 + 0x80 exception flag
                // Missing exception code
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadWriteMultipleRegistersPDU(pdu)
            }
        }
    }

    // MARK: - pymodbus struct.unpack Crashes

    /// pymodbus has multiple reported issues where struct.unpack crashes
    /// due to insufficient bounds checking before unpacking.
    ///
    /// References:
    /// - https://github.com/pymodbus-dev/pymodbus/discussions/1614
    /// - https://github.com/pymodbus-dev/pymodbus/issues/2018
    @Suite("pymodbus struct.unpack Style")
    struct PymodbusStructUnpack {
        @Test("Truncated mid-register (1 byte of UInt16)")
        func truncatedMidRegister() {
            let pdu: [UInt8] = [
                0x03,
                0x04, // Claims 4 bytes (2 registers)
                0x00, 0x01, // First register OK
                0x02, // Second register truncated
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("Exception response truncated")
        func exceptionTruncated() {
            let pdu: [UInt8] = [
                0x83, // FC 0x03 + exception flag
                // Missing exception code
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("Empty PDU")
        func emptyPDU() {
            let pdu: [UInt8] = []

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("Only function code")
        func onlyFunctionCode() {
            let pdu: [UInt8] = [0x03]

            #expect(throws: PDUError.pduTooShort) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("Write Single Register - truncated value")
        func writeSingleTruncatedValue() {
            let pdu: [UInt8] = [
                0x06, // FC: Write Single Register
                0x00, 0x01, // Address OK
                0x00, // Value truncated (need 2 bytes)
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseWriteSingleRegisterPDU(pdu)
            }
        }

        @Test("Write Single Register - truncated address")
        func writeSingleTruncatedAddress() {
            let pdu: [UInt8] = [
                0x06, // FC
                0x00, // Only 1 byte of address
            ]

            #expect(throws: PDUError.pduTooShort) {
                try parseWriteSingleRegisterPDU(pdu)
            }
        }
    }

    // MARK: - Defense in Depth: Binary Helpers

    /// Tests verifying that Optional binary helpers provide defense-in-depth.
    /// Even if outer validation has a bug, helpers catch out-of-bounds access.
    @Suite("Defense in Depth")
    struct DefenseInDepth {
        @Test("readUInt8 returns nil at boundary")
        func readUInt8Boundary() {
            let data: [UInt8] = [0x12, 0x34]
            #expect(readUInt8(data, at: 0) == 0x12)
            #expect(readUInt8(data, at: 1) == 0x34)
            #expect(readUInt8(data, at: 2) == nil)
            #expect(readUInt8(data, at: -1) == nil)
        }

        @Test("readUInt16BE returns nil when 1 byte short")
        func readUInt16BEOneBytShort() {
            let data: [UInt8] = [0x12, 0x34, 0x56]
            #expect(readUInt16BE(data, at: 0) == 0x1234)
            #expect(readUInt16BE(data, at: 1) == 0x3456)
            #expect(readUInt16BE(data, at: 2) == nil) // Only 1 byte left
        }

        @Test("readUInt32BE returns nil when 1 byte short")
        func readUInt32BEOneBytShort() {
            let data: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A]
            #expect(readUInt32BE(data, at: 0) == 0x1234_5678)
            #expect(readUInt32BE(data, at: 1) == 0x3456_789A)
            #expect(readUInt32BE(data, at: 2) == nil) // Only 3 bytes left
        }

        @Test("Sequential reads stop safely at boundary")
        func sequentialReadsBoundary() {
            let data: [UInt8] = [0x00, 0x01, 0x00, 0x02, 0x00]
            var offset = 0
            var values: [UInt16] = []

            while let value = readUInt16BE(data, at: offset) {
                values.append(value)
                offset += 2
            }

            #expect(values == [0x0001, 0x0002])
            #expect(offset == 4) // Stopped safely
        }

        @Test("Empty data returns nil for all helpers")
        func emptyDataAllHelpers() {
            let data: [UInt8] = []
            #expect(readUInt8(data, at: 0) == nil)
            #expect(readUInt16BE(data, at: 0) == nil)
            #expect(readUInt16LE(data, at: 0) == nil)
            #expect(readUInt32BE(data, at: 0) == nil)
            #expect(readUInt32LE(data, at: 0) == nil)
        }
    }

    // MARK: - Odd Byte Count Attacks

    /// Register data must have even byte count (2 bytes per register).
    /// Odd byte count indicates malformed or malicious PDU.
    @Suite("Odd Byte Count")
    struct OddByteCount {
        @Test("Read Registers - odd byteCount rejected")
        func readRegistersOddByteCount() {
            let pdu: [UInt8] = [
                0x03,
                0x05, // Odd - invalid
                0x00, 0x01, 0x02, 0x03, 0x04,
            ]

            #expect(throws: PDUError.byteCountMismatch(expected: 5, got: 5)) {
                try parseReadRegistersPDU(pdu)
            }
        }

        @Test("FC 0x17 - odd byteCount rejected")
        func fc17OddByteCount() {
            let pdu: [UInt8] = [
                0x17,
                0x03, // Odd
                0x00, 0x01, 0x02,
            ]

            #expect(throws: PDUError.byteCountMismatch(expected: 3, got: 3)) {
                try parseReadWriteMultipleRegistersPDU(pdu)
            }
        }

        @Test("byteCount 1 is always invalid for registers")
        func byteCountOneInvalid() {
            let pdu: [UInt8] = [
                0x03,
                0x01, // 1 byte - can't be valid register
                0xFF,
            ]

            #expect(throws: PDUError.byteCountMismatch(expected: 1, got: 1)) {
                try parseReadRegistersPDU(pdu)
            }
        }
    }
}
