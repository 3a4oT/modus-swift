// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Connection Tests

extension PymodbusIntegrationTests {
    // // MARK: - Multiple Sequential Requests

    /// @Test("Multiple sequential requests on same connection")
    func multipleSequentialRequests() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                for i: UInt16 in 0 ..< 5 {
                    let response = try await client.readHoldingRegisters(address: i * 10, count: 5, unitId: 1)
                    let expected = HoldingRegisterTestData.registerValues(startingAt: i * 10, count: 5)
                    #expect(response.registers == expected)
                }
            }
        }
    }

    // MARK: - Connection Lifecycle

    @Test("Reconnection after disconnect")
    func reconnectionAfterDisconnect() async throws {
        try await ReferenceServerManager.withServer { host, port in
            let client = ModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000))

            try await client.connect()
            let r1 = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
            #expect(r1.registers == [1])

            await client.close()
            #expect(client.connectionState == .disconnected)

            try await client.connect()
            let r2 = try await client.readHoldingRegisters(address: 1, count: 1, unitId: 1)
            #expect(r2.registers == [2])

            await client.close()
        }
    }

    // MARK: - Unit ID Tests

    @Test("Unit ID 1 (default device)")
    func unitIdDefault() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
                #expect(response.registers == [1])
            }
        }
    }

    @Test("Unit ID 0 (broadcast address)")
    func unitIdBroadcast() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 0)
                #expect(response.registers == [1])
            }
        }
    }

    @Test("Unit ID 247 (max standard device address)")
    func unitIdMaxStandard() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 247)
                #expect(response.registers == [1])
            }
        }
    }

    @Test("Unit ID 255 (reserved but commonly used)")
    func unitIdReserved() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 255)
                #expect(response.registers == [1])
            }
        }
    }
}
