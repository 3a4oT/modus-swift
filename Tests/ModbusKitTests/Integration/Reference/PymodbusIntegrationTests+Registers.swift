// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Registers Tests (FC 0x03, 0x04, 0x06, 0x10)

extension PymodbusIntegrationTests {
    // MARK: - Read Holding Registers (FC 0x03)

    @Test("Read holding registers from reference server")
    func readHoldingRegisters() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)

                let expected = HoldingRegisterTestData.registerValues(startingAt: 0, count: 10)
                #expect(response.registers == expected)
            }
        }
    }

    @Test("Read holding registers at offset")
    func readHoldingRegistersOffset() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 100, count: 5, unitId: 1)

                let expected = HoldingRegisterTestData.registerValues(startingAt: 100, count: 5)
                #expect(response.registers == expected)
            }
        }
    }

    @Test("Read maximum holding registers (125)")
    func readHoldingRegistersMax() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 125, unitId: 1)

                let expected = HoldingRegisterTestData.registerValues(startingAt: 0, count: 125)
                #expect(response.registers == expected)
            }
        }
    }

    // MARK: - Read Input Registers (FC 0x04)

    @Test("Read input registers from reference server")
    func readInputRegisters() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readInputRegisters(address: 0, count: 10, unitId: 1)

                let expected = InputRegisterTestData.registerValues(startingAt: 0, count: 10)
                #expect(response.registers == expected)
            }
        }
    }

    @Test("Read input registers validates address * 10 pattern")
    func readInputRegistersPattern() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readInputRegisters(address: 50, count: 5, unitId: 1)
                #expect(response.registers == [510, 520, 530, 540, 550])
            }
        }
    }

    // MARK: - Write Single Register (FC 0x06)

    @Test("Write single register to reference server")
    func writeSingleRegister() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let writeResponse = try await client.writeSingleRegister(address: 500, value: 0xABCD, unitId: 1)
                #expect(writeResponse.address == 500)
                #expect(writeResponse.value == 0xABCD)

                let readResponse = try await client.readHoldingRegisters(address: 500, count: 1, unitId: 1)
                #expect(readResponse.registers == [0xABCD])
            }
        }
    }

    // MARK: - Write Multiple Registers (FC 0x10)

    @Test("Write multiple registers to reference server")
    func writeMultipleRegisters() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let values: [UInt16] = [0x1111, 0x2222, 0x3333, 0x4444]
                let writeResponse = try await client.writeMultipleRegisters(address: 600, values: values, unitId: 1)
                #expect(writeResponse.address == 600)
                #expect(writeResponse.quantity == 4)

                let readResponse = try await client.readHoldingRegisters(address: 600, count: 4, unitId: 1)
                #expect(readResponse.registers == values)
            }
        }
    }
}
