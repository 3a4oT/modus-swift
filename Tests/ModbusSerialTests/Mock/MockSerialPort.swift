// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore
@testable import ModbusSerial

// MARK: - MockSerialPort

/// Mock serial port for testing ModbusRTUClient and ModbusASCIIClient without real hardware.
///
/// Simulates a Modbus slave device with configurable responses.
/// Supports both RTU (CRC-16) and ASCII (LRC) framing modes.
///
/// ## Usage
///
/// ```swift
/// let mock = MockSerialPort()
/// mock.storage.holdingRegisters[0] = 0x1234
///
/// // Inject into client (via actor wrapper)
/// let response = try await client.readHoldingRegisters(address: 0, count: 1)
/// #expect(response.registers == [0x1234])
/// ```
actor MockSerialPort: SerialPort {
    // MARK: Lifecycle

    init() {
        path = "/dev/mock"
    }

    // MARK: Public

    /// Mock storage for registers/coils.
    var storage = MockStorage()

    /// Error injector for testing error scenarios.
    var errorInjector = MockErrorInjector()

    /// Recorded transactions for verification.
    private(set) var transactions: [MockTransaction] = []

    /// Device path (always "/dev/mock").
    let path: String

    /// Whether the port is "open".
    var isOpen: Bool {
        _isOpen
    }

    /// Unit ID to respond as (default: 1).
    var unitId: UInt8 = 1

    /// Protocol mode: RTU (CRC-16) or ASCII (LRC).
    var protocolMode: MockProtocolMode = .rtu

    /// Opens the mock port.
    func open(configuration: SerialConfiguration) async throws(SerialPortError) {
        if errorInjector.failOpen {
            throw .openFailed(path: path, errno: 13) // EACCES
        }
        _isOpen = true
        _configuration = configuration
    }

    /// Closes the mock port.
    func close() async {
        _isOpen = false
    }

    /// Reads response from mock device.
    func read(maxBytes _: Int, timeout _: Duration) async throws(SerialPortError) -> [UInt8] {
        guard _isOpen else {
            throw .notOpen
        }

        // Check countdown-based read failure first
        if errorInjector.failReadCount > 0 {
            errorInjector.failReadCount -= 1
            throw .readFailed(errno: 5) // EIO
        }

        if errorInjector.failRead {
            throw .readFailed(errno: 5) // EIO
        }

        if errorInjector.timeout {
            throw .readTimeout
        }

        guard let response = pendingResponse else {
            throw .readTimeout
        }

        pendingResponse = nil
        return response
    }

    /// Writes request to mock device, generates response.
    func write(_ bytes: [UInt8], timeout _: Duration) async throws(SerialPortError) {
        guard _isOpen else {
            throw .notOpen
        }

        if errorInjector.failWrite {
            throw .writeFailed(errno: 5) // EIO
        }

        // Record transaction
        let transaction = MockTransaction(request: bytes, timestamp: .now)
        transactions.append(transaction)

        // Generate response
        var response = try generateResponse(for: bytes)

        // Prepend request to response if local echo is enabled
        if errorInjector.localEcho {
            response = bytes + response
        }

        pendingResponse = response
    }

    /// Flushes buffers (no-op for mock).
    func flush() async throws(SerialPortError) {
        guard _isOpen else {
            throw .notOpen
        }
        pendingResponse = nil
    }

    /// Clears recorded transactions.
    func clearTransactions() {
        transactions.removeAll()
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

    /// Injects a bad CRC response.
    func injectBadCRC(_ enabled: Bool) {
        errorInjector.badCRC = enabled
    }

    /// Injects a Modbus exception response.
    func injectException(_ exception: ModbusException?) {
        errorInjector.modbusException = exception
    }

    /// Injects a bad LRC response (ASCII mode).
    func injectBadLRC(_ enabled: Bool) {
        errorInjector.badLRC = enabled
    }

    /// Injects a read failure error.
    func injectReadFailure(_ enabled: Bool) {
        errorInjector.failRead = enabled
    }

    /// Injects a read failure for a specific number of read calls.
    /// After `count` read failures, subsequent reads will succeed.
    func injectReadFailureCount(_ count: Int) {
        errorInjector.failReadCount = count
    }

    /// Injects an open failure error.
    func injectOpenFailure(_ enabled: Bool) {
        errorInjector.failOpen = enabled
    }

    /// Injects a write failure error.
    func injectWriteFailure(_ enabled: Bool) {
        errorInjector.failWrite = enabled
    }

    /// Enables local echo simulation (prepends request to response).
    func injectLocalEcho(_ enabled: Bool) {
        errorInjector.localEcho = enabled
    }

    /// Sets protocol mode (RTU or ASCII).
    func setProtocolMode(_ mode: MockProtocolMode) {
        protocolMode = mode
    }

    // MARK: Private

    private var _isOpen = false
    private var _configuration: SerialConfiguration?
    private var pendingResponse: [UInt8]?

    /// Generates response based on request and protocol mode.
    private func generateResponse(for request: [UInt8]) throws(SerialPortError) -> [UInt8] {
        switch protocolMode {
        case .rtu:
            try generateRTUResponse(for: request)
        case .ascii:
            try generateASCIIResponse(for: request)
        }
    }

    /// Generates RTU response based on request.
    private func generateRTUResponse(for request: [UInt8]) throws(SerialPortError) -> [UInt8] {
        // Validate minimum frame size
        guard request.count >= RTUFrameLimits.minRequestSize else {
            // Return nothing (timeout)
            throw .readTimeout
        }

        // Verify CRC
        let crcBytes = Array(request.suffix(2))
        let frameWithoutCRC = Array(request.dropLast(2))
        let calculatedCRC = calculateModbusCRC16(frameWithoutCRC.span)
        let receivedCRC = UInt16(crcBytes[0]) | (UInt16(crcBytes[1]) << 8)

        if errorInjector.badCRC {
            // Return response with bad CRC
            var response = generateRTUFrame(for: frameWithoutCRC)
            response[response.count - 1] ^= 0xFF // Corrupt CRC
            return response
        }

        guard calculatedCRC == receivedCRC else {
            // Bad request CRC — no response (timeout)
            throw .readTimeout
        }

        let requestUnitId = frameWithoutCRC[0]

        // Check unit ID
        guard requestUnitId == unitId || requestUnitId == 0 else {
            // Wrong unit ID — no response
            throw .readTimeout
        }

        // Broadcast (unit ID 0) — no response
        if requestUnitId == 0 {
            throw .readTimeout
        }

        return generateRTUFrame(for: frameWithoutCRC)
    }

    /// Generates ASCII response based on request.
    private func generateASCIIResponse(for request: [UInt8]) throws(SerialPortError) -> [UInt8] {
        // Validate ASCII frame format
        guard request.first == ASCIIFrameConstants.startMarker else {
            throw .readTimeout
        }

        // Decode ASCII frame to get unit ID and PDU
        let (requestUnitId, requestPDU): (UInt8, [UInt8])
        do {
            (requestUnitId, requestPDU) = try parseASCIIFrame(request)
        } catch {
            throw .readTimeout // Invalid frame
        }

        // Check unit ID
        guard requestUnitId == unitId || requestUnitId == 0 else {
            throw .readTimeout
        }

        // Broadcast (unit ID 0) — no response
        if requestUnitId == 0 {
            throw .readTimeout
        }

        // Generate PDU response
        let responsePDU = generatePDUResponseFromPDU(functionCode: requestPDU[0], pdu: requestPDU)

        // Build ASCII frame
        var asciiFrame: [UInt8]
        do {
            asciiFrame = try buildASCIIFrame(unitId: unitId, pdu: responsePDU)
        } catch {
            throw .readTimeout
        }

        if errorInjector.badLRC {
            // Corrupt LRC (it's at position -4 and -3 before CRLF)
            // LRC hex chars are at -4 (high) and -3 (low) positions
            // Replace with valid but incorrect hex: 'F' (0x46) -> '0' (0x30)
            let lrcPos = asciiFrame.count - 4
            if asciiFrame[lrcPos] == 0x46 { // 'F'
                asciiFrame[lrcPos] = 0x30 // '0'
            } else {
                asciiFrame[lrcPos] = 0x46 // 'F'
            }
        }

        return asciiFrame
    }

    /// Generates RTU frame with CRC for the given ADU (unit ID + PDU).
    private func generateRTUFrame(for frame: [UInt8]) -> [UInt8] {
        let functionCode = frame[1]

        // Check for injected exception
        if let exception = errorInjector.modbusException {
            return buildExceptionResponse(unitId: unitId, functionCode: functionCode, exception: exception)
        }

        let response: [UInt8] =
            switch functionCode {
            case ModbusFunctionCode.readHoldingRegisters:
                handleReadHoldingRegisters(frame)
            case ModbusFunctionCode.readInputRegisters:
                handleReadInputRegisters(frame)
            case ModbusFunctionCode.readCoils:
                handleReadCoils(frame)
            case ModbusFunctionCode.readDiscreteInputs:
                handleReadDiscreteInputs(frame)
            case ModbusFunctionCode.writeSingleRegister:
                handleWriteSingleRegister(frame)
            case ModbusFunctionCode.writeMultipleRegisters:
                handleWriteMultipleRegisters(frame)
            case ModbusFunctionCode.writeSingleCoil:
                handleWriteSingleCoil(frame)
            case ModbusFunctionCode.writeMultipleCoils:
                handleWriteMultipleCoils(frame)
            case ModbusFunctionCode.maskWriteRegister:
                handleMaskWriteRegister(frame)
            default:
                buildExceptionResponse(
                    unitId: unitId,
                    functionCode: functionCode,
                    exception: .illegalFunction,
                )
            }

        return response
    }

    /// Generates PDU-only response from PDU request (for ASCII mode).
    private func generatePDUResponseFromPDU(functionCode: UInt8, pdu: [UInt8]) -> [UInt8] {
        // Check for injected exception
        if let exception = errorInjector.modbusException {
            return [functionCode | 0x80, exception.rawValue]
        }

        // Build a fake ADU frame [unitId, functionCode, ...data] for handlers
        let frame = [unitId] + pdu

        let response: [UInt8] =
            switch functionCode {
            case ModbusFunctionCode.readHoldingRegisters:
                handleReadHoldingRegisters(frame)
            case ModbusFunctionCode.readInputRegisters:
                handleReadInputRegisters(frame)
            case ModbusFunctionCode.readCoils:
                handleReadCoils(frame)
            case ModbusFunctionCode.readDiscreteInputs:
                handleReadDiscreteInputs(frame)
            case ModbusFunctionCode.writeSingleRegister:
                handleWriteSingleRegister(frame)
            case ModbusFunctionCode.writeMultipleRegisters:
                handleWriteMultipleRegisters(frame)
            case ModbusFunctionCode.writeSingleCoil:
                handleWriteSingleCoil(frame)
            case ModbusFunctionCode.writeMultipleCoils:
                handleWriteMultipleCoils(frame)
            case ModbusFunctionCode.maskWriteRegister:
                handleMaskWriteRegister(frame)
            default:
                [functionCode | 0x80, ModbusException.illegalFunction.rawValue]
            }

        // Response is RTU frame with CRC - strip unitId and CRC for PDU-only
        // RTU response: [unitId, functionCode, data..., CRC_LO, CRC_HI]
        // We need: [functionCode, data...]
        if response.count >= 3 {
            return Array(response.dropFirst().dropLast(2))
        }
        return [functionCode | 0x80, ModbusException.slaveDeviceFailure.rawValue]
    }

    // MARK: - Request Handlers

    private func handleReadHoldingRegisters(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        var registers: [UInt16] = []
        for i in 0 ..< count {
            let addr = address + i
            registers.append(storage.holdingRegisters[Int(addr)] ?? 0)
        }

        return buildReadRegistersResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.readHoldingRegisters,
            registers: registers,
        )
    }

    private func handleReadInputRegisters(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        var registers: [UInt16] = []
        for i in 0 ..< count {
            let addr = address + i
            registers.append(storage.inputRegisters[Int(addr)] ?? 0)
        }

        return buildReadRegistersResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.readInputRegisters,
            registers: registers,
        )
    }

    private func handleReadCoils(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        var bits: [Bool] = []
        for i in 0 ..< count {
            let addr = address + i
            bits.append(storage.coils[Int(addr)] ?? false)
        }

        return buildReadBitsResponse(unitId: unitId, functionCode: ModbusFunctionCode.readCoils, bits: bits)
    }

    private func handleReadDiscreteInputs(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        var bits: [Bool] = []
        for i in 0 ..< count {
            let addr = address + i
            bits.append(storage.discreteInputs[Int(addr)] ?? false)
        }

        return buildReadBitsResponse(unitId: unitId, functionCode: ModbusFunctionCode.readDiscreteInputs, bits: bits)
    }

    private func handleWriteSingleRegister(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let value = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        storage.holdingRegisters[Int(address)] = value

        // Echo request (without CRC, then add new CRC)
        return buildWriteSingleResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.writeSingleRegister,
            address: address,
            value: value,
        )
    }

    private func handleWriteMultipleRegisters(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])
        // let byteCount = frame[6]

        for i in 0 ..< count {
            let offset = 7 + Int(i) * 2
            let value = (UInt16(frame[offset]) << 8) | UInt16(frame[offset + 1])
            storage.holdingRegisters[Int(address + i)] = value
        }

        return buildWriteMultipleResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.writeMultipleRegisters,
            address: address,
            count: count,
        )
    }

    private func handleWriteSingleCoil(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let value = (UInt16(frame[4]) << 8) | UInt16(frame[5])

        storage.coils[Int(address)] = (value == 0xFF00)

        return buildWriteSingleResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.writeSingleCoil,
            address: address,
            value: value,
        )
    }

    private func handleWriteMultipleCoils(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let count = (UInt16(frame[4]) << 8) | UInt16(frame[5])
        // let byteCount = frame[6]

        for i in 0 ..< count {
            let byteIndex = Int(i) / 8
            let bitIndex = Int(i) % 8
            let byte = frame[7 + byteIndex]
            let value = (byte >> bitIndex) & 1 == 1
            storage.coils[Int(address + i)] = value
        }

        return buildWriteMultipleResponse(
            unitId: unitId,
            functionCode: ModbusFunctionCode.writeMultipleCoils,
            address: address,
            count: count,
        )
    }

    private func handleMaskWriteRegister(_ frame: [UInt8]) -> [UInt8] {
        let address = (UInt16(frame[2]) << 8) | UInt16(frame[3])
        let andMask = (UInt16(frame[4]) << 8) | UInt16(frame[5])
        let orMask = (UInt16(frame[6]) << 8) | UInt16(frame[7])

        // Apply mask: Result = (Current AND And_Mask) OR (Or_Mask AND (NOT And_Mask))
        let current = storage.holdingRegisters[Int(address)] ?? 0
        let result = (current & andMask) | (orMask & ~andMask)
        storage.holdingRegisters[Int(address)] = result

        return buildMaskWriteResponse(
            unitId: unitId,
            address: address,
            andMask: andMask,
            orMask: orMask,
        )
    }

    // MARK: - Response Builders

    private func buildReadRegistersResponse(unitId: UInt8, functionCode: UInt8, registers: [UInt16]) -> [UInt8] {
        var response: [UInt8] = [unitId, functionCode, UInt8(registers.count * 2)]
        for reg in registers {
            response.append(UInt8(reg >> 8))
            response.append(UInt8(reg & 0xFF))
        }
        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }

    private func buildReadBitsResponse(unitId: UInt8, functionCode: UInt8, bits: [Bool]) -> [UInt8] {
        let byteCount = (bits.count + 7) / 8
        var response: [UInt8] = [unitId, functionCode, UInt8(byteCount)]

        for byteIndex in 0 ..< byteCount {
            var byte: UInt8 = 0
            for bitIndex in 0 ..< 8 {
                let index = byteIndex * 8 + bitIndex
                if index < bits.count, bits[index] {
                    byte |= (1 << bitIndex)
                }
            }
            response.append(byte)
        }

        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }

    private func buildWriteSingleResponse(
        unitId: UInt8,
        functionCode: UInt8,
        address: UInt16,
        value: UInt16,
    ) -> [UInt8] {
        var response: [UInt8] = [
            unitId, functionCode,
            UInt8(address >> 8), UInt8(address & 0xFF),
            UInt8(value >> 8), UInt8(value & 0xFF),
        ]
        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }

    private func buildWriteMultipleResponse(
        unitId: UInt8,
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
    ) -> [UInt8] {
        var response: [UInt8] = [
            unitId, functionCode,
            UInt8(address >> 8), UInt8(address & 0xFF),
            UInt8(count >> 8), UInt8(count & 0xFF),
        ]
        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }

    private func buildExceptionResponse(unitId: UInt8, functionCode: UInt8, exception: ModbusException) -> [UInt8] {
        var response: [UInt8] = [unitId, functionCode | 0x80, exception.rawValue]
        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }

    private func buildMaskWriteResponse(
        unitId: UInt8,
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
    ) -> [UInt8] {
        var response: [UInt8] = [
            unitId, ModbusFunctionCode.maskWriteRegister,
            UInt8(address >> 8), UInt8(address & 0xFF),
            UInt8(andMask >> 8), UInt8(andMask & 0xFF),
            UInt8(orMask >> 8), UInt8(orMask & 0xFF),
        ]
        let crc = calculateModbusCRC16(response.span)
        response.append(UInt8(crc & 0xFF))
        response.append(UInt8(crc >> 8))
        return response
    }
}

// MARK: - MockStorage

/// Storage for mock Modbus device.
struct MockStorage: Sendable {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Holding registers (FC 0x03, 0x06, 0x10).
    var holdingRegisters: [Int: UInt16] = [:]

    /// Input registers (FC 0x04).
    var inputRegisters: [Int: UInt16] = [:]

    /// Coils (FC 0x01, 0x05, 0x0F).
    var coils: [Int: Bool] = [:]

    /// Discrete inputs (FC 0x02).
    var discreteInputs: [Int: Bool] = [:]
}

// MARK: - MockProtocolMode

/// Protocol mode for mock serial port.
enum MockProtocolMode: Sendable {
    /// RTU mode with CRC-16 checksum.
    case rtu
    /// ASCII mode with LRC checksum.
    case ascii
}

// MARK: - MockErrorInjector

/// Error injector for testing error scenarios.
struct MockErrorInjector: Sendable {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Fail on open.
    var failOpen = false

    /// Fail on read.
    var failRead = false

    /// Number of read calls to fail before succeeding.
    /// When set to > 0, decrements on each read and disables failRead when reaching 0.
    var failReadCount = 0

    /// Fail on write.
    var failWrite = false

    /// Simulate timeout.
    var timeout = false

    /// Return bad CRC in response (RTU mode).
    var badCRC = false

    /// Return bad LRC in response (ASCII mode).
    var badLRC = false

    /// Return Modbus exception response.
    var modbusException: ModbusException?

    /// Simulate local echo (prepend request to response).
    var localEcho = false
}

// MARK: - MockTransaction

/// Recorded transaction for verification.
struct MockTransaction: Sendable {
    /// Request bytes sent.
    let request: [UInt8]

    /// Timestamp.
    let timestamp: ContinuousClock.Instant
}
