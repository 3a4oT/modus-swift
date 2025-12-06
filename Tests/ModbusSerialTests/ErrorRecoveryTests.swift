// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusSerial
import Testing

// MARK: - RTUErrorRecoveryTests

/// Integration tests for RTU client error recovery with MockSerialPort.
///
/// Reference: libmodbus MODBUS_ERROR_RECOVERY_LINK behavior:
/// - EBADF, ECONNRESET, EPIPE trigger reconnect
/// - close() → sleep(delay) → connect()
@Suite("RTU Error Recovery")
struct RTUErrorRecoveryTests {
    // MARK: - Link Mode Tests

    @Test("Link recovery reconnects on I/O error")
    func linkRecoveryReconnectsOnIOError() async throws {
        let mock = MockSerialPort()
        await mock.setHoldingRegister(address: 0, value: 0x1234)

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 1,
            errorRecovery: .link(delay: .milliseconds(10)),
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Fail first read attempt, then succeed
        // Deterministic: no race conditions with Task
        await mock.injectReadFailureCount(1)

        // This should fail first, trigger reconnect, then succeed
        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0x1234])

        await client.close()
    }

    @Test("Link recovery fails if reconnect fails")
    func linkRecoveryFailsIfReconnectFails() async throws {
        let mock = MockSerialPort()

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 0,
            errorRecovery: .link(delay: .milliseconds(10)),
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Inject I/O error and keep open failure enabled
        await mock.injectReadFailure(true)
        await mock.injectOpenFailure(true)

        await #expect(throws: RTUClientError.self) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    @Test("Disabled recovery does not reconnect on I/O error")
    func disabledRecoveryNoReconnect() async throws {
        let mock = MockSerialPort()

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 0,
            errorRecovery: .disabled,
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Inject I/O error
        await mock.injectReadFailure(true)

        do {
            _ = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
            Issue.record("Expected ioError")
        } catch {
            if case .ioError = error {
                // Expected
            } else {
                Issue.record("Expected ioError, got \(error)")
            }
        }

        await client.close()
    }

    // MARK: - Exponential Backoff Tests

    @Test("Exponential backoff reconnects on I/O error")
    func exponentialBackoffReconnects() async throws {
        let mock = MockSerialPort()
        await mock.setHoldingRegister(address: 0, value: 0x5678)

        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 1,
            errorRecovery: .exponentialBackoff(
                initialDelay: .milliseconds(5),
                maxDelay: .milliseconds(100),
            ),
        )

        let client = ModbusRTUClient(port: mock, configuration: config)
        try await client.connect()

        // Fail first read attempt, then succeed
        // Deterministic: no race conditions with Task
        await mock.injectReadFailureCount(1)

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0x5678])

        await client.close()
    }
}

// MARK: - ASCIIErrorRecoveryTests

/// Integration tests for ASCII client error recovery with MockSerialPort.
@Suite("ASCII Error Recovery")
struct ASCIIErrorRecoveryTests {
    @Test("Link recovery reconnects on I/O error")
    func linkRecoveryReconnectsOnIOError() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0, value: 0xABCD)

        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 1,
            errorRecovery: .link(delay: .milliseconds(10)),
        )

        let client = ModbusASCIIClient(port: mock, configuration: config)
        try await client.connect()

        // Fail first read attempt, then succeed
        // Deterministic: no race conditions with Task
        await mock.injectReadFailureCount(1)

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(response.registers == [0xABCD])

        await client.close()
    }

    @Test("Disabled recovery does not reconnect on I/O error")
    func disabledRecoveryNoReconnect() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)

        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .milliseconds(50),
            ),
            retries: 0,
            errorRecovery: .disabled,
        )

        let client = ModbusASCIIClient(port: mock, configuration: config)
        try await client.connect()

        await mock.injectReadFailure(true)

        do {
            _ = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
            Issue.record("Expected ioError")
        } catch {
            if case .ioError = error {
                // Expected
            } else {
                Issue.record("Expected ioError, got \(error)")
            }
        }

        await client.close()
    }
}
