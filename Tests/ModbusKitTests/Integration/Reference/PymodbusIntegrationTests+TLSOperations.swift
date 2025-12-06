// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - TLS Operations Tests

extension PymodbusIntegrationTests {
    // MARK: - Read Holding Registers (FC 0x03)

    @Test("Read holding registers over TLS")
    func tlsReadHoldingRegisters() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(900),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readHoldingRegisters(
                    address: 0,
                    count: 10,
                    unitId: 1,
                )

                let expected = HoldingRegisterTestData.registerValues(startingAt: 0, count: 10)
                #expect(response.registers == expected)
            }
        }
    }

    @Test("Read holding registers at offset over TLS")
    func tlsReadHoldingRegistersOffset() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readHoldingRegisters(
                    address: 100,
                    count: 5,
                    unitId: 1,
                )

                let expected = HoldingRegisterTestData.registerValues(startingAt: 100, count: 5)
                #expect(response.registers == expected)
            }
        }
    }

    @Test("Read maximum holding registers (125) over TLS")
    func tlsReadHoldingRegistersMax() async throws {
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
                    count: 125,
                    unitId: 1,
                )

                let expected = HoldingRegisterTestData.registerValues(startingAt: 0, count: 125)
                #expect(response.registers == expected)
            }
        }
    }

    // MARK: - Read Input Registers (FC 0x04)

    @Test("Read input registers over TLS")
    func tlsReadInputRegisters() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(900),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readInputRegisters(
                    address: 0,
                    count: 10,
                    unitId: 1,
                )

                let expected = InputRegisterTestData.registerValues(startingAt: 0, count: 10)
                #expect(response.registers == expected)
            }
        }
    }

    // MARK: - Write Single Register (FC 0x06)

    @Test("Write single register over TLS")
    func tlsWriteSingleRegister() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let writeResponse = try await client.writeSingleRegister(
                    address: 500,
                    value: 0xABCD,
                    unitId: 1,
                )
                #expect(writeResponse.address == 500)
                #expect(writeResponse.value == 0xABCD)

                let readResponse = try await client.readHoldingRegisters(
                    address: 500,
                    count: 1,
                    unitId: 1,
                )
                #expect(readResponse.registers == [0xABCD])
            }
        }
    }

    // MARK: - Write Multiple Registers (FC 0x10)

    @Test("Write multiple registers over TLS")
    func tlsWriteMultipleRegisters() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let values: [UInt16] = [0x1111, 0x2222, 0x3333, 0x4444]
                let writeResponse = try await client.writeMultipleRegisters(
                    address: 600,
                    values: values,
                    unitId: 1,
                )
                #expect(writeResponse.address == 600)
                #expect(writeResponse.quantity == 4)

                let readResponse = try await client.readHoldingRegisters(
                    address: 600,
                    count: 4,
                    unitId: 1,
                )
                #expect(readResponse.registers == values)
            }
        }
    }

    // MARK: - Read Coils (FC 0x01)

    @Test("Read coils over TLS")
    func tlsReadCoils() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(900),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readCoils(
                    address: 0,
                    count: 10,
                    unitId: 1,
                )

                let expected = CoilTestData.bitValues(startingAt: 0, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    // MARK: - Read Discrete Inputs (FC 0x02)

    @Test("Read discrete inputs over TLS")
    func tlsReadDiscreteInputs() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readDiscreteInputs(
                    address: 0,
                    count: 10,
                    unitId: 1,
                )

                let expected = DiscreteInputTestData.bitValues(startingAt: 0, count: 10)
                #expect(response.bits == expected)
            }
        }
    }

    // MARK: - Write Single Coil (FC 0x05)

    @Test("Write single coil over TLS")
    func tlsWriteSingleCoil() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let writeResponse = try await client.writeSingleCoil(
                    address: 500,
                    value: true,
                    unitId: 1,
                )
                #expect(writeResponse.address == 500)
                #expect(writeResponse.value == true)

                let readResponse = try await client.readCoils(
                    address: 500,
                    count: 1,
                    unitId: 1,
                )
                #expect(readResponse.bits == [true])
            }
        }
    }

    // MARK: - Write Multiple Coils (FC 0x0F)

    @Test("Write multiple coils over TLS")
    func tlsWriteMultipleCoils() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let values: [Bool] = [true, true, false, false, true, false, true, false]
                let writeResponse = try await client.writeMultipleCoils(
                    address: 600,
                    values: values,
                    unitId: 1,
                )
                #expect(writeResponse.address == 600)
                #expect(writeResponse.quantity == 8)

                let readResponse = try await client.readCoils(
                    address: 600,
                    count: 8,
                    unitId: 1,
                )
                #expect(readResponse.bits == values)
            }
        }
    }

    // MARK: - Mask Write Register (FC 0x16)

    @Test("Mask write register over TLS")
    func tlsMaskWriteRegister() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(900),
                tlsConfiguration: tlsConfig,
            ) { client in
                _ = try await client.writeSingleRegister(
                    address: 800,
                    value: 0x0000,
                    unitId: 1,
                )

                let response = try await client.maskWriteRegister(
                    address: 800,
                    andMask: 0xFF0F,
                    orMask: 0x00F0,
                    unitId: 1,
                )
                #expect(response.address == 800)
                #expect(response.andMask == 0xFF0F)
                #expect(response.orMask == 0x00F0)

                let readResponse = try await client.readHoldingRegisters(
                    address: 800,
                    count: 1,
                    unitId: 1,
                )
                #expect(readResponse.registers[0] == 0x00F0)
            }
        }
    }

    // MARK: - Read/Write Multiple Registers (FC 0x17)

    @Test("Read/Write multiple registers over TLS")
    func tlsReadWriteMultipleRegisters() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                _ = try await client.writeMultipleRegisters(
                    address: 870,
                    values: [0xAAAA, 0xBBBB],
                    unitId: 1,
                )

                let response = try await client.readWriteMultipleRegisters(
                    readAddress: 0,
                    readCount: 5,
                    writeAddress: 870,
                    writeValues: [0x1111, 0x2222],
                    unitId: 1,
                )

                #expect(response.registers == [1, 2, 3, 4, 5])

                let verifyResponse = try await client.readHoldingRegisters(
                    address: 870,
                    count: 2,
                    unitId: 1,
                )
                #expect(verifyResponse.registers == [0x1111, 0x2222])
            }
        }
    }

    // MARK: - Device Identification (FC 0x2B / MEI 0x0E)

    @Test("Read basic device identification over TLS")
    func tlsReadBasicDeviceIdentification() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(4000),
                tlsConfiguration: tlsConfig,
            ) { client in
                let response = try await client.readDeviceIdentification(
                    readCode: .basic,
                    unitId: 1,
                )

                #expect(response.vendorName == DeviceIdentificationTestData.vendorName)
                #expect(response.productCode == DeviceIdentificationTestData.productCode)
                #expect(response.revision == DeviceIdentificationTestData.revision)
            }
        }
    }
}
