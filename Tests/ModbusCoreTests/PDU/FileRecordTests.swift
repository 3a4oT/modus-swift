// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for File Record (FC 0x14, 0x15).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.14-6.15
/// Test vectors verified against: pymodbus test_file_message.py
@Suite("File Record")
struct FileRecordTests {
    // MARK: - FileRecord Type Tests

    @Test("FileRecord with record length for read")
    func fileRecordForRead() {
        let record = FileRecord(fileNumber: 0x0001, recordNumber: 0x0002, recordLength: 0x0003)

        #expect(record.fileNumber == 0x0001)
        #expect(record.recordNumber == 0x0002)
        #expect(record.recordLength == 0x0003)
        #expect(record.recordData.isEmpty)
    }

    @Test("FileRecord with data for write")
    func fileRecordForWrite() throws {
        let data: [UInt8] = [0x00, 0x01, 0x02, 0x03]
        let record = try FileRecord(fileNumber: 0x0001, recordNumber: 0x0002, recordData: data)

        #expect(record.fileNumber == 0x0001)
        #expect(record.recordNumber == 0x0002)
        #expect(record.recordLength == 2) // 4 bytes = 2 registers
        #expect(record.recordData == data)
    }

    @Test("FileRecord with odd data length throws")
    func fileRecordOddDataLength() {
        let data: [UInt8] = [0x01, 0x02, 0x03] // 3 bytes = odd

        #expect(throws: PDUError.oddRecordDataLength(3)) {
            try FileRecord(fileNumber: 0x0001, recordNumber: 0x0002, recordData: data)
        }
    }

    // MARK: - Read File Record Request Tests

    @Test("Build read file record request - single record")
    func buildReadRequestSingleRecord() {
        // Verified: pymodbus test_read_file_record_request_encode
        // FileRecord(file_number=0x01, record_number=0x02, record_length=0)
        // Expected: b'\x07\x06\x00\x01\x00\x02\x00\x00'
        let record = FileRecord(fileNumber: 0x0001, recordNumber: 0x0002, recordLength: 0x0000)
        let pdu = buildReadFileRecordPDU(records: [record])

        #expect(pdu == [
            0x14, // FC
            0x07, // Data length (1 × 7)
            0x06, // Ref type
            0x00, 0x01, // File number
            0x00, 0x02, // Record number
            0x00, 0x00, // Record length
        ])
    }

    @Test("Build read file record request - multiple records")
    func buildReadRequestMultipleRecords() {
        // Verified: pymodbus test_read_file_record_request_decode
        // Input: b'\x0e\x06\x00\x04\x00\x01\x00\x02\x06\x00\x03\x00\x09\x00\x02'
        let record1 = FileRecord(fileNumber: 0x0004, recordNumber: 0x0001, recordLength: 0x0002)
        let record2 = FileRecord(fileNumber: 0x0003, recordNumber: 0x0009, recordLength: 0x0002)
        let pdu = buildReadFileRecordPDU(records: [record1, record2])

        #expect(pdu == [
            0x14, // FC
            0x0E, // Data length (2 × 7 = 14)
            0x06, 0x00, 0x04, 0x00, 0x01, 0x00, 0x02, // Record 1
            0x06, 0x00, 0x03, 0x00, 0x09, 0x00, 0x02, // Record 2
        ])
    }

    // MARK: - Read File Record Response Tests

    @Test("Parse read file record response - single record")
    func parseReadResponseSingleRecord() throws {
        // Verified: pymodbus test_read_file_record_response_encode
        // FileRecord(record_data=b'\x00\x01\x02\x03\x04\x05')
        // Expected output: b'\x08\x07\x06\x00\x01\x02\x03\x04\x05'
        let pdu: [UInt8] = [
            0x14, // FC
            0x08, // Data length
            0x07, // File response length (6 data + 1 ref type)
            0x06, // Ref type
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, // Record data (6 bytes)
        ]

        let response = try parseReadFileRecordPDU(pdu)

        #expect(response.records.count == 1)
        #expect(response.records[0].recordData == [0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(response.records[0].recordLength == 3) // 6 bytes = 3 registers
    }

    @Test("Parse read file record response - multiple records")
    func parseReadResponseMultipleRecords() throws {
        // Verified: pymodbus test_read_file_record_response_decode
        // Input: b'\x0c\x05\x06\x0d\xfe\x00\x20\x05\x06\x33\xcd\x00\x40'
        let pdu: [UInt8] = [
            0x14, // FC
            0x0C, // Data length
            0x05, 0x06, 0x0D, 0xFE, 0x00, 0x20, // Record 1: len=5, ref=6, data=4 bytes
            0x05, 0x06, 0x33, 0xCD, 0x00, 0x40, // Record 2: len=5, ref=6, data=4 bytes
        ]

        let response = try parseReadFileRecordPDU(pdu)

        #expect(response.records.count == 2)
        #expect(response.records[0].recordData == [0x0D, 0xFE, 0x00, 0x20])
        #expect(response.records[1].recordData == [0x33, 0xCD, 0x00, 0x40])
    }

    @Test("Parse read file record response - exception")
    func parseReadResponseException() {
        let pdu: [UInt8] = [0x94, 0x02] // FC|0x80 + IllegalDataAddress

        #expect(throws: PDUError.exceptionResponse(.illegalDataAddress)) {
            try parseReadFileRecordPDU(pdu)
        }
    }

    @Test("Parse read file record response - invalid ref type")
    func parseReadResponseInvalidRefType() {
        let pdu: [UInt8] = [
            0x14, // FC
            0x04, // Data length
            0x03, // File response length
            0x05, // WRONG ref type (should be 0x06)
            0x00, 0x01, // Record data
        ]

        #expect(throws: PDUError.invalidFileReferenceType(0x05)) {
            try parseReadFileRecordPDU(pdu)
        }
    }

    @Test("Parse read file record response - wrong function code")
    func parseReadResponseWrongFC() {
        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x14, got: 0x03)) {
            try parseReadFileRecordPDU(pdu)
        }
    }

    @Test("Parse read file record response - too short")
    func parseReadResponseTooShort() {
        let pdu: [UInt8] = [0x14] // Only FC, no data length

        #expect(throws: PDUError.pduTooShort) {
            try parseReadFileRecordPDU(pdu)
        }
    }

    // MARK: - Write File Record Request Tests

    @Test("Build write file record request - single record")
    func buildWriteRequestSingleRecord() throws {
        // Verified: pymodbus test_write_file_record_request_encode
        // FileRecord(file_number=0x01, record_number=0x02, record_data=b'\x00\x01\x02\x03')
        // Expected: b'\x0b\x06\x00\x01\x00\x02\x00\x02\x00\x01\x02\x03'
        let record = try FileRecord(fileNumber: 0x0001, recordNumber: 0x0002, recordData: [0x00, 0x01, 0x02, 0x03])
        let pdu = buildWriteFileRecordPDU(records: [record])

        #expect(pdu == [
            0x15, // FC
            0x0B, // Data length (7 header + 4 data)
            0x06, // Ref type
            0x00, 0x01, // File number
            0x00, 0x02, // Record number
            0x00, 0x02, // Record length (2 registers)
            0x00, 0x01, 0x02, 0x03, // Data
        ])
    }

    @Test("Build write file record request - multiple records")
    func buildWriteRequestMultipleRecords() throws {
        let record1 = try FileRecord(
            fileNumber: 0x0004,
            recordNumber: 0x0007,
            recordData: [0x06, 0xAF, 0x04, 0xBE, 0x10, 0x0D],
        )
        let pdu = buildWriteFileRecordPDU(records: [record1])

        // Verified: pymodbus test_write_file_record_request_decode
        // Input: b'\x0d\x06\x00\x04\x00\x07\x00\x03\x06\xaf\x04\xbe\x10\x0d'
        #expect(pdu == [
            0x15, // FC
            0x0D, // Data length (7 + 6)
            0x06, // Ref type
            0x00, 0x04, // File number
            0x00, 0x07, // Record number
            0x00, 0x03, // Record length (3 registers)
            0x06, 0xAF, 0x04, 0xBE, 0x10, 0x0D, // Data
        ])
    }

    // MARK: - Write File Record Response Tests

    @Test("Parse write file record response - single record")
    func parseWriteResponseSingleRecord() throws {
        // Verified: pymodbus test_write_file_record_response_encode
        // Same as request - response is echo
        let pdu: [UInt8] = [
            0x15, // FC
            0x0B, // Data length
            0x06, // Ref type
            0x00, 0x01, // File number
            0x00, 0x02, // Record number
            0x00, 0x02, // Record length
            0x00, 0x01, 0x02, 0x03, // Data
        ]

        let response = try parseWriteFileRecordPDU(pdu)

        #expect(response.records.count == 1)
        #expect(response.records[0].fileNumber == 0x0001)
        #expect(response.records[0].recordNumber == 0x0002)
        #expect(response.records[0].recordLength == 2)
        #expect(response.records[0].recordData == [0x00, 0x01, 0x02, 0x03])
    }

    @Test("Parse write file record response - multiple records")
    func parseWriteResponseMultipleRecords() throws {
        // Verified: pymodbus test_write_file_record_response_decode
        // Input: b'\x0d\x06\x00\x04\x00\x07\x00\x03\x06\xaf\x04\xbe\x10\x0d'
        let pdu: [UInt8] = [
            0x15, // FC
            0x0D, // Data length
            0x06, // Ref type
            0x00, 0x04, // File number
            0x00, 0x07, // Record number
            0x00, 0x03, // Record length
            0x06, 0xAF, 0x04, 0xBE, 0x10, 0x0D, // Data
        ]

        let response = try parseWriteFileRecordPDU(pdu)

        #expect(response.records.count == 1)
        #expect(response.records[0].fileNumber == 0x0004)
        #expect(response.records[0].recordNumber == 0x0007)
        #expect(response.records[0].recordLength == 3)
        #expect(response.records[0].recordData == [0x06, 0xAF, 0x04, 0xBE, 0x10, 0x0D])
    }

    @Test("Parse write file record response - exception")
    func parseWriteResponseException() {
        let pdu: [UInt8] = [0x95, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseWriteFileRecordPDU(pdu)
        }
    }

    @Test("Parse write file record response - invalid ref type")
    func parseWriteResponseInvalidRefType() {
        let pdu: [UInt8] = [
            0x15, // FC
            0x0B, // Data length
            0x07, // WRONG ref type (should be 0x06)
            0x00, 0x01, // File number
            0x00, 0x02, // Record number
            0x00, 0x02, // Record length
            0x00, 0x01, 0x02, 0x03, // Data
        ]

        #expect(throws: PDUError.invalidFileReferenceType(0x07)) {
            try parseWriteFileRecordPDU(pdu)
        }
    }

    @Test("Parse write file record response - wrong function code")
    func parseWriteResponseWrongFC() {
        let pdu: [UInt8] = [0x06, 0x04, 0x00, 0x01, 0x00, 0x02]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x15, got: 0x06)) {
            try parseWriteFileRecordPDU(pdu)
        }
    }

    @Test("Parse write file record response - too short")
    func parseWriteResponseTooShort() {
        let pdu: [UInt8] = [0x15] // Only FC

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteFileRecordPDU(pdu)
        }
    }

    // MARK: - Security Tests (CVE-style)

    @Test("Parse read response - data length larger than actual")
    func parseReadResponseDataLengthTooLarge() {
        // CVE-style: claims 0xFF bytes but has only 4
        let pdu: [UInt8] = [
            0x14, // FC
            0xFF, // Claims 255 bytes
            0x03, 0x06, 0x00, 0x01, // Only 4 bytes of data
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadFileRecordPDU(pdu)
        }
    }

    @Test("Parse write response - record length overflow")
    func parseWriteResponseRecordLengthOverflow() {
        // Claims 0xFFFF registers (130KB of data) but has none
        let pdu: [UInt8] = [
            0x15, // FC
            0x07, // Data length
            0x06, // Ref type
            0x00, 0x01, // File number
            0x00, 0x02, // Record number
            0xFF, 0xFF, // Record length = 65535 registers
            // No data follows
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseWriteFileRecordPDU(pdu)
        }
    }

    @Test("Parse read response - truncated sub-response")
    func parseReadResponseTruncatedSubResponse() {
        let pdu: [UInt8] = [
            0x14, // FC
            0x04, // Data length
            0x10, // Claims 16 bytes (len + reftype + 14 data)
            0x06, // Ref type
            0x00, 0x01, // Only 2 bytes of data, not 14
        ]

        #expect(throws: PDUError.pduTooShort) {
            try parseReadFileRecordPDU(pdu)
        }
    }
}
