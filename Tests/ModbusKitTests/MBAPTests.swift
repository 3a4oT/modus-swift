// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for MBAP (Modbus Application Protocol) header implementation.
///
/// Test vectors verified against:
/// - pymodbus framer/socket.py
/// - libmodbus modbus-tcp.c
/// - goburrow/modbus tcpclient.go
@Suite("MBAP Header")
struct MBAPTests {
    // MARK: - Constants Tests

    @Test("Header size is 7 bytes")
    func headerSize() {
        // Verified: pymodbus MIN_SIZE=8 (header+1), libmodbus _MODBUS_TCP_HEADER_LENGTH=7
        #expect(MBAPConstants.headerSize == 7)
    }

    @Test("Protocol ID is 0x0000")
    func protocolId() {
        // Verified: goburrow tcpProtocolIdentifier = 0x0000
        #expect(MBAPConstants.protocolId == 0x0000)
    }

    @Test("Maximum ADU size is 260 bytes")
    func maximumADUSize() {
        // Verified: goburrow tcpMaxLength = 260
        #expect(MBAPConstants.maximumADUSize == 260)
    }

    @Test("Default port is 502")
    func defaultPort() {
        #expect(MBAPConstants.defaultPort == 502)
    }

    @Test("Offsets are correct")
    func offsets() {
        #expect(MBAPOffset.transactionId == 0)
        #expect(MBAPOffset.protocolId == 2)
        #expect(MBAPOffset.length == 4)
        #expect(MBAPOffset.unitId == 6)
        #expect(MBAPOffset.pdu == 7)
    }

    // MARK: - Header Builder Tests

    @Test("Build header with transaction ID 0x0001")
    func buildHeaderSimple() {
        let header = MBAPHeader(transactionId: 0x0001, unitId: 0x01, pduLength: 6)
        let bytes = buildMBAPHeader(header)

        // Expected: TID=0x0001, PID=0x0000, LEN=7 (6+1), UID=0x01
        let expected: [UInt8] = [
            0x00, 0x01, // Transaction ID (BE)
            0x00, 0x00, // Protocol ID (BE)
            0x00, 0x07, // Length: 6 (PDU) + 1 (UID) = 7 (BE)
            0x01, // Unit ID
        ]

        #expect(bytes == expected)
        #expect(bytes.count == MBAPConstants.headerSize)
    }

    @Test("Build header with large transaction ID")
    func buildHeaderLargeTID() {
        let header = MBAPHeader(transactionId: 0xABCD, unitId: 0xFF, pduLength: 5)
        let bytes = buildMBAPHeader(header)

        let expected: [UInt8] = [
            0xAB, 0xCD, // Transaction ID (BE)
            0x00, 0x00, // Protocol ID (BE)
            0x00, 0x06, // Length: 5 + 1 = 6 (BE)
            0xFF, // Unit ID
        ]

        #expect(bytes == expected)
    }

    @Test("Build complete ADU for Read Holding Registers")
    func buildADUReadHolding() {
        // Read 10 registers starting from 0x0000
        // PDU: FC=0x03, Start=0x0000, Quantity=0x000A
        let pdu: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x0A]
        let adu = buildModbusTCPADU(transactionId: 0x0001, unitId: 0x01, pdu: pdu)

        let expected: [UInt8] = [
            // MBAP Header
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x06, // Length: 5 (PDU) + 1 (UID) = 6
            0x01, // Unit ID
            // PDU
            0x03, // Function code
            0x00, 0x00, // Start address
            0x00, 0x0A, // Quantity
        ]

        #expect(adu == expected)
        #expect(adu.count == 12) // 7 header + 5 PDU
    }

    // MARK: - Header Parser Tests

    @Test("Parse valid MBAP header")
    func parseValidHeader() throws {
        let frame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x06, // Length
            0x01, // Unit ID
        ]

        let header = try parseMBAPHeader(frame)

        #expect(header.transactionId == 0x0001)
        #expect(header.protocolId == 0x0000)
        #expect(header.length == 6)
        #expect(header.unitId == 0x01)
    }

    @Test("Parse header with max transaction ID")
    func parseMaxTransactionId() throws {
        let frame: [UInt8] = [
            0xFF, 0xFF, // Transaction ID = 65535
            0x00, 0x00, // Protocol ID
            0x00, 0x05, // Length
            0x0A, // Unit ID
        ]

        let header = try parseMBAPHeader(frame)

        #expect(header.transactionId == 0xFFFF)
        #expect(header.unitId == 0x0A)
    }

    @Test("Parse header - frame too short")
    func parseFrameTooShort() {
        let frame: [UInt8] = [0x00, 0x01, 0x00, 0x00, 0x00] // Only 5 bytes

        #expect(throws: MBAPError.frameTooShort) {
            try parseMBAPHeader(frame)
        }
    }

    @Test("Parse header - empty frame")
    func parseEmptyFrame() {
        let frame: [UInt8] = []

        #expect(throws: MBAPError.frameTooShort) {
            try parseMBAPHeader(frame)
        }
    }

    @Test("Parse header - invalid protocol ID")
    func parseInvalidProtocolId() {
        let frame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x01, // Protocol ID = 0x0001 (invalid, must be 0x0000)
            0x00, 0x06, // Length
            0x01, // Unit ID
        ]

        #expect(throws: MBAPError.invalidProtocolId(0x0001)) {
            try parseMBAPHeader(frame)
        }
    }

    // MARK: - Complete ADU Parser Tests

    @Test("Parse complete ADU")
    func parseCompleteADU() throws {
        // Response to Read Holding Registers: 3 registers
        let frame: [UInt8] = [
            // MBAP Header
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x09, // Length: 1 (UID) + 8 (PDU) = 9
            0x01, // Unit ID
            // PDU
            0x03, // Function code
            0x06, // Byte count
            0x00, 0x01, // Register 0
            0x00, 0x02, // Register 1
            0x00, 0x03, // Register 2
        ]

        let (header, pdu) = try parseModbusTCPADU(frame)

        #expect(header.transactionId == 0x0001)
        #expect(header.length == 9)
        #expect(pdu.count == 8) // Function + byte count + 6 data bytes
        #expect(pdu[0] == 0x03) // Function code
        #expect(pdu[1] == 0x06) // Byte count
    }

    @Test("Parse ADU - validate transaction ID")
    func parseADUValidateTransactionId() throws {
        let frame: [UInt8] = [
            0x00, 0x05, // Transaction ID = 5
            0x00, 0x00,
            0x00, 0x03,
            0x01,
            0x03, 0x00, // Minimal PDU
        ]

        // Should succeed with matching transaction ID
        let (header, _) = try parseModbusTCPADU(frame, expectedTransactionId: 0x0005)
        #expect(header.transactionId == 0x0005)
    }

    @Test("Parse ADU - transaction ID mismatch")
    func parseADUTransactionMismatch() {
        let frame: [UInt8] = [
            0x00, 0x05, // Transaction ID = 5
            0x00, 0x00,
            0x00, 0x03,
            0x01,
            0x03, 0x00,
        ]

        #expect(throws: MBAPError.transactionIdMismatch(expected: 0x0001, got: 0x0005)) {
            try parseModbusTCPADU(frame, expectedTransactionId: 0x0001)
        }
    }

    @Test("Parse ADU - validate unit ID")
    func parseADUValidateUnitId() throws {
        // Reference: goburrow/modbus tcpclient.go Verify()
        // Validates aduResponse[6] == aduRequest[6]
        let frame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x03, // Length
            0x05, // Unit ID = 5
            0x03, 0x00, // Minimal PDU
        ]

        // Should succeed with matching unit ID
        let (header, _) = try parseModbusTCPADU(frame, expectedUnitId: 0x05)
        #expect(header.unitId == 0x05)
    }

    @Test("Parse ADU - unit ID mismatch")
    func parseADUUnitIdMismatch() {
        // Reference: goburrow/modbus returns error when unit IDs don't match
        let frame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x00, // Protocol ID
            0x00, 0x03, // Length
            0x05, // Unit ID = 5
            0x03, 0x00, // Minimal PDU
        ]

        #expect(throws: MBAPError.unitIdMismatch(expected: 0x01, got: 0x05)) {
            try parseModbusTCPADU(frame, expectedUnitId: 0x01)
        }
    }

    @Test("Parse ADU - validate both transaction ID and unit ID")
    func parseADUValidateBoth() throws {
        let frame: [UInt8] = [
            0x12, 0x34, // Transaction ID = 0x1234
            0x00, 0x00, // Protocol ID
            0x00, 0x03, // Length
            0x0A, // Unit ID = 10
            0x03, 0x00, // Minimal PDU
        ]

        // Should succeed with both matching
        let (header, _) = try parseModbusTCPADU(
            frame,
            expectedTransactionId: 0x1234,
            expectedUnitId: 0x0A,
        )
        #expect(header.transactionId == 0x1234)
        #expect(header.unitId == 0x0A)
    }

    @Test("Parse ADU - length mismatch")
    func parseADULengthMismatch() {
        let frame: [UInt8] = [
            0x00, 0x01,
            0x00, 0x00,
            0x00, 0x10, // Length claims 16, but only 2 bytes follow
            0x01,
            0x03, 0x00, // Only 2 PDU bytes
        ]

        #expect(throws: MBAPError.lengthMismatch(declared: 16, actual: 3)) {
            try parseModbusTCPADU(frame)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Build and parse round-trip")
    func roundTrip() throws {
        let pdu: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x0A]
        let adu = buildModbusTCPADU(transactionId: 0x1234, unitId: 0x0F, pdu: pdu)

        let (header, parsedPDU) = try parseModbusTCPADU(adu)

        #expect(header.transactionId == 0x1234)
        #expect(header.unitId == 0x0F)
        #expect(header.protocolId == 0x0000)
        #expect(Array(parsedPDU) == pdu)
    }

    // MARK: - MBAPHeader Struct Tests

    @Test("MBAPHeader calculates length correctly")
    func headerLengthCalculation() {
        let header = MBAPHeader(transactionId: 1, unitId: 1, pduLength: 10)

        // Length should be PDU length + 1 (for Unit ID)
        #expect(header.length == 11)
    }

    @Test("MBAPHeader is Equatable")
    func headerEquatable() {
        let h1 = MBAPHeader(transactionId: 1, unitId: 1, pduLength: 5)
        let h2 = MBAPHeader(transactionId: 1, unitId: 1, pduLength: 5)
        let h3 = MBAPHeader(transactionId: 2, unitId: 1, pduLength: 5)

        #expect(h1 == h2)
        #expect(h1 != h3)
    }
}
