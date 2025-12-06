// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusSerial
import Testing

// MARK: - RTULocalEchoTests

/// Integration tests for RTU client local echo handling with MockSerialPort.
///
/// Reference: pymodbus `handle_local_echo`, minimalmodbus `handle_local_echo`
/// RS-485 half-duplex adapters may echo transmitted bytes back on receive line.
@Suite("RTU Local Echo")
struct RTULocalEchoTests {
    @Test("Local echo handling strips echoed request from response")
    func localEchoHandlingStripsEcho() async throws {
        let mock = MockSerialPort()
        await mock.setHoldingRegister(address: 0, value: 0x1234)
        await mock.injectLocalEcho(true)

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            handleLocalEcho: true,
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0x1234])

        await client.close()
    }

    @Test("Local echo disabled fails with CRC error when echo present")
    func localEchoDisabledFailsWithCRCError() async throws {
        let mock = MockSerialPort()
        await mock.setHoldingRegister(address: 0, value: 0x1234)
        await mock.injectLocalEcho(true)

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            retries: 0, // No retries to fail fast
            handleLocalEcho: false, // Echo not handled
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Should fail with CRC error because response starts with request bytes
        await #expect(throws: RTUClientError.self) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    @Test("Local echo handling works with no echo present")
    func localEchoHandlingWorksWithNoEcho() async throws {
        let mock = MockSerialPort()
        await mock.setHoldingRegister(address: 0, value: 0x5678)
        // Local echo NOT injected

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            handleLocalEcho: true, // Enabled but no echo
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Should still work - no echo to strip
        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0x5678])

        await client.close()
    }
}

// MARK: - ASCIILocalEchoTests

/// Integration tests for ASCII client local echo handling with MockSerialPort.
///
/// Reference: pymodbus `handle_local_echo`, minimalmodbus `handle_local_echo`
@Suite("ASCII Local Echo")
struct ASCIILocalEchoTests {
    @Test("Local echo handling strips echoed request from response")
    func localEchoHandlingStripsEcho() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0, value: 0xABCD)
        await mock.injectLocalEcho(true)

        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            handleLocalEcho: true,
        )

        let client = ModbusASCIIClient(port: mock, configuration: config)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0xABCD])

        await client.close()
    }

    @Test("Local echo disabled fails with LRC error when echo present")
    func localEchoDisabledFailsWithLRCError() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0, value: 0xABCD)
        await mock.injectLocalEcho(true)

        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            retries: 0,
            handleLocalEcho: false,
        )

        let client = ModbusASCIIClient(port: mock, configuration: config)
        try await client.connect()

        // Should fail with LRC error because response starts with request bytes
        await #expect(throws: ASCIIClientError.self) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    @Test("Local echo handling works with no echo present")
    func localEchoHandlingWorksWithNoEcho() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0, value: 0xEF01)
        // Local echo NOT injected

        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(100),
            ),
            handleLocalEcho: true,
        )

        let client = ModbusASCIIClient(port: mock, configuration: config)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0xEF01])

        await client.close()
    }
}
