// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

/// Tests for ModbusTLSClient.
///
/// Note: These are unit tests for client configuration and state management.
/// Integration tests with actual TLS servers require external setup.
@Suite("ModbusTLSClient")
struct ModbusTLSClientTests {
    // MARK: - Initialization

    @Test("Default initialization uses port 802")
    func defaultInitializationUsesPort802() {
        let client = ModbusTLSClient(host: "192.168.1.100")

        #expect(client.configuration.host == "192.168.1.100")
        #expect(client.configuration.port == 802)
    }

    @Test("Custom port overrides default")
    func customPortOverridesDefault() {
        let client = ModbusTLSClient(host: "192.168.1.100", port: 8802)

        #expect(client.configuration.port == 8802)
    }

    @Test("Custom timeout is respected")
    func customTimeoutIsRespected() {
        let client = ModbusTLSClient(
            host: "192.168.1.100",
            timeout: .seconds(10),
        )

        #expect(client.configuration.timeout == .seconds(10))
    }

    @Test("TLS configuration is stored")
    func tlsConfigurationIsStored() {
        let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()
        let client = ModbusTLSClient(
            host: "192.168.1.100",
            tlsConfiguration: tlsConfig,
        )

        #expect(client.tlsConfiguration.certificateVerification == .none)
    }

    // MARK: - Connection State

    @Test("Initial state is disconnected")
    func initialStateIsDisconnected() {
        let client = ModbusTLSClient(host: "192.168.1.100")

        #expect(client.isConnected == false)
        #expect(client.connectionState == .disconnected)
    }

    // MARK: - Error Cases

    @Test("Connection to invalid host fails")
    func connectionToInvalidHostFails() async {
        let client = ModbusTLSClient(
            host: "192.0.2.1", // TEST-NET-1, guaranteed unreachable
            port: 802,
            timeout: .milliseconds(100),
        )

        await #expect(throws: ModbusClientError.self) {
            try await client.connect()
        }
    }

    @Test("Read without connection throws notConnected")
    func readWithoutConnectionThrowsNotConnected() async {
        // Disable auto-reconnect
        let config = ModbusClientConfiguration(
            host: "192.168.1.100",
            port: 802,
            reconnectionStrategy: .disabled,
        )
        let client = ModbusTLSClient(configuration: config)

        await #expect(throws: ModbusClientError.notConnected) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    // MARK: - Configuration with ModbusClientConfiguration

    @Test("Initialization with ModbusClientConfiguration")
    func initializationWithModbusClientConfiguration() {
        let config = ModbusClientConfiguration(
            host: "10.0.0.1",
            port: 8802,
            timeout: .milliseconds(1000),
            retries: 3,
            idleTimeout: .seconds(30),
            reconnectionStrategy: .immediate,
        )
        let tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()

        let client = ModbusTLSClient(
            configuration: config,
            tlsConfiguration: tlsConfig,
        )

        #expect(client.configuration.host == "10.0.0.1")
        #expect(client.configuration.port == 8802)
        #expect(client.configuration.timeout == .milliseconds(1000))
        #expect(client.configuration.idleTimeout == .seconds(30))
        #expect(client.configuration.retries == 3)
    }
}
