// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Report Server ID (FC 0x11).
///
/// Reference: Modbus Application Protocol Specification V1.1b3
/// Test vectors verified against pymodbus ReportDeviceIdRequest/Response.
@Suite("Report Server ID")
struct ReportServerIdTests {
    // MARK: - Request Builder Tests

    @Test("Build request PDU")
    func buildRequestPDU() {
        let pdu = buildReportServerIdPDU()

        // Request is just the function code
        #expect(pdu == [0x11])
    }

    @Test("Function code constant")
    func functionCodeConstant() {
        #expect(ModbusFunctionCode.reportServerId == 0x11)
    }

    // MARK: - Response Parser Tests

    @Test("Parse response with ASCII identifier")
    func parseResponseWithASCII() throws {
        // Response: FC + ByteCount + "Pymodbus" + Status(ON)
        // ByteCount = 8 (identifier) + 1 (status) = 9
        let pdu: [UInt8] = [
            0x11, // Function code
            0x09, // Byte count (8 + 1)
            0x50, 0x79, 0x6D, 0x6F, 0x64, 0x62, 0x75, 0x73, // "Pymodbus"
            0xFF, // Status: ON
        ]

        let response = try parseReportServerIdPDU(pdu)

        #expect(response.identifier == [0x50, 0x79, 0x6D, 0x6F, 0x64, 0x62, 0x75, 0x73])
        #expect(response.identifierString == "Pymodbus")
        #expect(response.status == true)
    }

    @Test("Parse response with status OFF")
    func parseResponseStatusOff() throws {
        // Response: FC + ByteCount + "ABC" + Status(OFF)
        let pdu: [UInt8] = [
            0x11, // Function code
            0x04, // Byte count (3 + 1)
            0x41, 0x42, 0x43, // "ABC"
            0x00, // Status: OFF
        ]

        let response = try parseReportServerIdPDU(pdu)

        #expect(response.identifierString == "ABC")
        #expect(response.status == false)
    }

    @Test("Parse response with empty identifier")
    func parseResponseEmptyIdentifier() throws {
        // Response: FC + ByteCount + Status only (no identifier)
        let pdu: [UInt8] = [
            0x11, // Function code
            0x01, // Byte count (0 + 1)
            0xFF, // Status: ON
        ]

        let response = try parseReportServerIdPDU(pdu)

        #expect(response.identifier.isEmpty)
        #expect(response.identifierString == "")
        #expect(response.status == true)
    }

    @Test("Parse response with binary identifier")
    func parseResponseBinaryIdentifier() throws {
        // Response with non-UTF8 binary data
        let pdu: [UInt8] = [
            0x11, // Function code
            0x05, // Byte count (4 + 1)
            0x01, 0x02, 0xFF, 0xFE, // Binary data (invalid UTF-8)
            0xFF, // Status: ON
        ]

        let response = try parseReportServerIdPDU(pdu)

        #expect(response.identifier == [0x01, 0x02, 0xFF, 0xFE])
        #expect(response.identifierString == nil) // Not valid UTF-8
        #expect(response.status == true)
    }

    // MARK: - Exception Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() throws {
        let pdu: [UInt8] = [0x91, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseReportServerIdPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Failure")
    func parseExceptionSlaveDeviceFailure() throws {
        let pdu: [UInt8] = [0x91, 0x04] // FC|0x80 + SlaveDeviceFailure

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceFailure)) {
            try parseReportServerIdPDU(pdu)
        }
    }

    // MARK: - Error Cases

    @Test("Parse PDU too short throws")
    func parsePDUTooShort() throws {
        let pdu: [UInt8] = [0x11] // Only function code

        #expect(throws: PDUError.pduTooShort) {
            try parseReportServerIdPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() throws {
        let pdu: [UInt8] = [0x03, 0x01, 0xFF] // FC 0x03 instead of 0x11

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x11, got: 0x03)) {
            try parseReportServerIdPDU(pdu)
        }
    }

    @Test("Parse truncated data throws")
    func parseTruncatedData() throws {
        // ByteCount says 5, but only 2 bytes of data
        let pdu: [UInt8] = [0x11, 0x05, 0x41, 0x42]

        #expect(throws: PDUError.pduTooShort) {
            try parseReportServerIdPDU(pdu)
        }
    }

    @Test("Parse zero byte count throws")
    func parseZeroByteCount() throws {
        // ByteCount = 0 is invalid (must have at least status byte)
        let pdu: [UInt8] = [0x11, 0x00]

        #expect(throws: PDUError.byteCountMismatch(expected: 1, got: 0)) {
            try parseReportServerIdPDU(pdu)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Request is minimal")
    func requestIsMinimal() {
        let pdu = buildReportServerIdPDU()

        // Report Server ID request has no payload
        #expect(pdu.count == 1)
        #expect(pdu[0] == ModbusFunctionCode.reportServerId)
    }

    // MARK: - RTU Frame Tests

    @Test("Build RTU request frame")
    func buildRTURequest() {
        let frame = buildRTUReportServerIdRequest(unitId: 0x01)

        // Frame: unitId(1) + FC(1) + CRC(2) = 4 bytes
        #expect(frame.count == RTUFrameSize.reportServerIdRequest)
        #expect(frame[0] == 0x01) // Unit ID
        #expect(frame[1] == 0x11) // Function code

        // Verify CRC
        let crcValid = verifyModbusCRC(frame.span)
        #expect(crcValid)
    }

    @Test("Build RTU request with custom unit ID")
    func buildRTURequestCustomUnitId() {
        let frame = buildRTUReportServerIdRequest(unitId: 0x05)

        #expect(frame[0] == 0x05)
        #expect(frame[1] == 0x11)

        let crcValid = verifyModbusCRC(frame.span)
        #expect(crcValid)
    }

    @Test("Parse RTU response")
    func parseRTUResponse() throws {
        // Build valid RTU response: unitId + FC + byteCount + "Test" + status + CRC
        var frame: [UInt8] = [
            0x01, // Unit ID
            0x11, // Function code
            0x05, // Byte count (4 + 1)
            0x54, 0x65, 0x73, 0x74, // "Test"
            0xFF, // Status: ON
        ]
        frame = appendModbusCRC(frame)

        let response = try parseRTUReportServerIdResponse(frame, expectedUnitId: 0x01)

        #expect(response.identifierString == "Test")
        #expect(response.status == true)
    }

    @Test("Parse RTU response with wrong unit ID throws")
    func parseRTUWrongUnitId() throws {
        var frame: [UInt8] = [
            0x02, // Wrong Unit ID
            0x11, // Function code
            0x01, // Byte count
            0xFF, // Status
        ]
        frame = appendModbusCRC(frame)

        #expect(throws: RTUError.unitIdMismatch(expected: 0x01, got: 0x02)) {
            try parseRTUReportServerIdResponse(frame, expectedUnitId: 0x01)
        }
    }

    @Test("Parse RTU exception response")
    func parseRTUException() throws {
        var frame: [UInt8] = [
            0x01, // Unit ID
            0x91, // FC|0x80
            0x01, // IllegalFunction
        ]
        frame = appendModbusCRC(frame)

        #expect(throws: RTUError.exceptionResponse(.illegalFunction)) {
            try parseRTUReportServerIdResponse(frame, expectedUnitId: 0x01)
        }
    }

    @Test("Parse RTU response with invalid CRC throws")
    func parseRTUInvalidCRC() throws {
        let frame: [UInt8] = [
            0x01, // Unit ID
            0x11, // Function code
            0x01, // Byte count
            0xFF, // Status
            0x00, 0x00, // Invalid CRC
        ]

        #expect(throws: RTUError.invalidCRC) {
            try parseRTUReportServerIdResponse(frame, expectedUnitId: 0x01)
        }
    }
}
