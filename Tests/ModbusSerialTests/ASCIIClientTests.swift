// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusSerial
import Testing

/// Tests for ModbusASCIIClient with MockSerialPort.
@Suite("ModbusASCIIClient")
struct ASCIIClientTests {
    // MARK: - Configuration

    let defaultConfig = ASCIIClientConfiguration(
        serialConfiguration: SerialConfiguration(
            port: "/dev/mock",
            baudRate: .b9600,
            parity: .even,
            stopBits: .one,
            dataBits: .seven,
            timeout: .milliseconds(100),
        ),
        retries: 0,
    )

    // MARK: - Connection Tests

    @Test("Connect opens serial port")
    func connectOpensPort() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)

        #expect(await !client.isConnected)
        try await client.connect()
        #expect(await client.isConnected)
    }

    @Test("Connect when already connected throws")
    func connectAlreadyConnected() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)

        try await client.connect()

        await #expect(throws: ASCIIClientError.alreadyConnected) {
            try await client.connect()
        }
    }

    @Test("Close disconnects port")
    func closeDisconnects() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)

        try await client.connect()
        #expect(await client.isConnected)

        await client.close()
        #expect(await !client.isConnected)
    }

    // MARK: - Read Holding Registers Tests

    @Test("Read single holding register")
    func readSingleHoldingRegister() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0x0000, value: 0x1234)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0x0000, count: 1, unitId: 1)

        #expect(response.registers == [0x1234])
        #expect(response.count == 1)
    }

    @Test("Read multiple holding registers")
    func readMultipleHoldingRegisters() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0, value: 0x0001)
        await mock.setHoldingRegister(address: 1, value: 0x0002)
        await mock.setHoldingRegister(address: 2, value: 0x0003)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 3, unitId: 1)

        #expect(response.registers == [0x0001, 0x0002, 0x0003])
        #expect(response.count == 3)
    }

    @Test("Read uninitialized registers returns zeros")
    func readUninitializedRegisters() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 100, count: 2, unitId: 1)

        #expect(response.registers == [0x0000, 0x0000])
    }

    // MARK: - Read Input Registers Tests

    @Test("Read input registers")
    func readInputRegisters() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setInputRegister(address: 10, value: 0xABCD)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readInputRegisters(address: 10, count: 1, unitId: 1)

        #expect(response.registers == [0xABCD])
    }

    // MARK: - Read Coils Tests

    @Test("Read coils")
    func readCoils() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setCoil(address: 0, value: true)
        await mock.setCoil(address: 1, value: false)
        await mock.setCoil(address: 2, value: true)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readCoils(address: 0, count: 3, unitId: 1)

        #expect(response.count == 3)
        #expect(response.bits == [true, false, true])
        #expect(response.value(at: 0) == true)
        #expect(response.value(at: 1) == false)
        #expect(response.value(at: 2) == true)
    }

    // MARK: - Read Discrete Inputs Tests

    @Test("Read discrete inputs")
    func readDiscreteInputs() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setDiscreteInput(address: 5, value: true)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readDiscreteInputs(address: 5, count: 1, unitId: 1)

        #expect(response.count == 1)
        #expect(response.bits == [true])
    }

    // MARK: - Write Single Register Tests

    @Test("Write single register")
    func writeSingleRegister() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.writeSingleRegister(address: 0x0010, value: 0x5678, unitId: 1)

        #expect(response.address == 0x0010)

        // Verify storage was updated
        let storage = await mock.storage
        #expect(storage.holdingRegisters[0x0010] == 0x5678)
    }

    // MARK: - Write Multiple Registers Tests

    @Test("Write multiple registers")
    func writeMultipleRegisters() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
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
    }

    // MARK: - Write Single Coil Tests

    @Test("Write single coil ON")
    func writeSingleCoilOn() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.writeSingleCoil(address: 0x0005, value: true, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0x0005] == true)
    }

    @Test("Write single coil OFF")
    func writeSingleCoilOff() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setCoil(address: 0x0005, value: true)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.writeSingleCoil(address: 0x0005, value: false, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0x0005] == false)
    }

    // MARK: - Write Multiple Coils Tests

    @Test("Write multiple coils")
    func writeMultipleCoils() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let values = [true, false, true, true, false]
        _ = try await client.writeMultipleCoils(address: 0x0000, values: values, unitId: 1)

        let storage = await mock.storage
        #expect(storage.coils[0] == true)
        #expect(storage.coils[1] == false)
        #expect(storage.coils[2] == true)
        #expect(storage.coils[3] == true)
        #expect(storage.coils[4] == false)
    }

    // MARK: - Error Injection Tests

    @Test("Timeout error")
    func timeoutError() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.injectTimeout(true)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.timeout) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    @Test("LRC error")
    func lrcError() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.injectBadLRC(true)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.lrcError) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    @Test("Modbus exception - illegal function")
    func modbusExceptionIllegalFunction() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.injectException(.illegalFunction)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.modbusException(.illegalFunction)) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    @Test("Modbus exception - illegal data address")
    func modbusExceptionIllegalAddress() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.injectException(.illegalDataAddress)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.modbusException(.illegalDataAddress)) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    // MARK: - Parameter Validation Tests

    @Test("Invalid count zero throws")
    func invalidCountZero() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.invalidParameter("count must be >= 1")) {
            try await client.readHoldingRegisters(address: 0, count: 0, unitId: 1)
        }
    }

    @Test("Invalid count exceeds max throws")
    func invalidCountExceedsMax() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        await #expect(throws: ASCIIClientError.invalidParameter("count must be <= 125")) {
            try await client.readHoldingRegisters(address: 0, count: 126, unitId: 1)
        }
    }

    @Test("Not connected throws")
    func notConnectedThrows() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)

        // Don't connect

        await #expect(throws: ASCIIClientError.notConnected) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        }
    }

    // MARK: - Unit ID Tests

    @Test("Custom unit ID")
    func customUnitId() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setUnitId(5)
        await mock.setHoldingRegister(address: 0, value: 0x9999)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 5)

        #expect(response.registers == [0x9999])
    }

    @Test("Wrong unit ID times out")
    func wrongUnitIdTimeout() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setUnitId(1)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        // Request with unit ID 2, but mock responds to 1
        await #expect(throws: ASCIIClientError.timeout) {
            try await client.readHoldingRegisters(address: 0, count: 1, unitId: 2)
        }
    }

    // MARK: - Transaction Recording Tests

    @Test("Transactions are recorded")
    func transactionsRecorded() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        _ = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
        _ = try await client.readHoldingRegisters(address: 10, count: 2, unitId: 1)

        let transactions = await mock.transactions
        #expect(transactions.count == 2)
    }

    // MARK: - Mask Write Register Test

    @Test("Mask write register")
    func maskWriteRegister() async throws {
        let mock = MockSerialPort()
        await mock.setProtocolMode(.ascii)
        await mock.setHoldingRegister(address: 0x0010, value: 0x00FF)

        let client = ModbusASCIIClient(port: mock, configuration: defaultConfig)
        try await client.connect()

        let response = try await client.maskWriteRegister(
            address: 0x0010,
            andMask: 0x00F0,
            orMask: 0x000F,
            unitId: 1,
        )

        #expect(response.address == 0x0010)
        #expect(response.andMask == 0x00F0)
        #expect(response.orMask == 0x000F)
    }
}
