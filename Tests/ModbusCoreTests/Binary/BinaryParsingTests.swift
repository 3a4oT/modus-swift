// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for binary parsing helpers
@Suite("Binary Parsing")
struct BinaryParsingTests {
    // MARK: - UInt8 Reading

    @Test("Read UInt8 at valid offset")
    func readUInt8Valid() {
        let data: [UInt8] = [0x12, 0x34, 0x56]
        #expect(readUInt8(data, at: 0) == 0x12)
        #expect(readUInt8(data, at: 1) == 0x34)
        #expect(readUInt8(data, at: 2) == 0x56)
    }

    // MARK: - Little Endian UInt16

    @Test("Read UInt16 LE at valid offset")
    func readUInt16LEValid() {
        // 0x3412 in LE = [0x12, 0x34]
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt16LE(data, at: 0) == 0x3412)
        #expect(readUInt16LE(data, at: 1) == 0x5634)
        #expect(readUInt16LE(data, at: 2) == 0x7856)
    }

    @Test("Read UInt16 LE at boundary")
    func readUInt16LEBoundary() {
        let data: [UInt8] = [0xFF, 0xFF]
        #expect(readUInt16LE(data, at: 0) == 0xFFFF)
    }

    // MARK: - Little Endian UInt32

    @Test("Read UInt32 LE at valid offset")
    func readUInt32LEValid() {
        // 0x78563412 in LE = [0x12, 0x34, 0x56, 0x78]
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A]
        #expect(readUInt32LE(data, at: 0) == 0x7856_3412)
        #expect(readUInt32LE(data, at: 1) == 0x9A78_5634)
    }

    @Test("Read UInt32 LE at boundary")
    func readUInt32LEBoundary() {
        let data: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        #expect(readUInt32LE(data, at: 0) == 0xFFFF_FFFF)
    }

    // MARK: - Big Endian UInt16

    @Test("Read UInt16 BE at valid offset")
    func readUInt16BEValid() {
        // 0x1234 in BE = [0x12, 0x34]
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt16BE(data, at: 0) == 0x1234)
        #expect(readUInt16BE(data, at: 1) == 0x3456)
        #expect(readUInt16BE(data, at: 2) == 0x5678)
    }

    // MARK: - Big Endian UInt32

    @Test("Read UInt32 BE at valid offset")
    func readUInt32BEValid() {
        // 0x12345678 in BE = [0x12, 0x34, 0x56, 0x78]
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt32BE(data, at: 0) == 0x1234_5678)
    }

    // MARK: - Real World: V5 Frame Parsing Simulation

    @Test("Parse V5 response header fields")
    func parseV5HeaderFields() {
        // Simulated V5 response header (first 13 bytes)
        let header: [UInt8] = [
            0xA5, // Start
            0x15, 0x00, // Length: 21 (LE)
            0x10, 0x15, // Control: 0x1510 (LE)
            0x42, 0x00, // Sequence: 66 (LE)
            0x78, 0x56, 0x34, 0x12, // Serial: 0x12345678 (LE)
            0x02, // Frame type
            0x01, // Status
        ]

        // Parsing with bounds already validated
        #expect(readUInt8(header, at: 0) == 0xA5)
        #expect(readUInt16LE(header, at: 1) == 21)
        #expect(readUInt16LE(header, at: 3) == 0x1510)
        #expect(readUInt16LE(header, at: 5) == 66)
        #expect(readUInt32LE(header, at: 7) == 0x1234_5678)
        #expect(readUInt8(header, at: 11) == 0x02)
        #expect(readUInt8(header, at: 12) == 0x01)
    }

    // MARK: - Span Overloads

    @Test("Read UInt16 BE from Span")
    func readUInt16BEFromSpan() {
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        let result = data.withUnsafeBufferPointer { buffer in
            let span = Span<UInt8>(_unsafeStart: buffer.baseAddress!, count: buffer.count)
            return readUInt16BE(span, at: 0)
        }
        #expect(result == 0x1234)
    }

    @Test("Read UInt32 LE from Span")
    func readUInt32LEFromSpan() {
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        let result = data.withUnsafeBufferPointer { buffer in
            let span = Span<UInt8>(_unsafeStart: buffer.baseAddress!, count: buffer.count)
            return readUInt32LE(span, at: 0)
        }
        #expect(result == 0x7856_3412)
    }

    // MARK: - Out of Bounds Tests (Safety-Critical)

    // These tests verify the Optional return behavior that prevents
    // crashes on malformed network data. Reference: pymodbus has known
    // bugs from insufficient bounds checking before struct.unpack.

    @Test("Read UInt8 returns nil for empty data")
    func readUInt8EmptyData() {
        let data: [UInt8] = []
        #expect(readUInt8(data, at: 0) == nil)
    }

    @Test("Read UInt8 returns nil for offset at count")
    func readUInt8OffsetAtCount() {
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt8(data, at: 2) == nil)
    }

    @Test("Read UInt8 returns nil for offset beyond count")
    func readUInt8OffsetBeyondCount() {
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt8(data, at: 100) == nil)
    }

    @Test("Read UInt8 returns nil for negative offset")
    func readUInt8NegativeOffset() {
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt8(data, at: -1) == nil)
    }

    @Test("Read UInt16 BE returns nil for insufficient data")
    func readUInt16BEInsufficientData() {
        // Need 2 bytes, have only 1
        let data: [UInt8] = [0x12]
        #expect(readUInt16BE(data, at: 0) == nil)
    }

    @Test("Read UInt16 BE returns nil for offset at boundary")
    func readUInt16BEOffsetAtBoundary() {
        // Need 2 bytes starting at offset 1, but only 1 byte available
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt16BE(data, at: 1) == nil)
    }

    @Test("Read UInt16 BE returns nil for empty data")
    func readUInt16BEEmptyData() {
        let data: [UInt8] = []
        #expect(readUInt16BE(data, at: 0) == nil)
    }

    @Test("Read UInt16 LE returns nil for insufficient data")
    func readUInt16LEInsufficientData() {
        let data: [UInt8] = [0x12]
        #expect(readUInt16LE(data, at: 0) == nil)
    }

    @Test("Read UInt16 LE returns nil for negative offset")
    func readUInt16LENegativeOffset() {
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt16LE(data, at: -1) == nil)
    }

    @Test("Read UInt32 BE returns nil for insufficient data")
    func readUInt32BEInsufficientData() {
        // Need 4 bytes, have only 3
        let data: [UInt8] = [0x12, 0x34, 0x56]
        #expect(readUInt32BE(data, at: 0) == nil)
    }

    @Test("Read UInt32 BE returns nil for offset at boundary")
    func readUInt32BEOffsetAtBoundary() {
        // Need 4 bytes starting at offset 1, but only 3 available
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt32BE(data, at: 1) == nil)
    }

    @Test("Read UInt32 LE returns nil for insufficient data")
    func readUInt32LEInsufficientData() {
        let data: [UInt8] = [0x12, 0x34, 0x56]
        #expect(readUInt32LE(data, at: 0) == nil)
    }

    @Test("Read UInt32 LE returns nil for empty data")
    func readUInt32LEEmptyData() {
        let data: [UInt8] = []
        #expect(readUInt32LE(data, at: 0) == nil)
    }

    @Test("Read UInt32 LE returns nil for negative offset")
    func readUInt32LENegativeOffset() {
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt32LE(data, at: -1) == nil)
    }

    // MARK: - Edge Case: Exactly Sufficient Data

    @Test("Read UInt16 BE succeeds with exactly 2 bytes")
    func readUInt16BEExactlyEnough() {
        let data: [UInt8] = [0x12, 0x34]
        #expect(readUInt16BE(data, at: 0) == 0x1234)
    }

    @Test("Read UInt32 BE succeeds with exactly 4 bytes")
    func readUInt32BEExactlyEnough() {
        let data: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        #expect(readUInt32BE(data, at: 0) == 0x1234_5678)
    }

    @Test("Read UInt16 at last valid offset succeeds")
    func readUInt16LastValidOffset() {
        let data: [UInt8] = [0x00, 0x00, 0x12, 0x34]
        // Last valid offset for UInt16 is count - 2 = 2
        #expect(readUInt16BE(data, at: 2) == 0x1234)
        // Offset 3 should fail (only 1 byte remaining)
        #expect(readUInt16BE(data, at: 3) == nil)
    }

    @Test("Read UInt32 at last valid offset succeeds")
    func readUInt32LastValidOffset() {
        let data: [UInt8] = [0x00, 0x00, 0x12, 0x34, 0x56, 0x78]
        // Last valid offset for UInt32 is count - 4 = 2
        #expect(readUInt32BE(data, at: 2) == 0x1234_5678)
        // Offset 3 should fail (only 3 bytes remaining)
        #expect(readUInt32BE(data, at: 3) == nil)
    }
}
