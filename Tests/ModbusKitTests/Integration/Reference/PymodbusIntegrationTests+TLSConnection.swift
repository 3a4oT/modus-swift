// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - TLS Connection Tests

extension PymodbusIntegrationTests {
    // MARK: - TLS Connection Tests

    @Test("TLS connection with insecure configuration succeeds")
    func tlsConnectionInsecure() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                #expect(client.isConnected)
                #expect(client.connectionState == .connected)
            }
        }
    }

    @Test("TLS connection establishes secure channel")
    func tlsConnectionSecureChannel() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readHoldingRegisters(
                    address: 0,
                    count: 1,
                    unitId: 1,
                )
                #expect(response.registers.count == 1)
            }
        }
    }

    // MARK: - Multiple Sequential Requests

    @Test("Multiple sequential requests on same TLS connection")
    func tlsMultipleSequentialRequests() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                for i: UInt16 in 0 ..< 5 {
                    let response = try await client.readHoldingRegisters(
                        address: i * 10,
                        count: 5,
                        unitId: 1,
                    )
                    let expected = HoldingRegisterTestData.registerValues(
                        startingAt: i * 10,
                        count: 5,
                    )
                    #expect(response.registers == expected)
                }
            }
        }
    }

    // MARK: - Connection Lifecycle

    @Test("Reconnection after TLS disconnect")
    func tlsReconnectionAfterDisconnect() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            let client = ModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            )

            try await client.connect()
            let r1 = try await client.readHoldingRegisters(
                address: 0,
                count: 1,
                unitId: 1,
            )
            #expect(r1.registers == [1])

            await client.close()
            #expect(client.connectionState == .disconnected)

            try await client.connect()
            let r2 = try await client.readHoldingRegisters(
                address: 1,
                count: 1,
                unitId: 1,
            )
            #expect(r2.registers == [2])

            await client.close()
        }
    }

    // MARK: - Exception Response Tests

    @Test("Read beyond address space returns Illegal Data Address over TLS")
    func tlsReadBeyondAddressSpace() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readHoldingRegisters(
                        address: 1000,
                        count: 1,
                        unitId: 1,
                    )
                }
            }
        }
    }
}
