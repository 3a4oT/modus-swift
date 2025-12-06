// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore
@testable import ModbusKit
import Testing

/// Tests for ModbusUDPClient with MockUDPTransport.
@Suite("ModbusUDPClient")
struct UDPClientTests {
    // MARK: - Configuration

    let defaultConfig = ModbusUDPClientConfiguration(
        host: "127.0.0.1",
        port: 502,
        timeout: .milliseconds(100),
        retries: 0,
    )

    // MARK: - Connection Tests

    @Test("Connect binds transport")
    func connectBindsTransport() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)

        #expect(!client.isConnected)
        try await client.connect()
        #expect(client.isConnected)

        await client.close()
    }

    @Test("Connect when already connected throws")
    func connectAlreadyConnected() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)

        try await client.connect()

        await #expect(throws: ModbusClientError.alreadyConnected) {
            try await client.connect()
        }

        await client.close()
    }

    @Test("Close unbinds transport")
    func closeUnbindsTransport() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)

        try await client.connect()
        #expect(client.isConnected)

        await client.close()
        #expect(!client.isConnected)
    }

    // MARK: - Read Holding Registers Tests

    @Test("Read single holding register")
    func readSingleHoldingRegister() async throws {
        let mock = MockUDPTransport()
        await mock.setHoldingRegister(address: 0x0000, value: 0x1234)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0x0000, count: 1, unitId: 1)

        #expect(response.registers == [0x1234])
        #expect(response.count == 1)

        await client.close()
    }

    @Test("Read multiple holding registers")
    func readMultipleHoldingRegisters() async throws {
        let mock = MockUDPTransport()
        await mock.setHoldingRegister(address: 0, value: 0x0001)
        await mock.setHoldingRegister(address: 1, value: 0x0002)
        await mock.setHoldingRegister(address: 2, value: 0x0003)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 3, unitId: 1)

        #expect(response.registers == [0x0001, 0x0002, 0x0003])
        #expect(response.count == 3)

        await client.close()
    }

    @Test("Read uninitialized registers returns zeros")
    func readUninitializedRegisters() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 100, count: 2, unitId: 1)

        #expect(response.registers == [0x0000, 0x0000])

        await client.close()
    }

    // MARK: - Read Input Registers Tests

    @Test("Read input registers")
    func readInputRegisters() async throws {
        let mock = MockUDPTransport()
        await mock.setInputRegister(address: 10, value: 0xABCD)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readInputRegisters(address: 10, count: 1, unitId: 1)

        #expect(response.registers == [0xABCD])

        await client.close()
    }

    // MARK: - Read Coils Tests

    @Test("Read coils")
    func readCoils() async throws {
        let mock = MockUDPTransport()
        await mock.setCoil(address: 0, value: true)
        await mock.setCoil(address: 1, value: false)
        await mock.setCoil(address: 2, value: true)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readCoils(address: 0, count: 3, unitId: 1)

        #expect(response.count == 3)
        #expect(response.bits == [true, false, true])

        await client.close()
    }

    // MARK: - Read Discrete Inputs Tests

    @Test("Read discrete inputs")
    func readDiscreteInputs() async throws {
        let mock = MockUDPTransport()
        await mock.setDiscreteInput(address: 5, value: true)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readDiscreteInputs(address: 5, count: 1, unitId: 1)

        #expect(response.count == 1)
        #expect(response.bits == [true])

        await client.close()
    }

    // MARK: - Write Single Register Tests

    @Test("Write single register")
    func writeSingleRegister() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.writeSingleRegister(address: 0x0010, value: 0x5678, unitId: 1)

        #expect(response.address == 0x0010)

        // Verify storage was updated
        let storage = await mock.storage
        #expect(storage.holdingRegisters[0x0010] == 0x5678)

        await client.close()
    }

    // MARK: - Write Multiple Registers Tests

    @Test("Write multiple registers")
    func writeMultipleRegisters() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let values: [UInt16] = [0x1111, 0x2222, 0x3333]
        let response = try await client.writeMultipleRegisters(address: 0x0020, values: values, unitId: 1)

        #expect(response.address == 0x0020)
        #expect(response.quantity == 3)

        // Verify storage
        let storage = await mock.storage
        #expect(storage.holdingRegisters[0x0020] == 0x1111)
        #expect(storage.holdingRegisters[0x0021] == 0x2222)
        #expect(storage.holdingRegisters[0x0022] == 0x3333)

        await client.close()
    }

    // MARK: - Write Single Coil Tests

    @Test("Write single coil ON")
    func writeSingleCoilOn() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.writeSingleCoil(address: 0x0005, value: true, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0x0005] == true)

        await client.close()
    }

    @Test("Write single coil OFF")
    func writeSingleCoilOff() async throws {
        let mock = MockUDPTransport()
        await mock.setCoil(address: 0x0005, value: true)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.writeSingleCoil(address: 0x0005, value: false, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0x0005] == false)

        await client.close()
    }

    // MARK: - Write Multiple Coils Tests

    @Test("Write multiple coils")
    func writeMultipleCoils() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let values = [true, false, true, true, false]
        _ = try await client.writeMultipleCoils(address: 0x0000, values: values, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0] == true)
        #expect(storage.coils[1] == false)
        #expect(storage.coils[2] == true)
        #expect(storage.coils[3] == true)
        #expect(storage.coils[4] == false)

        await client.close()
    }

    // MARK: - Error Injection Tests

    @Test("Timeout error")
    func timeoutError() async throws {
        let mock = MockUDPTransport()
        await mock.injectTimeout(true)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ModbusClientError.timeout) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    @Test("Modbus exception - illegal function")
    func modbusExceptionIllegalFunction() async throws {
        let mock = MockUDPTransport()
        await mock.injectException(.illegalFunction)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ModbusClientError.modbusException(.illegalFunction)) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    @Test("Modbus exception - illegal data address")
    func modbusExceptionIllegalAddress() async throws {
        let mock = MockUDPTransport()
        await mock.injectException(.illegalDataAddress)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }

        await client.close()
    }

    // MARK: - Parameter Validation Tests

    @Test("Invalid count zero throws")
    func invalidCountZero() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ModbusClientError.invalidParameter("count must be >= 1")) {
            try await client.readHoldingRegisters(address: 0, count: 0, unitId: 1)
        }

        await client.close()
    }

    @Test("Invalid count exceeds max throws")
    func invalidCountExceedsMax() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ModbusClientError.invalidParameter("count must be <= 125")) {
            try await client.readHoldingRegisters(address: 0, count: 126, unitId: 1)
        }

        await client.close()
    }

    // MARK: - Auto-bind Tests

    @Test("Auto-bind on first request")
    func autoBindOnFirstRequest() async throws {
        let mock = MockUDPTransport()
        await mock.setHoldingRegister(address: 0, value: 0x9999)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)

        // Don't explicitly connect
        #expect(!client.isConnected)

        // Should auto-bind
        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)

        #expect(client.isConnected)
        #expect(response.registers == [0x9999])

        await client.close()
    }

    // MARK: - Unit ID Tests

    @Test("Custom unit ID")
    func customUnitId() async throws {
        let mock = MockUDPTransport()
        await mock.setUnitId(5)
        await mock.setHoldingRegister(address: 0, value: 0x9999)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 5)

        #expect(response.registers == [0x9999])

        await client.close()
    }

    @Test("Wrong unit ID returns timeout")
    func wrongUnitIdTimeout() async throws {
        let mock = MockUDPTransport()
        await mock.setUnitId(1)

        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        // Request with unit ID 2, but mock responds to 1
        await #expect(throws: ModbusClientError.timeout) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 2)
        }

        await client.close()
    }

    // MARK: - Transaction Recording Tests

    @Test("Transactions are recorded")
    func transactionsRecorded() async throws {
        let mock = MockUDPTransport()
        let client = ModbusUDPClient(transport: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        _ = try await client.readHoldingRegisters(address: 10, count: 2, unitId: 1)

        let transactions = await mock.transactions
        #expect(transactions.count == 2)

        await client.close()
    }
}
