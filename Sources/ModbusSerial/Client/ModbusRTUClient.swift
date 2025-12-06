// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Logging
import ModbusCore
import ServiceLifecycle
import Synchronization

// MARK: - ModbusRTUClient

/// Modbus RTU client for serial RS-485/RS-232 communication.
///
/// Thread-safe async client using actor for request serialization.
///
/// ## Protocol Stack
///
/// ```
/// ModbusRTUClient
///     ↓
/// RTU Frame (Address + PDU + CRC-16)
///     ↓
/// SerialPortActor (POSIX termios)
/// ```
///
/// ## Usage
///
/// **Simple (one-off operations):**
/// ```swift
/// let client = ModbusRTUClient(
///     port: "/dev/ttyUSB0",
///     baudRate: .b9600
/// )
///
/// try await client.connect()
///
/// let response = try await client.readHoldingRegisters(
///     address: 0,
///     count: 10,
///     unitId: 1
/// )
/// print(response.registers)
///
/// await client.close()
/// ```
///
/// **Long-running service:**
/// ```swift
/// let client = ModbusRTUClient(port: "/dev/ttyUSB0", baudRate: .b9600)
/// try await client.connect()
///
/// let group = ServiceGroup(
///     services: [client],
///     gracefulShutdownSignals: [.sigterm, .sigint],
///     logger: logger
/// )
/// try await group.run()
/// ```
///
/// Reference: pymodbus RTU client, goburrow/modbus serial
public final class ModbusRTUClient: Sendable {
    // MARK: Lifecycle

    /// Creates a Modbus RTU client.
    ///
    /// - Parameters:
    ///   - port: Serial port path (e.g., "/dev/ttyUSB0")
    ///   - baudRate: Baud rate (default: 9600)
    ///   - parity: Parity mode (default: none)
    ///   - stopBits: Stop bits (default: one)
    ///   - dataBits: Data bits (default: eight)
    ///   - timeout: Response timeout (default: 1 second)
    ///   - retries: Retry count on retryable errors (default: 3)
    ///   - errorRecovery: Error recovery mode (default: .disabled)
    ///   - logger: Optional logger
    public init(
        port: String,
        baudRate: BaudRate = .b9600,
        parity: Parity = .none,
        stopBits: StopBits = .one,
        dataBits: DataBits = .eight,
        timeout: Duration = .seconds(1),
        retries: Int = 3,
        errorRecovery: SerialErrorRecovery = .disabled,
        logger: Logger? = nil,
    ) {
        configuration = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: port,
                baudRate: baudRate,
                parity: parity,
                stopBits: stopBits,
                dataBits: dataBits,
                timeout: timeout,
            ),
            retries: retries,
            errorRecovery: errorRecovery,
        )
        self.logger = logger
        timing = RTUTiming(baudRate: baudRate)
        serialPort = SerialPortActor(path: port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: errorRecovery))
    }

    /// Creates a Modbus RTU client with configuration.
    public init(
        configuration: RTUClientConfiguration,
        logger: Logger? = nil,
    ) {
        self.configuration = configuration
        self.logger = logger
        timing = RTUTiming(baudRate: configuration.serialConfiguration.baudRate)
        serialPort = SerialPortActor(path: configuration.serialConfiguration.port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: configuration.errorRecovery))
    }

    /// Creates a Modbus RTU client with a custom serial port.
    ///
    /// Primarily for testing with MockSerialPort.
    ///
    /// - Parameters:
    ///   - port: Serial port implementation
    ///   - configuration: Client configuration
    ///   - logger: Optional logger
    public init(
        port: any SerialPort,
        configuration: RTUClientConfiguration,
        logger: Logger? = nil,
    ) {
        self.configuration = configuration
        self.logger = logger
        timing = RTUTiming(baudRate: configuration.serialConfiguration.baudRate)
        serialPort = SerialPortActor(port: port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: configuration.errorRecovery))
    }

    // MARK: Public

    /// Client configuration.
    public let configuration: RTUClientConfiguration

    /// RTU timing (T1.5, T3.5).
    public let timing: RTUTiming

    /// Whether connected.
    public var isConnected: Bool {
        get async {
            await serialPort.isOpen
        }
    }

    /// Opens the serial port.
    public func connect() async throws(RTUClientError) {
        guard await !serialPort.isOpen else {
            throw .alreadyConnected
        }

        logger?.debug("Opening serial port: \(configuration.serialConfiguration.port)")

        do {
            try await serialPort.open(configuration: configuration.serialConfiguration)
            logger?.debug("Serial port opened")
        } catch {
            throw .connectionFailed("\(error)")
        }
    }

    /// Closes the serial port.
    public func close() async {
        logger?.debug("Closing serial port")
        await serialPort.close()
        logger?.debug("Serial port closed")
    }

    // MARK: - Read Operations

    /// Reads holding registers (FC 0x03).
    public func readHoldingRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let request = buildRTUReadRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readHoldingRegisters,
            unitId: unitId,
        )
        return rtuResponse.toReadRegistersResponse()
    }

    /// Reads input registers (FC 0x04).
    public func readInputRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let request = buildRTUReadInputRegistersRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readInputRegisters,
            unitId: unitId,
        )
        return rtuResponse.toReadRegistersResponse()
    }

    /// Reads coils (FC 0x01).
    public func readCoils(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadBitsResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let request = buildRTUReadCoilsRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readCoils,
            unitId: unitId,
        )
        return rtuResponse.toReadBitsResponse(requestedCount: count)
    }

    /// Reads discrete inputs (FC 0x02).
    public func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadBitsResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let request = buildRTUReadDiscreteInputsRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readDiscreteInputs,
            unitId: unitId,
        )
        return rtuResponse.toReadBitsResponse(requestedCount: count)
    }

    // MARK: - Raw Read Operations (Debug/Advanced)

    /// Reads holding registers with raw response (FC 0x03).
    ///
    /// Returns raw RTU response for debugging, custom parsing, or
    /// non-standard device implementations. Exposes raw bytes without
    /// interpretation.
    ///
    /// For normal use, prefer `readHoldingRegisters()` which returns
    /// a typed `ReadRegistersResponse`.
    ///
    /// Reference: goburrow/modbus returns `[]byte` for raw access
    ///
    /// - Parameters:
    ///   - address: Starting register address (0-65535)
    ///   - count: Number of registers to read (1-125)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Raw RTU response with `.data: [UInt8]` access
    public func readHoldingRegistersRaw(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> RTUReadResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let request = buildRTUReadRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        return try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readHoldingRegisters,
            unitId: unitId,
        )
    }

    /// Reads input registers with raw response (FC 0x04).
    ///
    /// Returns raw RTU response for debugging or custom parsing.
    /// For normal use, prefer `readInputRegisters()`.
    ///
    /// - Parameters:
    ///   - address: Starting register address (0-65535)
    ///   - count: Number of registers to read (1-125)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Raw RTU response with `.data: [UInt8]` access
    public func readInputRegistersRaw(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> RTUReadResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let request = buildRTUReadInputRegistersRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        return try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readInputRegisters,
            unitId: unitId,
        )
    }

    /// Reads coils with raw response (FC 0x01).
    ///
    /// Returns raw RTU response for debugging or custom parsing.
    /// For normal use, prefer `readCoils()`.
    ///
    /// - Parameters:
    ///   - address: Starting coil address (0-65535)
    ///   - count: Number of coils to read (1-2000)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Raw RTU response with `.data: [UInt8]` access
    public func readCoilsRaw(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> RTUReadResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let request = buildRTUReadCoilsRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        return try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readCoils,
            unitId: unitId,
        )
    }

    /// Reads discrete inputs with raw response (FC 0x02).
    ///
    /// Returns raw RTU response for debugging or custom parsing.
    /// For normal use, prefer `readDiscreteInputs()`.
    ///
    /// - Parameters:
    ///   - address: Starting input address (0-65535)
    ///   - count: Number of inputs to read (1-2000)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Raw RTU response with `.data: [UInt8]` access
    public func readDiscreteInputsRaw(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> RTUReadResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let request = buildRTUReadDiscreteInputsRequest(
            address: address,
            count: count,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        return try parseReadResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.readDiscreteInputs,
            unitId: unitId,
        )
    }

    // MARK: - Write Operations

    /// Writes single register (FC 0x06).
    public func writeSingleRegister(
        address: UInt16,
        value: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> WriteSingleRegisterResponse {
        let request = buildRTUWriteSingleRegisterRequest(
            address: address,
            value: value,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseWriteResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.writeSingleRegister,
            unitId: unitId,
        )
        return rtuResponse.toWriteSingleRegisterResponse()
    }

    /// Writes multiple registers (FC 0x10).
    public func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> WriteMultipleRegistersResponse {
        guard values.count >= 1, values.count <= 123 else {
            throw .invalidParameter("values count must be 1-123")
        }

        let request = buildRTUWriteMultipleRegistersRequest(
            address: address,
            values: values,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseWriteResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.writeMultipleRegisters,
            unitId: unitId,
        )
        return rtuResponse.toWriteMultipleRegistersResponse()
    }

    /// Writes single coil (FC 0x05).
    public func writeSingleCoil(
        address: UInt16,
        value: Bool,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> WriteSingleCoilResponse {
        let request = buildRTUWriteSingleCoilRequest(
            address: address,
            value: value,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseWriteResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.writeSingleCoil,
            unitId: unitId,
        )
        return rtuResponse.toWriteSingleCoilResponse()
    }

    /// Writes multiple coils (FC 0x0F).
    public func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> WriteMultipleCoilsResponse {
        guard values.count >= 1, values.count <= 1968 else {
            throw .invalidParameter("values count must be 1-1968")
        }

        let request = buildRTUWriteMultipleCoilsRequest(
            address: address,
            values: values,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseWriteResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.writeMultipleCoils,
            unitId: unitId,
        )
        return rtuResponse.toWriteMultipleCoilsResponse()
    }

    /// Mask write register (FC 0x16).
    public func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> MaskWriteRegisterResponse {
        let request = buildRTUMaskWriteRegisterRequest(
            address: address,
            andMask: andMask,
            orMask: orMask,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        let rtuResponse = try parseWriteResponse(
            response: response,
            expectedFunction: ModbusFunctionCode.maskWriteRegister,
            unitId: unitId,
        )
        return rtuResponse.toMaskWriteRegisterResponse()
    }

    // MARK: Internal

    let serialPort: SerialPortActor

    func performRequest(request: [UInt8]) async throws(RTUClientError) -> [UInt8] {
        guard await serialPort.isOpen else {
            throw .notConnected
        }

        // Log TX (Foundation-free hex formatting)
        if let logger {
            let hex = request.map { formatHex($0) }.joined(separator: " ")
            logger.trace("TX: \(hex)")
        }

        // Execute transaction through actor
        let response: [UInt8]
        do {
            response = try await serialPort.transaction(
                request: request,
                timeout: configuration.serialConfiguration.timeout,
                interFrameDelay: timing.interFrame,
                handleLocalEcho: configuration.handleLocalEcho,
            )
        } catch {
            if case .readTimeout = error {
                throw .timeout
            }
            throw .ioError("\(error)")
        }

        // Validate minimum size
        guard response.count >= RTUFrameLimits.minResponseSize else {
            throw .frameTooShort(expected: RTUFrameLimits.minResponseSize, got: response.count)
        }

        // Log RX
        if let logger {
            let hex = response.map { formatHex($0) }.joined(separator: " ")
            logger.trace("RX: \(hex)")
        }

        return response
    }

    func mapRTUError(_ error: RTUError) -> RTUClientError {
        switch error {
        case .frameTooShort:
            .frameTooShort(expected: RTUFrameLimits.minResponseSize, got: 0)
        case .invalidCRC:
            .crcError
        case let .exceptionResponse(exception):
            .modbusException(exception)
        case let .unitIdMismatch(expected, got):
            .unitIdMismatch(expected: expected, got: got)
        case let .unexpectedFunctionCode(expected, got):
            .functionCodeMismatch(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            .byteCountMismatch(expected: Int(expected), got: Int(got))
        }
    }

    // MARK: - Request Execution

    /// Sends RTU request with retry and error recovery.
    ///
    /// Handles:
    /// - Retries on retryable errors (timeout, CRC, I/O)
    /// - Auto-reconnect on I/O errors (libmodbus MODBUS_ERROR_RECOVERY_LINK pattern)
    /// - Buffer flush between retries
    ///
    /// - Parameter request: Complete RTU frame (unitId + PDU + CRC)
    /// - Returns: Raw response bytes for parsing
    func sendRequest(request: [UInt8]) async throws(RTUClientError) -> [UInt8] {
        var lastError: RTUClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performRequest(request: request)
            } catch {
                lastError = error

                // Attempt reconnect on I/O errors (libmodbus MODBUS_ERROR_RECOVERY_LINK)
                if shouldAttemptReconnect(for: error) {
                    logger?.debug("I/O error, attempting reconnect: \(error)")
                    do {
                        try await attemptReconnect()
                        // Retry request after successful reconnect
                        continue
                    } catch {
                        // Reconnect failed, propagate original error
                        throw lastError!
                    }
                }

                guard error.isRetryable, attempt < maxAttempts else {
                    throw error
                }

                logger?.debug("Retry \(attempt)/\(maxAttempts - 1) after: \(error)")

                try? await serialPort.flush()
            }
        }

        throw lastError ?? .timeout
    }

    // MARK: Private

    private let logger: Logger?

    /// Current reconnect delay for exponential backoff.
    private let _reconnectDelay: Mutex<Duration>

    /// Whether error recovery is enabled.
    private var isErrorRecoveryEnabled: Bool {
        switch configuration.errorRecovery {
        case .disabled:
            false
        case .link,
             .exponentialBackoff:
            true
        }
    }

    /// Returns initial reconnect delay for the given error recovery mode.
    private static func initialReconnectDelay(for errorRecovery: SerialErrorRecovery) -> Duration {
        switch errorRecovery {
        case .disabled:
            .zero
        case let .link(delay):
            delay ?? .seconds(1)
        case let .exponentialBackoff(initialDelay, _):
            initialDelay
        }
    }

    /// Attempts to reconnect the serial port.
    ///
    /// Based on libmodbus MODBUS_ERROR_RECOVERY_LINK:
    /// 1. Close the port
    /// 2. Sleep for delay
    /// 3. Reopen the port
    ///
    /// For exponential backoff, delay doubles on each call until success.
    private func attemptReconnect() async throws(RTUClientError) {
        let delay: Duration
        let maxDelay: Duration?

        switch configuration.errorRecovery {
        case .disabled:
            // Should not be called with disabled recovery
            return

        case let .link(configuredDelay):
            delay = configuredDelay ?? configuration.serialConfiguration.timeout
            maxDelay = nil

        case let .exponentialBackoff(_, max):
            delay = _reconnectDelay.withLock { $0 }
            maxDelay = max
        }

        logger?.debug("Attempting reconnect after \(delay)")

        // 1. Close the port
        await serialPort.close()

        // 2. Sleep for delay
        try? await Task.sleep(for: delay)

        // 3. Attempt to reopen
        do {
            try await serialPort.open(configuration: configuration.serialConfiguration)
            logger?.debug("Reconnected successfully")

            // Reset delay on success (for exponential backoff)
            if case let .exponentialBackoff(initialDelay, _) = configuration.errorRecovery {
                _reconnectDelay.withLock { $0 = initialDelay }
            }
        } catch {
            // Double delay for next attempt (exponential backoff)
            if let maxDelay {
                _reconnectDelay.withLock { current in
                    current = min(current * 2, maxDelay)
                }
            }
            throw .connectionFailed("\(error)")
        }
    }

    /// Whether the error should trigger reconnection.
    ///
    /// Based on libmodbus: EBADF, ECONNRESET, EPIPE trigger reconnect.
    /// We map these to ioError.
    private func shouldAttemptReconnect(for error: RTUClientError) -> Bool {
        guard isErrorRecoveryEnabled else {
            return false
        }

        switch error {
        case .ioError:
            // I/O errors indicate port may be disconnected
            return true
        case .notConnected:
            // Port was closed, try to reopen
            return true
        default:
            return false
        }
    }

    // MARK: - Validation

    private func validateReadParameters(count: UInt16, maxCount: UInt16) throws(RTUClientError) {
        guard count >= 1 else {
            throw .invalidParameter("count must be >= 1")
        }
        guard count <= maxCount else {
            throw .invalidParameter("count must be <= \(maxCount)")
        }
    }

    // MARK: - Response Parsing

    private func parseReadResponse(
        response: [UInt8],
        expectedFunction: UInt8,
        unitId: UInt8,
    ) throws(RTUClientError) -> RTUReadResponse {
        do throws(RTUError) {
            return try parseRTUReadResponse(
                response,
                expectedUnitId: unitId,
                expectedFunction: expectedFunction,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    private func parseWriteResponse(
        response: [UInt8],
        expectedFunction: UInt8,
        unitId: UInt8,
    ) throws(RTUClientError) -> RTUWriteResponse {
        do throws(RTUError) {
            return try parseRTUWriteResponse(
                response,
                expectedUnitId: unitId,
                expectedFunction: expectedFunction,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    // MARK: - Helpers

    /// Formats byte as hex string (Foundation-free).
    @inline(__always)
    private func formatHex(_ byte: UInt8) -> String {
        let hex = String(byte, radix: 16, uppercase: true)
        return byte < 16 ? "0\(hex)" : hex
    }
}

// MARK: Service

extension ModbusRTUClient: Service {
    public func run() async throws {
        try await gracefulShutdown()
        await close()
    }
}
