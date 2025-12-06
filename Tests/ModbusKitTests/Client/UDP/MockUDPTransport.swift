// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore
@testable import ModbusKit
import Synchronization

// MARK: - MockUDPTransport

/// Mock UDP transport for testing ModbusUDPClient without real network I/O.
///
/// Simulates a Modbus TCP/UDP slave device with configurable responses.
/// Uses MBAP framing (same as ModbusTCP).
///
/// ## Usage
///
/// ```swift
/// let mock = MockUDPTransport()
/// await mock.setHoldingRegister(address: 0, value: 0x1234)
///
/// let client = ModbusUDPClient(transport: mock, configuration: config)
/// let response = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
/// #expect(response.registers == [0x1234])
/// ```
actor MockUDPTransport: UDPTransport {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Mock storage for registers/coils.
    var storage = MockUDPStorage()

    /// Error injector for testing error scenarios.
    var errorInjector = MockUDPErrorInjector()

    /// Recorded transactions for verification.
    private(set) var transactions: [MockUDPTransaction] = []

    /// Unit ID to respond as (default: 1).
    var unitId: UInt8 = 1

    /// Whether the transport is "bound".
    /// Uses Mutex for nonisolated access required by protocol.
    nonisolated var isBound: Bool {
        _isBoundMutex.withLock { $0 }
    }

    /// Binds the mock transport.
    func bind() async throws(UDPTransportError) {
        if errorInjector.failBind {
            throw .bindFailed("Mock bind failed")
        }
        if _isBoundMutex.withLock({ $0 }) {
            throw .alreadyBound
        }
        _isBoundMutex.withLock { $0 = true }
    }

    /// Closes the mock transport.
    func close() async {
        _isBoundMutex.withLock { $0 = false }
        pendingResponse = nil
    }

    /// Sends data and generates response.
    func send(_ data: [UInt8]) async throws(UDPTransportError) {
        if !_isBoundMutex.withLock({ $0 }) {
            try await bind()
        }

        if errorInjector.failSend {
            throw .sendFailed("Mock send failed")
        }

        // Record transaction
        let transaction = MockUDPTransaction(request: data, timestamp: .now)
        transactions.append(transaction)

        // Generate response
        pendingResponse = generateResponse(for: data)
    }

    /// Receives response with timeout.
    func receive(timeout _: Duration) async throws(UDPTransportError) -> [UInt8] {
        if !_isBoundMutex.withLock({ $0 }) {
            throw .notBound
        }

        if errorInjector.failReceive {
            throw .receiveFailed("Mock receive failed")
        }

        if errorInjector.timeout {
            throw .timeout
        }

        guard let response = pendingResponse else {
            throw .timeout
        }

        pendingResponse = nil
        return response
    }

    // MARK: - Convenience Setters

    /// Sets a holding register value.
    func setHoldingRegister(address: Int, value: UInt16) {
        storage.holdingRegisters[address] = value
    }

    /// Sets an input register value.
    func setInputRegister(address: Int, value: UInt16) {
        storage.inputRegisters[address] = value
    }

    /// Sets a coil value.
    func setCoil(address: Int, value: Bool) {
        storage.coils[address] = value
    }

    /// Sets a discrete input value.
    func setDiscreteInput(address: Int, value: Bool) {
        storage.discreteInputs[address] = value
    }

    /// Sets the unit ID to respond as.
    func setUnitId(_ id: UInt8) {
        unitId = id
    }

    /// Injects a timeout error.
    func injectTimeout(_ enabled: Bool) {
        errorInjector.timeout = enabled
    }

    /// Injects a Modbus exception response.
    func injectException(_ exception: ModbusException?) {
        errorInjector.modbusException = exception
    }

    /// Clears recorded transactions.
    func clearTransactions() {
        transactions.removeAll()
    }

    // MARK: Private

    private let _isBoundMutex = Mutex(false)
    private var pendingResponse: [UInt8]?

    /// Generates MBAP response based on request.
    private func generateResponse(for request: [UInt8]) -> [UInt8]? {
        // MBAP Header: Transaction ID (2) + Protocol ID (2) + Length (2) + Unit ID (1) + PDU
        guard request.count >= 8 else {
            return nil
        }

        let transactionId = (UInt16(request[0]) << 8) | UInt16(request[1])
        let protocolId = (UInt16(request[2]) << 8) | UInt16(request[3])
        let requestUnitId = request[6]
        let functionCode = request[7]

        // Validate protocol ID
        guard protocolId == 0 else {
            return nil
        }

        // Check unit ID
        guard requestUnitId == unitId || requestUnitId == 0 else {
            return nil
        }

        // Broadcast (unit ID 0) — no response
        if requestUnitId == 0 {
            return nil
        }

        // Generate PDU response
        let pdu = Array(request[7...])
        let responsePDU = generatePDUResponse(functionCode: functionCode, pdu: pdu)

        // Build MBAP response
        return buildMBAPResponse(transactionId: transactionId, unitId: unitId, pdu: responsePDU)
    }

    /// Generates PDU response.
    private func generatePDUResponse(functionCode: UInt8, pdu: [UInt8]) -> [UInt8] {
        // Check for injected exception
        if let exception = errorInjector.modbusException {
            return [functionCode | 0x80, exception.rawValue]
        }

        switch functionCode {
        case ModbusFunctionCode.readHoldingRegisters:
            return handleReadHoldingRegisters(pdu)
        case ModbusFunctionCode.readInputRegisters:
            return handleReadInputRegisters(pdu)
        case ModbusFunctionCode.readCoils:
            return handleReadCoils(pdu)
        case ModbusFunctionCode.readDiscreteInputs:
            return handleReadDiscreteInputs(pdu)
        case ModbusFunctionCode.writeSingleRegister:
            return handleWriteSingleRegister(pdu)
        case ModbusFunctionCode.writeMultipleRegisters:
            return handleWriteMultipleRegisters(pdu)
        case ModbusFunctionCode.writeSingleCoil:
            return handleWriteSingleCoil(pdu)
        case ModbusFunctionCode.writeMultipleCoils:
            return handleWriteMultipleCoils(pdu)
        default:
            return [functionCode | 0x80, ModbusException.illegalFunction.rawValue]
        }
    }

    // MARK: - Request Handlers

    private func handleReadHoldingRegisters(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x83, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])

        var data: [UInt8] = [ModbusFunctionCode.readHoldingRegisters, UInt8(count * 2)]
        for i in 0 ..< count {
            let value = storage.holdingRegisters[Int(address + i)] ?? 0
            data.append(UInt8(value >> 8))
            data.append(UInt8(value & 0xFF))
        }
        return data
    }

    private func handleReadInputRegisters(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x84, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])

        var data: [UInt8] = [ModbusFunctionCode.readInputRegisters, UInt8(count * 2)]
        for i in 0 ..< count {
            let value = storage.inputRegisters[Int(address + i)] ?? 0
            data.append(UInt8(value >> 8))
            data.append(UInt8(value & 0xFF))
        }
        return data
    }

    private func handleReadCoils(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x81, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])
        let byteCount = (count + 7) / 8

        var data: [UInt8] = [ModbusFunctionCode.readCoils, UInt8(byteCount)]
        for byteIndex in 0 ..< byteCount {
            var byte: UInt8 = 0
            for bitIndex in 0 ..< 8 {
                let coilIndex = Int(address) + Int(byteIndex) * 8 + bitIndex
                if coilIndex < Int(address + count), storage.coils[coilIndex] == true {
                    byte |= (1 << bitIndex)
                }
            }
            data.append(byte)
        }
        return data
    }

    private func handleReadDiscreteInputs(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x82, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])
        let byteCount = (count + 7) / 8

        var data: [UInt8] = [ModbusFunctionCode.readDiscreteInputs, UInt8(byteCount)]
        for byteIndex in 0 ..< byteCount {
            var byte: UInt8 = 0
            for bitIndex in 0 ..< 8 {
                let inputIndex = Int(address) + Int(byteIndex) * 8 + bitIndex
                if inputIndex < Int(address + count), storage.discreteInputs[inputIndex] == true {
                    byte |= (1 << bitIndex)
                }
            }
            data.append(byte)
        }
        return data
    }

    private func handleWriteSingleRegister(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x86, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let value = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])

        storage.holdingRegisters[Int(address)] = value

        // Echo request
        return Array(pdu[0 ..< 5])
    }

    private func handleWriteMultipleRegisters(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 6 else {
            return [0x90, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])
        // let byteCount = pdu[5]

        for i in 0 ..< count {
            let offset = 6 + Int(i) * 2
            guard offset + 1 < pdu.count else {
                break
            }
            let value = (UInt16(pdu[offset]) << 8) | UInt16(pdu[offset + 1])
            storage.holdingRegisters[Int(address + i)] = value
        }

        // Response: FC + address + count
        return [
            ModbusFunctionCode.writeMultipleRegisters,
            UInt8(address >> 8), UInt8(address & 0xFF),
            UInt8(count >> 8), UInt8(count & 0xFF),
        ]
    }

    private func handleWriteSingleCoil(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 5 else {
            return [0x85, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let value = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])

        storage.coils[Int(address)] = (value == 0xFF00)

        // Echo request
        return Array(pdu[0 ..< 5])
    }

    private func handleWriteMultipleCoils(_ pdu: [UInt8]) -> [UInt8] {
        guard pdu.count >= 6 else {
            return [0x8F, 0x03]
        }

        let address = (UInt16(pdu[1]) << 8) | UInt16(pdu[2])
        let count = (UInt16(pdu[3]) << 8) | UInt16(pdu[4])
        // let byteCount = pdu[5]

        for i in 0 ..< count {
            let byteIndex = Int(i) / 8
            let bitIndex = Int(i) % 8
            guard 6 + byteIndex < pdu.count else {
                break
            }
            let byte = pdu[6 + byteIndex]
            let value = (byte >> bitIndex) & 1 == 1
            storage.coils[Int(address) + Int(i)] = value
        }

        // Response: FC + address + count
        return [
            ModbusFunctionCode.writeMultipleCoils,
            UInt8(address >> 8), UInt8(address & 0xFF),
            UInt8(count >> 8), UInt8(count & 0xFF),
        ]
    }

    // MARK: - MBAP Builder

    private func buildMBAPResponse(transactionId: UInt16, unitId: UInt8, pdu: [UInt8]) -> [UInt8] {
        let length = UInt16(pdu.count + 1) // PDU + Unit ID
        return [
            UInt8(transactionId >> 8), UInt8(transactionId & 0xFF), // Transaction ID
            0x00, 0x00, // Protocol ID (Modbus)
            UInt8(length >> 8), UInt8(length & 0xFF), // Length
            unitId, // Unit ID
        ] + pdu
    }
}

// MARK: - MockUDPStorage

/// Storage for mock Modbus UDP device.
struct MockUDPStorage: Sendable {
    /// Holding registers (FC 0x03, 0x06, 0x10).
    var holdingRegisters: [Int: UInt16] = [:]

    /// Input registers (FC 0x04).
    var inputRegisters: [Int: UInt16] = [:]

    /// Coils (FC 0x01, 0x05, 0x0F).
    var coils: [Int: Bool] = [:]

    /// Discrete inputs (FC 0x02).
    var discreteInputs: [Int: Bool] = [:]
}

// MARK: - MockUDPErrorInjector

/// Error injector for testing error scenarios.
struct MockUDPErrorInjector: Sendable {
    /// Fail on bind.
    var failBind = false

    /// Fail on send.
    var failSend = false

    /// Fail on receive.
    var failReceive = false

    /// Simulate timeout.
    var timeout = false

    /// Return Modbus exception response.
    var modbusException: ModbusException?
}

// MARK: - MockUDPTransaction

/// Recorded transaction for verification.
struct MockUDPTransaction: Sendable {
    /// Request bytes sent.
    let request: [UInt8]

    /// Timestamp.
    let timestamp: ContinuousClock.Instant
}
