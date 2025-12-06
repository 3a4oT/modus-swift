// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Device Identification (FC 0x2B / MEI 0x0E).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.21
@Suite("Device Identification")
struct DeviceIdentificationTests {
    // MARK: - Request Builder Tests

    @Test("Build basic device identification request")
    func buildBasicRequest() {
        let pdu = buildReadDeviceIdentificationPDU(readCode: .basic, objectId: 0x00)

        #expect(pdu == [0x2B, 0x0E, 0x01, 0x00])
    }

    @Test("Build regular device identification request")
    func buildRegularRequest() {
        let pdu = buildReadDeviceIdentificationPDU(readCode: .regular, objectId: 0x00)

        #expect(pdu == [0x2B, 0x0E, 0x02, 0x00])
    }

    @Test("Build extended device identification request")
    func buildExtendedRequest() {
        let pdu = buildReadDeviceIdentificationPDU(readCode: .extended, objectId: 0x00)

        #expect(pdu == [0x2B, 0x0E, 0x03, 0x00])
    }

    @Test("Build specific object request")
    func buildSpecificRequest() {
        let pdu = buildReadDeviceIdentificationPDU(readCode: .specific, objectId: 0x02)

        #expect(pdu == [0x2B, 0x0E, 0x04, 0x02])
    }

    // MARK: - Response Parser Tests

    @Test("Parse basic device identification response")
    func parseBasicResponse() throws {
        // Response with VendorName "Test"
        // FC(2B) + MEI(0E) + ReadCode(01) + Conformity(01) + MoreFollows(00) + NextObj(00) + NumObj(01)
        // + ObjId(00) + Len(04) + "Test"
        let pdu: [UInt8] = [
            0x2B, 0x0E, 0x01, 0x01, // FC, MEI, ReadCode, Conformity
            0x00, 0x00, 0x01, // MoreFollows, NextObjId, NumObjects
            0x00, 0x04, // ObjId, Length
            0x54, 0x65, 0x73, 0x74, // "Test"
        ]

        let response = try parseDeviceIdentificationPDU(pdu)

        #expect(response.conformityLevel == 0x01)
        #expect(response.moreFollows == false)
        #expect(response.nextObjectId == 0x00)
        #expect(response.objects.count == 1)
        #expect(response.vendorName == "Test")
    }

    @Test("Parse response with multiple objects")
    func parseMultipleObjects() throws {
        // Response with VendorName "ABC" and ProductCode "XY"
        let pdu: [UInt8] = [
            0x2B, 0x0E, 0x01, 0x01, // FC, MEI, ReadCode, Conformity
            0x00, 0x00, 0x02, // MoreFollows, NextObjId, NumObjects
            0x00, 0x03, 0x41, 0x42, 0x43, // VendorName "ABC"
            0x01, 0x02, 0x58, 0x59, // ProductCode "XY"
        ]

        let response = try parseDeviceIdentificationPDU(pdu)

        #expect(response.objects.count == 2)
        #expect(response.vendorName == "ABC")
        #expect(response.productCode == "XY")
    }

    @Test("Parse response with moreFollows flag")
    func parseMoreFollows() throws {
        let pdu: [UInt8] = [
            0x2B, 0x0E, 0x01, 0x01, // FC, MEI, ReadCode, Conformity
            0xFF, 0x03, 0x01, // MoreFollows=true, NextObjId=3, NumObjects=1
            0x00, 0x01, 0x41, // VendorName "A"
        ]

        let response = try parseDeviceIdentificationPDU(pdu)

        #expect(response.moreFollows == true)
        #expect(response.nextObjectId == 0x03)
    }

    @Test("Parse exception response")
    func parseExceptionResponse() throws {
        // Exception response: FC|0x80 + ExceptionCode
        let pdu: [UInt8] = [0xAB, 0x01] // 0x2B|0x80, IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseDeviceIdentificationPDU(pdu)
        }
    }

    @Test("Parse invalid MEI type throws")
    func parseInvalidMEIType() throws {
        // Wrong MEI type (0x0F instead of 0x0E)
        let pdu: [UInt8] = [
            0x2B, 0x0F, 0x01, 0x01,
            0x00, 0x00, 0x00,
        ]

        #expect(throws: PDUError.invalidMEIType(0x0F)) {
            try parseDeviceIdentificationPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() throws {
        let pdu: [UInt8] = [
            0x03, 0x0E, 0x01, 0x01, // Wrong FC
            0x00, 0x00, 0x00,
        ]

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x2B, got: 0x03)) {
            try parseDeviceIdentificationPDU(pdu)
        }
    }

    @Test("Parse too short PDU throws")
    func parseTooShortPDU() throws {
        let pdu: [UInt8] = [0x2B, 0x0E] // Too short

        #expect(throws: PDUError.pduTooShort) {
            try parseDeviceIdentificationPDU(pdu)
        }
    }

    // MARK: - Convenience Accessor Tests

    @Test("Convenience accessors for all standard objects")
    func convenienceAccessors() throws {
        let pdu: [UInt8] = [
            0x2B, 0x0E, 0x02, 0x02, // FC, MEI, ReadCode=Regular, Conformity=Regular
            0x00, 0x00, 0x07, // MoreFollows, NextObjId, NumObjects=7
            0x00, 0x01, 0x41, // VendorName "A"
            0x01, 0x01, 0x42, // ProductCode "B"
            0x02, 0x03, 0x31, 0x2E, 0x30, // Revision "1.0"
            0x03, 0x01, 0x43, // VendorUrl "C"
            0x04, 0x01, 0x44, // ProductName "D"
            0x05, 0x01, 0x45, // ModelName "E"
            0x06, 0x01, 0x46, // UserAppName "F"
        ]

        let response = try parseDeviceIdentificationPDU(pdu)

        #expect(response.vendorName == "A")
        #expect(response.productCode == "B")
        #expect(response.revision == "1.0")
        #expect(response.vendorUrl == "C")
        #expect(response.productName == "D")
        #expect(response.modelName == "E")
        #expect(response.userApplicationName == "F")
    }

    // MARK: - RTU Frame Tests

    @Test("Build RTU device identification request")
    func buildRTURequest() {
        let frame = buildRTUReadDeviceIdentificationRequest(
            readCode: .basic,
            objectId: 0x00,
            unitId: 0x01,
        )

        // UnitId(1) + FC(2B) + MEI(0E) + ReadCode(01) + ObjId(00) + CRC(2)
        #expect(frame.count == 7)
        #expect(frame[0] == 0x01) // Unit ID
        #expect(frame[1] == 0x2B) // Function code
        #expect(frame[2] == 0x0E) // MEI type
        #expect(frame[3] == 0x01) // Read code (basic)
        #expect(frame[4] == 0x00) // Object ID

        // Verify CRC
        let crcValid = verifyModbusCRC(frame.span)
        #expect(crcValid)
    }

    @Test("Parse RTU device identification response")
    func parseRTUResponse() throws {
        // Build a valid RTU response frame
        var frame: [UInt8] = [
            0x01, // Unit ID
            0x2B, 0x0E, 0x01, 0x01, // FC, MEI, ReadCode, Conformity
            0x00, 0x00, 0x01, // MoreFollows, NextObjId, NumObjects
            0x00, 0x04, // ObjId, Length
            0x54, 0x65, 0x73, 0x74, // "Test"
        ]
        frame = appendModbusCRC(frame)

        let response = try parseRTUDeviceIdentificationResponse(frame, expectedUnitId: 0x01)

        #expect(response.vendorName == "Test")
        #expect(response.moreFollows == false)
    }

    @Test("Parse RTU response with wrong unit ID throws")
    func parseRTUWrongUnitId() throws {
        var frame: [UInt8] = [
            0x02, // Wrong Unit ID
            0x2B, 0x0E, 0x01, 0x01,
            0x00, 0x00, 0x00,
        ]
        frame = appendModbusCRC(frame)

        #expect(throws: RTUError.unitIdMismatch(expected: 0x01, got: 0x02)) {
            try parseRTUDeviceIdentificationResponse(frame, expectedUnitId: 0x01)
        }
    }

    @Test("Parse RTU exception response")
    func parseRTUException() throws {
        var frame: [UInt8] = [
            0x01, // Unit ID
            0xAB, 0x02, // FC|0x80, IllegalDataAddress
        ]
        frame = appendModbusCRC(frame)

        #expect(throws: RTUError.exceptionResponse(.illegalDataAddress)) {
            try parseRTUDeviceIdentificationResponse(frame, expectedUnitId: 0x01)
        }
    }
}
