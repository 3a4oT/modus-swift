// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Pipelining Tests

/// Validation tests for Transaction ID pipelining against pymodbus reference server.
///
/// These tests validate concurrent request handling with pipelining enabled,
/// ensuring responses are correctly matched by Transaction ID per Modbus TCP
/// specification Section 4.2.
///
/// **NOTE:** These tests are disabled because pymodbus server does NOT support pipelining.
///
/// When multiple requests are sent concurrently:
/// 1. pymodbus server receives all requests
/// 2. Server processes and responds to ONLY the first request
/// 3. Server drops/ignores subsequent requests
/// 4. Our client times out waiting for responses
///
/// This is expected behavior — many Modbus devices only support one outstanding
/// request at a time. Pipelining requires a server that explicitly supports it.
///
/// Reference: MODBUS Messaging on TCP/IP Implementation Guide V1.0b, Section 4.2
extension PymodbusIntegrationTests {
    // MARK: - Concurrent Read Tests

    @Test(
        "Concurrent reads with async let (pipelining enabled)",
        .disabled("pymodbus server does not support pipelining"),
    )
    func concurrentReadsWithAsyncLet() async throws {
        try await ReferenceServerManager.withServer { host, port in
            let config = ModbusClientConfiguration(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                pipelining: .enabled,
            )
            let client = ModbusTCPClient(configuration: config)
            try await client.connect()

            async let r1 = client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
            async let r2 = client.readHoldingRegisters(address: 100, count: 10, unitId: 1)
            async let r3 = client.readInputRegisters(address: 0, count: 10, unitId: 1)
            async let r4 = client.readInputRegisters(address: 50, count: 5, unitId: 1)

            let (result1, result2, result3, result4) = try await (r1, r2, r3, r4)

            await client.close()

            let expectedHolding1 = HoldingRegisterTestData.registerValues(startingAt: 0, count: 10)
            let expectedHolding2 = HoldingRegisterTestData.registerValues(startingAt: 100, count: 10)
            let expectedInput1 = InputRegisterTestData.registerValues(startingAt: 0, count: 10)

            #expect(result1.registers == expectedHolding1)
            #expect(result2.registers == expectedHolding2)
            #expect(result3.registers == expectedInput1)
            #expect(result4.registers == [510, 520, 530, 540, 550])
        }
    }

    @Test(
        "Concurrent reads with TaskGroup (pipelining enabled)",
        .disabled("pymodbus server does not support pipelining"),
    )
    func concurrentReadsWithTaskGroup() async throws {
        try await ReferenceServerManager.withServer { host, port in
            let config = ModbusClientConfiguration(
                host: host,
                port: port,
                timeout: .seconds(10),
                pipelining: PipeliningConfiguration(maxInFlight: 4, requestTimeout: .seconds(10)),
            )
            let client = ModbusTCPClient(configuration: config)
            try await client.connect()

            let results = try await withThrowingTaskGroup(
                of: (Int, [UInt16]).self,
                returning: [[UInt16]].self,
            ) { group in
                for i in 0 ..< 4 {
                    group.addTask {
                        let address = UInt16(i * 10)
                        let response = try await client.readHoldingRegisters(
                            address: address,
                            count: 5,
                            unitId: 1,
                        )
                        return (i, response.registers)
                    }
                }

                var collected = [[UInt16]](repeating: [], count: 4)
                for try await (index, registers) in group {
                    collected[index] = registers
                }
                return collected
            }

            await client.close()

            for i in 0 ..< 4 {
                let address = UInt16(i * 10)
                let expected = HoldingRegisterTestData.registerValues(startingAt: address, count: 5)
                #expect(results[i] == expected, "Result at index \(i) mismatch")
            }
        }
    }

    // MARK: - Serial Mode Comparison

    @Test("Serial mode still works correctly (baseline)")
    func serialModeBaseline() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                #expect(client.configuration.pipelining.isEnabled == false)

                let r1 = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
                let r2 = try await client.readHoldingRegisters(address: 100, count: 10, unitId: 1)

                let expected1 = HoldingRegisterTestData.registerValues(startingAt: 0, count: 10)
                let expected2 = HoldingRegisterTestData.registerValues(startingAt: 100, count: 10)

                #expect(r1.registers == expected1)
                #expect(r2.registers == expected2)
            }
        }
    }

    // MARK: - Mixed Operations

    @Test(
        "Concurrent mixed read and write operations",
        .disabled("pymodbus server does not support pipelining"),
    )
    func concurrentMixedOperations() async throws {
        try await ReferenceServerManager.withServer { host, port in
            let config = ModbusClientConfiguration(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                pipelining: .enabled,
            )
            let client = ModbusTCPClient(configuration: config)
            try await client.connect()

            async let readTask = client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
            async let writeTask = client.writeSingleRegister(address: 500, value: 0xABCD, unitId: 1)
            async let readCoilsTask = client.readCoils(address: 0, count: 16, unitId: 1)

            let (readResult, writeResult, coilsResult) = try await (readTask, writeTask, readCoilsTask)

            await client.close()

            let expectedRegisters = HoldingRegisterTestData.registerValues(startingAt: 0, count: 10)
            #expect(readResult.registers == expectedRegisters)
            #expect(writeResult.address == 500)
            #expect(writeResult.value == 0xABCD)
            #expect(coilsResult.bits.count == 16)
        }
    }
}
