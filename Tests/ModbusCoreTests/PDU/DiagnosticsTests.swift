// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Diagnostics (FC 0x08).
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.8
/// Test vectors verified against pymodbus DiagnosticStatusRequest/Response.
@Suite("Diagnostics PDU")
struct DiagnosticsTests {
    // MARK: - Function Code Constant

    @Test("Function code constant")
    func functionCodeConstant() {
        #expect(ModbusFunctionCode.diagnostics == 0x08)
    }

    // MARK: - Sub-Function Enum Tests

    @Test("Sub-function raw values")
    func subFunctionRawValues() {
        #expect(DiagnosticSubFunction.returnQueryData.rawValue == 0x0000)
        #expect(DiagnosticSubFunction.restartCommunications.rawValue == 0x0001)
        #expect(DiagnosticSubFunction.returnDiagnosticRegister.rawValue == 0x0002)
        #expect(DiagnosticSubFunction.changeAsciiInputDelimiter.rawValue == 0x0003)
        #expect(DiagnosticSubFunction.forceListenOnlyMode.rawValue == 0x0004)
        #expect(DiagnosticSubFunction.clearCounters.rawValue == 0x000A)
        #expect(DiagnosticSubFunction.returnBusMessageCount.rawValue == 0x000B)
        #expect(DiagnosticSubFunction.returnBusCommunicationErrorCount.rawValue == 0x000C)
        #expect(DiagnosticSubFunction.returnBusExceptionErrorCount.rawValue == 0x000D)
        #expect(DiagnosticSubFunction.returnServerMessageCount.rawValue == 0x000E)
        #expect(DiagnosticSubFunction.returnServerNoResponseCount.rawValue == 0x000F)
        #expect(DiagnosticSubFunction.returnServerNAKCount.rawValue == 0x0010)
        #expect(DiagnosticSubFunction.returnServerBusyCount.rawValue == 0x0011)
        #expect(DiagnosticSubFunction.returnBusCharacterOverrunCount.rawValue == 0x0012)
        #expect(DiagnosticSubFunction.clearOverrunCounter.rawValue == 0x0014)
    }

    @Test("Sub-function CaseIterable count")
    func subFunctionCount() {
        // 15 sub-functions defined
        #expect(DiagnosticSubFunction.allCases.count == 15)
    }

    // MARK: - Request Builder Tests

    @Test("Build Return Query Data request")
    func buildReturnQueryDataRequest() {
        // Verified: pymodbus ReturnQueryDataRequest(0x1234).encode()
        let pdu = buildDiagnosticsPDU(subFunction: .returnQueryData, data: 0x1234)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x00, // Sub-function: Return Query Data
            0x12, 0x34, // Data
        ]

        #expect(pdu == expected)
    }

    @Test("Build Restart Communications request - normal")
    func buildRestartCommunicationsNormal() {
        // Verified: pymodbus RestartCommunicationsOptionRequest(False).encode()
        let pdu = buildDiagnosticsPDU(subFunction: .restartCommunications, data: 0x0000)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x01, // Sub-function: Restart Communications
            0x00, 0x00, // Data: Normal restart
        ]

        #expect(pdu == expected)
    }

    @Test("Build Restart Communications request - clear log")
    func buildRestartCommunicationsClearLog() {
        // Verified: pymodbus RestartCommunicationsOptionRequest(True).encode()
        let pdu = buildDiagnosticsPDU(subFunction: .restartCommunications, data: 0xFF00)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x01, // Sub-function: Restart Communications
            0xFF, 0x00, // Data: Clear event log
        ]

        #expect(pdu == expected)
    }

    @Test("Build Return Diagnostic Register request")
    func buildReturnDiagnosticRegister() {
        // Verified: pymodbus ReturnDiagnosticRegisterRequest().encode()
        let pdu = buildDiagnosticsPDU(subFunction: .returnDiagnosticRegister, data: 0x0000)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x02, // Sub-function: Return Diagnostic Register
            0x00, 0x00, // Data: Ignored
        ]

        #expect(pdu == expected)
    }

    @Test("Build Change ASCII Input Delimiter request")
    func buildChangeAsciiInputDelimiter() {
        // Verified: pymodbus ChangeAsciiInputDelimiterRequest(b'\\r').encode()
        // Delimiter in high byte, low byte = 0x00
        let pdu = buildDiagnosticsPDU(subFunction: .changeAsciiInputDelimiter, data: 0x0D00)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x03, // Sub-function: Change ASCII Input Delimiter
            0x0D, 0x00, // Data: CR (0x0D) in high byte
        ]

        #expect(pdu == expected)
    }

    @Test("Build Force Listen Only Mode request")
    func buildForceListenOnlyMode() {
        // Verified: pymodbus ForceListenOnlyModeRequest().encode()
        let pdu = buildDiagnosticsPDU(subFunction: .forceListenOnlyMode, data: 0x0000)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x04, // Sub-function: Force Listen Only Mode
            0x00, 0x00, // Data: Ignored
        ]

        #expect(pdu == expected)
    }

    @Test("Build Clear Counters request")
    func buildClearCounters() {
        // Verified: pymodbus ClearCountersRequest().encode()
        let pdu = buildDiagnosticsPDU(subFunction: .clearCounters, data: 0x0000)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x0A, // Sub-function: Clear Counters (10)
            0x00, 0x00, // Data: Ignored
        ]

        #expect(pdu == expected)
    }

    @Test("Build Return Bus Message Count request")
    func buildReturnBusMessageCount() {
        // Verified: pymodbus ReturnBusMessageCountRequest().encode()
        let pdu = buildDiagnosticsPDU(subFunction: .returnBusMessageCount, data: 0x0000)

        let expected: [UInt8] = [
            0x08, // Function code
            0x00, 0x0B, // Sub-function: Return Bus Message Count (11)
            0x00, 0x00, // Data: Ignored
        ]

        #expect(pdu == expected)
    }

    @Test("Build raw sub-function request")
    func buildRawSubFunctionRequest() {
        // For vendor-specific sub-functions
        let pdu = buildDiagnosticsPDU(subFunctionCode: 0xABCD, data: 0x1234)

        let expected: [UInt8] = [
            0x08, // Function code
            0xAB, 0xCD, // Sub-function: Custom
            0x12, 0x34, // Data
        ]

        #expect(pdu == expected)
    }

    @Test("PDU size is always 5 bytes")
    func pduSizeIsConstant() {
        for subFunction in DiagnosticSubFunction.allCases {
            let pdu = buildDiagnosticsPDU(subFunction: subFunction, data: 0x0000)
            #expect(pdu.count == 5)
        }
    }

    // MARK: - Response Parser Tests

    @Test("Parse Return Query Data response")
    func parseReturnQueryDataResponse() throws {
        // Verified: pymodbus ReturnQueryDataResponse(0x1234)
        let pdu: [UInt8] = [
            0x08, // Function code
            0x00, 0x00, // Sub-function
            0x12, 0x34, // Echoed data
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunction == 0x0000)
        #expect(response.subFunctionType == .returnQueryData)
        #expect(response.data == 0x1234)
    }

    @Test("Parse Restart Communications response")
    func parseRestartCommunicationsResponse() throws {
        let pdu: [UInt8] = [
            0x08, // Function code
            0x00, 0x01, // Sub-function
            0xFF, 0x00, // Echoed data (clear log)
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunction == 0x0001)
        #expect(response.subFunctionType == .restartCommunications)
        #expect(response.data == 0xFF00)
    }

    @Test("Parse Return Diagnostic Register response")
    func parseReturnDiagnosticRegisterResponse() throws {
        // Response contains the diagnostic register value
        let pdu: [UInt8] = [
            0x08, // Function code
            0x00, 0x02, // Sub-function
            0x00, 0x42, // Diagnostic register value
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunctionType == .returnDiagnosticRegister)
        #expect(response.data == 0x0042)
    }

    @Test("Parse Return Bus Message Count response")
    func parseReturnBusMessageCountResponse() throws {
        // Response contains the counter value
        let pdu: [UInt8] = [
            0x08, // Function code
            0x00, 0x0B, // Sub-function: Return Bus Message Count
            0x01, 0x23, // Counter value: 0x0123 = 291
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunctionType == .returnBusMessageCount)
        #expect(response.data == 0x0123)
    }

    @Test("Parse Clear Counters response")
    func parseClearCountersResponse() throws {
        // Response echoes request data
        let pdu: [UInt8] = [
            0x08, // Function code
            0x00, 0x0A, // Sub-function: Clear Counters
            0x00, 0x00, // Echoed data
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunctionType == .clearCounters)
        #expect(response.data == 0x0000)
    }

    @Test("Parse unknown sub-function response")
    func parseUnknownSubFunctionResponse() throws {
        // Unknown sub-function should still parse
        let pdu: [UInt8] = [
            0x08, // Function code
            0xFF, 0xFF, // Unknown sub-function
            0xAB, 0xCD, // Data
        ]

        let response = try parseDiagnosticsPDU(pdu)

        #expect(response.subFunction == 0xFFFF)
        #expect(response.subFunctionType == nil) // Not a known sub-function
        #expect(response.data == 0xABCD)
    }

    // MARK: - Exception Response Tests

    @Test("Parse exception response - Illegal Function")
    func parseExceptionIllegalFunction() throws {
        let pdu: [UInt8] = [0x88, 0x01] // FC|0x80 + IllegalFunction

        #expect(throws: PDUError.exceptionResponse(.illegalFunction)) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    @Test("Parse exception response - Illegal Data Value")
    func parseExceptionIllegalDataValue() throws {
        // Sub-function not supported
        let pdu: [UInt8] = [0x88, 0x03] // FC|0x80 + IllegalDataValue

        #expect(throws: PDUError.exceptionResponse(.illegalDataValue)) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    @Test("Parse exception response - Slave Device Failure")
    func parseExceptionSlaveDeviceFailure() throws {
        let pdu: [UInt8] = [0x88, 0x04] // FC|0x80 + SlaveDeviceFailure

        #expect(throws: PDUError.exceptionResponse(.slaveDeviceFailure)) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    // MARK: - Error Cases

    @Test("Parse PDU too short - empty")
    func parsePDUTooShortEmpty() {
        let pdu: [UInt8] = []

        #expect(throws: PDUError.pduTooShort) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    @Test("Parse PDU too short - only function code")
    func parsePDUTooShortOnlyFC() {
        let pdu: [UInt8] = [0x08]

        #expect(throws: PDUError.pduTooShort) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    @Test("Parse PDU too short - missing data bytes")
    func parsePDUTooShortMissingData() {
        let pdu: [UInt8] = [0x08, 0x00, 0x00, 0x12] // Only 4 bytes, need 5

        #expect(throws: PDUError.pduTooShort) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    @Test("Parse wrong function code throws")
    func parseWrongFunctionCode() {
        let pdu: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x00] // FC 0x03 instead of 0x08

        #expect(throws: PDUError.unexpectedFunctionCode(expected: 0x08, got: 0x03)) {
            try parseDiagnosticsPDU(pdu)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Return Query Data round-trip")
    func returnQueryDataRoundTrip() throws {
        let testData: UInt16 = 0xABCD
        let requestPDU = buildDiagnosticsPDU(subFunction: .returnQueryData, data: testData)

        // Response echoes request
        let response = try parseDiagnosticsPDU(requestPDU)

        #expect(response.subFunctionType == .returnQueryData)
        #expect(response.data == testData)
    }

    @Test("All sub-functions round-trip")
    func allSubFunctionsRoundTrip() throws {
        for subFunction in DiagnosticSubFunction.allCases {
            let testData: UInt16 = 0x5678
            let requestPDU = buildDiagnosticsPDU(subFunction: subFunction, data: testData)

            let response = try parseDiagnosticsPDU(requestPDU)

            #expect(response.subFunction == subFunction.rawValue)
            #expect(response.subFunctionType == subFunction)
            #expect(response.data == testData)
        }
    }

    // MARK: - Boundary Value Tests

    @Test("Maximum data value")
    func maximumDataValue() throws {
        let pdu = buildDiagnosticsPDU(subFunction: .returnQueryData, data: 0xFFFF)

        #expect(pdu[3] == 0xFF)
        #expect(pdu[4] == 0xFF)

        let response = try parseDiagnosticsPDU(pdu)
        #expect(response.data == 0xFFFF)
    }

    @Test("Zero data value")
    func zeroDataValue() throws {
        let pdu = buildDiagnosticsPDU(subFunction: .returnQueryData, data: 0x0000)

        #expect(pdu[3] == 0x00)
        #expect(pdu[4] == 0x00)

        let response = try parseDiagnosticsPDU(pdu)
        #expect(response.data == 0x0000)
    }
}
