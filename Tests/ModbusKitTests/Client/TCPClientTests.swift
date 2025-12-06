// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - ModbusTCPClient Unit Tests

@Suite("Modbus TCP Client")
struct TCPClientTests {
    // MARK: - Configuration Tests

    @Test("Default configuration has correct values")
    func defaultConfiguration() {
        let config = ModbusClientConfiguration(host: "192.168.1.100")

        #expect(config.host == "192.168.1.100")
        #expect(config.port == 502)
        #expect(config.timeout == .seconds(3))
        #expect(config.retries == 3)
    }

    @Test("Custom configuration preserves values")
    func customConfiguration() {
        let config = ModbusClientConfiguration(
            host: "10.0.0.1",
            port: 8899,
            timeout: .milliseconds(1000),
            retries: 5,
            idleTimeout: .seconds(30),
        )

        #expect(config.host == "10.0.0.1")
        #expect(config.port == 8899)
        #expect(config.timeout == .milliseconds(1000))
        #expect(config.retries == 5)
        #expect(config.idleTimeout == .seconds(30))
    }

    // MARK: - Idle Timeout Configuration Tests

    @Test("Default idle timeout is 60 seconds (goburrow default)")
    func defaultIdleTimeout() {
        let config = ModbusClientConfiguration(host: "localhost")

        #expect(config.idleTimeout == .seconds(60))
    }

    @Test("Idle timeout can be disabled with nil")
    func idleTimeoutDisabled() {
        let config = ModbusClientConfiguration(host: "localhost", idleTimeout: nil)

        #expect(config.idleTimeout == nil)
    }

    @Test("Custom idle timeout preserves value")
    func customIdleTimeout() {
        let config = ModbusClientConfiguration(host: "localhost", idleTimeout: .milliseconds(500))

        #expect(config.idleTimeout == .milliseconds(500))
    }

    @Test("Client initializes with host and port")
    func clientInitWithHostPort() {
        let client = ModbusTCPClient(host: "192.168.1.100", port: 502)

        #expect(client.connectionState == .disconnected)
    }

    @Test("Client initializes with configuration")
    func clientInitWithConfig() {
        let config = ModbusClientConfiguration(host: "10.0.0.1", port: 8899)
        let client = ModbusTCPClient(configuration: config)

        // nonisolated property can be accessed synchronously
        #expect(client.configuration.host == "10.0.0.1")
        #expect(client.configuration.port == 8899)
    }

    // MARK: - Connection State Tests

    @Test("Initial state is disconnected")
    func initialStateDisconnected() {
        let client = ModbusTCPClient(host: "localhost")

        #expect(client.connectionState == .disconnected)
    }

    @Test("ConnectionState enum values")
    func connectionStateValues() {
        let states: [ConnectionState] = [.disconnected, .connecting, .connected, .disconnecting]

        #expect(states.count == 4)
        #expect(ConnectionState.disconnected != ConnectionState.connected)
    }

    // MARK: - Parameter Validation Tests

    @Test("Validate count >= 1")
    func validateCountMinimum() throws {
        #expect(throws: ModbusClientError.invalidParameter("count must be >= 1")) {
            try validateReadParameters(count: 0)
        }
    }

    @Test("Validate count <= 125")
    func validateCountMaximum() throws {
        #expect(throws: ModbusClientError.invalidParameter("count must be <= 125")) {
            try validateReadParameters(count: 126)
        }
    }

    @Test("Valid count 1 passes validation")
    func validateCountOne() throws {
        try validateReadParameters(count: 1)
    }

    @Test("Valid count 125 passes validation")
    func validateCountMax() throws {
        try validateReadParameters(count: 125)
    }

    @Test("Valid count 10 passes validation")
    func validateCountTen() throws {
        try validateReadParameters(count: 10)
    }

    // MARK: - Write Parameter Validation Tests

    @Test("Validate write values must not be empty")
    func validateWriteValuesEmpty() throws {
        #expect(throws: ModbusClientError.invalidParameter("values must not be empty")) {
            try validateWriteParameters(values: [])
        }
    }

    @Test("Validate write values count <= 123")
    func validateWriteValuesMaximum() throws {
        let tooMany = [UInt16](repeating: 0, count: 124)
        #expect(throws: ModbusClientError.invalidParameter("values count must be <= 123")) {
            try validateWriteParameters(values: tooMany)
        }
    }

    @Test("Valid write values count 1 passes validation")
    func validateWriteValuesOne() throws {
        try validateWriteParameters(values: [0x1234])
    }

    @Test("Valid write values count 123 passes validation")
    func validateWriteValuesMax() throws {
        let maxValues = [UInt16](repeating: 0xABCD, count: 123)
        try validateWriteParameters(values: maxValues)
    }

    // MARK: - Transaction ID Generator Tests

    @Test("Transaction ID starts at 1")
    func transactionIdStartsAtOne() {
        let generator = TransactionIdGenerator()

        #expect(generator.next() == 1)
    }

    @Test("Transaction ID increments sequentially")
    func transactionIdIncrements() {
        let generator = TransactionIdGenerator()

        #expect(generator.next() == 1)
        #expect(generator.next() == 2)
        #expect(generator.next() == 3)
    }

    @Test("Transaction ID wraps at UInt16.max")
    func transactionIdWraps() {
        let generator = TransactionIdGenerator()

        // Generate 65535 IDs to reach max
        for _ in 1 ... 65535 {
            _ = generator.next()
        }

        // Next should wrap to 1 (skipping 0)
        #expect(generator.next() == 1)
    }

    @Test("Transaction ID skips 0")
    func transactionIdSkipsZero() {
        let generator = TransactionIdGenerator()

        // Generate many IDs
        var sawZero = false
        for _ in 1 ... 70000 {
            if generator.next() == 0 {
                sawZero = true
                break
            }
        }

        #expect(sawZero == false)
    }

    @Test("Transaction ID reset works")
    func transactionIdReset() {
        let generator = TransactionIdGenerator()

        _ = generator.next()
        _ = generator.next()
        generator.reset()

        #expect(generator.next() == 1)
    }

    // MARK: - Error Retryable Tests

    @Test("Timeout error is retryable")
    func timeoutIsRetryable() {
        #expect(ModbusClientError.timeout.isRetryable == true)
    }

    @Test("IO error is retryable")
    func ioErrorIsRetryable() {
        #expect(ModbusClientError.ioError("test").isRetryable == true)
    }

    @Test("Channel closed is retryable")
    func channelClosedIsRetryable() {
        #expect(ModbusClientError.channelClosed.isRetryable == true)
    }

    @Test("Connection failed is retryable")
    func connectionFailedIsRetryable() {
        #expect(ModbusClientError.connectionFailed("test").isRetryable == true)
    }

    @Test("Modbus exception is not retryable")
    func modbusExceptionNotRetryable() {
        #expect(ModbusClientError.modbusException(.illegalFunction).isRetryable == false)
    }

    @Test("Invalid parameter is not retryable")
    func invalidParameterNotRetryable() {
        #expect(ModbusClientError.invalidParameter("test").isRetryable == false)
    }

    @Test("Not connected is not retryable")
    func notConnectedNotRetryable() {
        #expect(ModbusClientError.notConnected.isRetryable == false)
    }

    // MARK: - Error Type Tests

    @Test("ModbusClientError.notConnected")
    func errorNotConnected() {
        let error = ModbusClientError.notConnected

        #expect(error == .notConnected)
    }

    @Test("ModbusClientError.alreadyConnected")
    func errorAlreadyConnected() {
        let error = ModbusClientError.alreadyConnected

        #expect(error == .alreadyConnected)
    }

    @Test("ModbusClientError.timeout")
    func errorTimeout() {
        let error = ModbusClientError.timeout

        #expect(error == .timeout)
    }

    @Test("ModbusClientError.connectionFailed with message")
    func errorConnectionFailed() {
        let error = ModbusClientError.connectionFailed("Host unreachable")

        #expect(error == .connectionFailed("Host unreachable"))
    }

    @Test("ModbusClientError.transactionIdMismatch")
    func errorTransactionIdMismatch() {
        let error = ModbusClientError.transactionIdMismatch(expected: 1, got: 2)

        #expect(error == .transactionIdMismatch(expected: 1, got: 2))
    }

    @Test("ModbusClientError.invalidParameter")
    func errorInvalidParameter() {
        let error = ModbusClientError.invalidParameter("count too large")

        #expect(error == .invalidParameter("count too large"))
    }

    @Test("ModbusClientError.modbusException")
    func errorModbusException() {
        let error = ModbusClientError.modbusException(.illegalFunction)

        #expect(error == .modbusException(.illegalFunction))
    }

    @Test("ModbusClientError.channelClosed")
    func errorChannelClosed() {
        let error = ModbusClientError.channelClosed

        #expect(error == .channelClosed)
    }

    // MARK: - Limits Tests

    @Test("Max read registers is 125")
    func maxReadRegisters() {
        #expect(ModbusClientLimits.maxReadRegisters == 125)
    }

    @Test("Max write registers is 123 (pymodbus MODBUS_MAX_WRITE_REGISTERS)")
    func maxWriteRegisters() {
        #expect(ModbusClientLimits.maxWriteRegisters == 123)
    }

    @Test("Max frame size is 260")
    func maxFrameSize() {
        #expect(ModbusClientLimits.maxFrameSize == 260)
    }

    @Test("Min response size is 8")
    func minResponseSize() {
        // MBAP header (7) + minimum PDU (1 function code)
        #expect(ModbusClientLimits.minResponseSize == 8)
    }

    // MARK: - Connection Error Tests (No Server)

    @Test("Connect to non-existent host throws connectionFailed")
    func connectNonExistentHost() async throws {
        let client = ModbusTCPClient(
            host: "192.0.2.1", // TEST-NET-1 (RFC 5737) - guaranteed unreachable
            port: 502,
            timeout: .milliseconds(100),
        )

        do {
            try await client.connect()
            Issue.record("Expected connection to fail")
        } catch {
            // Note: error is ModbusClientError due to typed throws
            switch error {
            case .timeout,
                 .connectionFailed:
                break // Expected
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        }

        await client.close()
    }

    @Test("Read without connect throws notConnected when reconnection disabled")
    func readWithoutConnectDisabled() async throws {
        let config = ModbusClientConfiguration(
            host: "localhost",
            reconnectionStrategy: .disabled,
        )
        let client = ModbusTCPClient(configuration: config)

        do {
            _ = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
            Issue.record("Expected notConnected error")
        } catch {
            #expect(error == .notConnected)
        }
    }

    @Test("Write single register without connect throws notConnected when reconnection disabled")
    func writeSingleWithoutConnectDisabled() async throws {
        let config = ModbusClientConfiguration(
            host: "localhost",
            reconnectionStrategy: .disabled,
        )
        let client = ModbusTCPClient(configuration: config)

        do {
            _ = try await client.writeSingleRegister(address: 0, value: 0x1234, unitId: 1)
            Issue.record("Expected notConnected error")
        } catch {
            #expect(error == .notConnected)
        }
    }

    @Test("Write multiple registers without connect throws notConnected when reconnection disabled")
    func writeMultipleWithoutConnectDisabled() async throws {
        let config = ModbusClientConfiguration(
            host: "localhost",
            reconnectionStrategy: .disabled,
        )
        let client = ModbusTCPClient(configuration: config)

        do {
            _ = try await client.writeMultipleRegisters(address: 0, values: [0x1234, 0x5678], unitId: 1)
            Issue.record("Expected notConnected error")
        } catch {
            #expect(error == .notConnected)
        }
    }

    // MARK: - Reconnection Strategy Tests

    @Test("Default reconnection strategy is immediate")
    func defaultReconnectionStrategy() {
        let config = ModbusClientConfiguration(host: "localhost")

        #expect(config.reconnectionStrategy == .immediate)
    }

    @Test("Reconnection strategy disabled preserves value")
    func reconnectionStrategyDisabled() {
        let config = ModbusClientConfiguration(
            host: "localhost",
            reconnectionStrategy: .disabled,
        )

        #expect(config.reconnectionStrategy == .disabled)
    }

    @Test("Reconnection strategy exponentialBackoff preserves values")
    func reconnectionStrategyExponentialBackoff() {
        let config = ModbusClientConfiguration(
            host: "localhost",
            reconnectionStrategy: .exponentialBackoff(
                initialDelay: .milliseconds(200),
                maxDelay: .seconds(60),
            ),
        )

        #expect(config.reconnectionStrategy == .exponentialBackoff(
            initialDelay: .milliseconds(200),
            maxDelay: .seconds(60),
        ))
    }

    @Test("Immediate strategy attempts reconnect on read")
    func immediateStrategyReconnects() async throws {
        // With immediate strategy, client should try to connect
        let config = ModbusClientConfiguration(
            host: "192.0.2.1", // TEST-NET-1 - unreachable
            timeout: .milliseconds(50),
            reconnectionStrategy: .immediate,
        )
        let client = ModbusTCPClient(configuration: config)

        do {
            _ = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
            Issue.record("Expected connection to fail")
        } catch {
            // Should be connectionFailed or timeout (not notConnected)
            switch error {
            case .connectionFailed,
                 .timeout:
                break // Expected - client tried to reconnect
            case .notConnected:
                Issue.record("With .immediate strategy, should attempt reconnect")
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }

        await client.close()
    }
}
