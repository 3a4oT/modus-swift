// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Coils Tests (FC 0x01, 0x02, 0x05, 0x0F)

extension PymodbusIntegrationTests {
    // MARK: - Read Coils (FC 0x01)

    @Test("Read coils from reference server")
    func readCoils() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readCoils(address: 0, count: 10, unitId: 1)

                let expected = CoilTestData.bitValues(startingAt: 0, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    @Test("Read coils at offset validates pattern")
    func readCoilsOffset() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readCoils(address: 100, count: 10, unitId: 1)

                let expected = CoilTestData.bitValues(startingAt: 100, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    // MARK: - Read Discrete Inputs (FC 0x02)

    @Test("Read discrete inputs from reference server")
    func readDiscreteInputs() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readDiscreteInputs(address: 0, count: 10, unitId: 1)

                let expected = DiscreteInputTestData.bitValues(startingAt: 0, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    @Test("Read discrete inputs at boundary")
    func readDiscreteInputsBoundary() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readDiscreteInputs(address: 95, count: 10, unitId: 1)

                let expected = DiscreteInputTestData.bitValues(startingAt: 95, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    // MARK: - Write Single Coil (FC 0x05)

    @Test("Write single coil to reference server")
    func writeSingleCoil() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let writeResponse = try await client.writeSingleCoil(address: 500, value: true, unitId: 1)
                #expect(writeResponse.address == 500)
                #expect(writeResponse.value == true)

                let readResponse = try await client.readCoils(address: 500, count: 1, unitId: 1)
                #expect(readResponse.bits == [true])
            }
        }
    }

    @Test("Write single coil OFF to reference server")
    func writeSingleCoilOff() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let writeResponse = try await client.writeSingleCoil(address: 0, value: false, unitId: 1)
                #expect(writeResponse.address == 0)
                #expect(writeResponse.value == false)

                let readResponse = try await client.readCoils(address: 0, count: 1, unitId: 1)
                #expect(readResponse.bits == [false])
            }
        }
    }

    // MARK: - Write Multiple Coils (FC 0x0F)

    @Test("Write multiple coils to reference server")
    func writeMultipleCoils() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let values: [Bool] = [true, true, false, false, true, false, true, false]
                let writeResponse = try await client.writeMultipleCoils(address: 600, values: values, unitId: 1)
                #expect(writeResponse.address == 600)
                #expect(writeResponse.quantity == 8)

                let readResponse = try await client.readCoils(address: 600, count: 8, unitId: 1)
                #expect(readResponse.bits == values)
            }
        }
    }

    @Test("Write coils across byte boundary")
    func writeCoilsAcrossByteBoundary() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let values: [Bool] = [true, false, true, false, true, false, true, false, true, true]
                let writeResponse = try await client.writeMultipleCoils(address: 700, values: values, unitId: 1)
                #expect(writeResponse.address == 700)
                #expect(writeResponse.quantity == 10)

                let readResponse = try await client.readCoils(address: 700, count: 10, unitId: 1)
                #expect(readResponse.bits == values)
            }
        }
    }
}
