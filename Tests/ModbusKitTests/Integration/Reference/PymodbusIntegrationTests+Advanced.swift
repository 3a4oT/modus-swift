// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Advanced Tests (FC 0x16, 0x17, 0x18, 0x2B)

extension PymodbusIntegrationTests {
    // MARK: - Mask Write Register (FC 0x16)

    @Test("Mask write register sets specific bits")
    func maskWriteRegisterSetBits() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                _ = try await client.writeSingleRegister(address: 800, value: 0x0000, unitId: 1)

                let response = try await client.maskWriteRegister(
                    address: 800,
                    andMask: 0xFF0F,
                    orMask: 0x00F0,
                    unitId: 1,
                )
                #expect(response.address == 800)
                #expect(response.andMask == 0xFF0F)
                #expect(response.orMask == 0x00F0)

                let readResponse = try await client.readHoldingRegisters(address: 800, count: 1, unitId: 1)
                #expect(readResponse.registers[0] == 0x00F0)
            }
        }
    }

    @Test("Mask write register clears specific bits")
    func maskWriteRegisterClearBits() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                _ = try await client.writeSingleRegister(address: 801, value: 0xFFFF, unitId: 1)

                let response = try await client.maskWriteRegister(
                    address: 801,
                    andMask: 0xFFF0,
                    orMask: 0x0000,
                    unitId: 1,
                )
                #expect(response.address == 801)

                let readResponse = try await client.readHoldingRegisters(address: 801, count: 1, unitId: 1)
                #expect(readResponse.registers[0] == 0xFFF0)
            }
        }
    }

    // MARK: - Read/Write Multiple Registers (FC 0x17)

    @Test("Read/Write multiple registers atomically")
    func readWriteMultipleRegistersAtomic() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                _ = try await client.writeMultipleRegisters(address: 870, values: [0xAAAA, 0xBBBB], unitId: 1)

                let response = try await client.readWriteMultipleRegisters(
                    readAddress: 0,
                    readCount: 5,
                    writeAddress: 870,
                    writeValues: [0x1111, 0x2222],
                    unitId: 1,
                )

                #expect(response.registers == [1, 2, 3, 4, 5])

                let verifyResponse = try await client.readHoldingRegisters(address: 870, count: 2, unitId: 1)
                #expect(verifyResponse.registers == [0x1111, 0x2222])
            }
        }
    }

    @Test("Read/Write multiple registers with single register")
    func readWriteMultipleRegistersSingle() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readWriteMultipleRegisters(
                    readAddress: 10,
                    readCount: 1,
                    writeAddress: 880,
                    writeValues: [0xDEAD],
                    unitId: 1,
                )

                #expect(response.registers == [11])

                let verifyResponse = try await client.readHoldingRegisters(address: 880, count: 1, unitId: 1)
                #expect(verifyResponse.registers == [0xDEAD])
            }
        }
    }

    // MARK: - Read FIFO Queue (FC 0x18)

    /// pymodbus has a known bug in ReadFifoQueueResponse encoding.
    /// pymodbus encodes FIFO count as byte count, but Modbus spec (V1.1b3 Section 6.18)
    /// requires register count: `byte_count = 2 + (FIFO_count × 2)`
    ///
    /// See: https://github.com/riptideio/pymodbus/issues/529
    ///
    /// Our implementation follows the Modbus specification.
    /// Unit tests for FC 0x18: Tests/ModbusKitTests/PDU/Advanced/ReadFIFOQueueTests.swift
    @Test(
        "Read FIFO queue returns sequential values",
        .disabled("pymodbus FIFO response encoding bug - see issue #529"),
    )
    func readFIFOQueueSequential() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readFIFOQueue(address: 0, unitId: 1)
                #expect(response.fifoCount >= 1)
                #expect(response.registers.count == response.fifoCount)
            }
        }
    }

    @Test(
        "Read FIFO queue at different address",
        .disabled("pymodbus FIFO response encoding bug - see issue #529"),
    )
    func readFIFOQueueAtOffset() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readFIFOQueue(address: 10, unitId: 1)
                #expect(response.fifoCount >= 1)
            }
        }
    }

    // MARK: - Device Identification (FC 0x2B / MEI 0x0E)

    @Test("Read basic device identification returns mandatory objects")
    func readBasicDeviceIdentification() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readDeviceIdentification(readCode: .basic, unitId: 1)

                #expect(response.vendorName == DeviceIdentificationTestData.vendorName)
                #expect(response.productCode == DeviceIdentificationTestData.productCode)
                #expect(response.revision == DeviceIdentificationTestData.revision)
            }
        }
    }

    @Test("Read regular device identification returns extended objects")
    func readRegularDeviceIdentification() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readDeviceIdentification(readCode: .regular, unitId: 1)

                #expect(response.vendorName == DeviceIdentificationTestData.vendorName)
                #expect(response.productCode == DeviceIdentificationTestData.productCode)
                #expect(response.revision == DeviceIdentificationTestData.revision)
                #expect(response.vendorUrl == DeviceIdentificationTestData.vendorUrl)
                #expect(response.productName == DeviceIdentificationTestData.productName)
                #expect(response.modelName == DeviceIdentificationTestData.modelName)
            }
        }
    }

    @Test("Read specific device identification object")
    func readSpecificDeviceIdentification() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readDeviceIdentification(
                    readCode: .specific,
                    objectId: 0x00,
                    unitId: 1,
                )

                #expect(response.vendorName == DeviceIdentificationTestData.vendorName)
                #expect(response.objects.count == 1)
            }
        }
    }
}
