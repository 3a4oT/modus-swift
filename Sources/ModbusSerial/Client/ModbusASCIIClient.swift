// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Logging
@_exported import ModbusCore
import ServiceLifecycle
import Synchronization

// MARK: - ModbusASCIIClient

/// Modbus ASCII client for serial RS-485/RS-232 communication.
///
/// Thread-safe async client using actor for request serialization.
///
/// ## Protocol Stack
///
/// ```
/// ModbusASCIIClient
///     ↓
/// ASCII Frame (':' + hex(Address + PDU + LRC) + CR LF)
///     ↓
/// SerialPortActor (POSIX termios)
/// ```
///
/// ## Differences from RTU
///
/// | Feature | RTU | ASCII |
/// |---------|-----|-------|
/// | Encoding | Binary | Hex ASCII |
/// | Checksum | CRC-16 | LRC |
/// | Frame start | 3.5 char silence | ':' (0x3A) |
/// | Frame end | 3.5 char silence | CR LF |
/// | Max inter-char | 1.5 char time | 1 second |
/// | Efficiency | Higher | Lower (2x data) |
///
/// ## Usage
///
/// ```swift
/// let client = ModbusASCIIClient(
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
/// Reference: Modbus Serial Line Protocol V1.02, Section 2.5
public final class ModbusASCIIClient: Sendable {
    // MARK: Lifecycle

    /// Creates a Modbus ASCII client.
    ///
    /// - Parameters:
    ///   - port: Serial port path (e.g., "/dev/ttyUSB0")
    ///   - baudRate: Baud rate (default: 9600)
    ///   - parity: Parity mode (default: even, per ASCII spec)
    ///   - stopBits: Stop bits (default: one)
    ///   - dataBits: Data bits (default: seven, per ASCII spec)
    ///   - timeout: Response timeout (default: 1 second)
    ///   - retries: Retry count on retryable errors (default: 3)
    ///   - errorRecovery: Error recovery mode (default: .disabled)
    ///   - logger: Optional logger
    public init(
        port: String,
        baudRate: BaudRate = .b9600,
        parity: Parity = .even,
        stopBits: StopBits = .one,
        dataBits: DataBits = .seven,
        timeout: Duration = .seconds(1),
        retries: Int = 3,
        errorRecovery: SerialErrorRecovery = .disabled,
        logger: Logger? = nil,
    ) {
        configuration = ASCIIClientConfiguration(
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
        serialPort = SerialPortActor(path: port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: errorRecovery))
    }

    /// Creates a Modbus ASCII client with configuration.
    public init(
        configuration: ASCIIClientConfiguration,
        logger: Logger? = nil,
    ) {
        self.configuration = configuration
        self.logger = logger
        serialPort = SerialPortActor(path: configuration.serialConfiguration.port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: configuration.errorRecovery))
    }

    /// Creates a Modbus ASCII client with a custom serial port.
    ///
    /// Primarily for testing with MockSerialPort.
    public init(
        port: any SerialPort,
        configuration: ASCIIClientConfiguration,
        logger: Logger? = nil,
    ) {
        self.configuration = configuration
        self.logger = logger
        serialPort = SerialPortActor(port: port)
        _reconnectDelay = Mutex(Self.initialReconnectDelay(for: configuration.errorRecovery))
    }

    // MARK: Public

    /// Client configuration.
    public let configuration: ASCIIClientConfiguration

    /// Whether connected.
    public var isConnected: Bool {
        get async {
            await serialPort.isOpen
        }
    }

    /// Opens the serial port.
    public func connect() async throws(ASCIIClientError) {
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
    ) async throws(ASCIIClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let pdu = buildReadHoldingRegistersPDU(address: address, count: count)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseReadRegistersPDU(responsePDU, expectedFunction: ModbusFunctionCode.readHoldingRegisters)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Reads input registers (FC 0x04).
    public func readInputRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count, maxCount: 125)

        let pdu = buildReadInputRegistersPDU(address: address, count: count)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseReadRegistersPDU(responsePDU, expectedFunction: ModbusFunctionCode.readInputRegisters)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Reads coils (FC 0x01).
    public func readCoils(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> ReadBitsResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let pdu = buildReadCoilsPDU(address: address, count: count)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseReadBitsPDU(
                responsePDU,
                expectedFunction: ModbusFunctionCode.readCoils,
                requestedCount: count,
            )
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Reads discrete inputs (FC 0x02).
    public func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> ReadBitsResponse {
        try validateReadParameters(count: count, maxCount: 2000)

        let pdu = buildReadDiscreteInputsPDU(address: address, count: count)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseReadBitsPDU(
                responsePDU,
                expectedFunction: ModbusFunctionCode.readDiscreteInputs,
                requestedCount: count,
            )
        } catch {
            throw mapPDUError(error)
        }
    }

    // MARK: - Write Operations

    /// Writes single register (FC 0x06).
    public func writeSingleRegister(
        address: UInt16,
        value: UInt16,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> WriteSingleRegisterResponse {
        let pdu = buildWriteSingleRegisterPDU(address: address, value: value)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseWriteSingleRegisterPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes multiple registers (FC 0x10).
    public func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> WriteMultipleRegistersResponse {
        guard values.count >= 1, values.count <= 123 else {
            throw .invalidParameter("values count must be 1-123")
        }

        let pdu = buildWriteMultipleRegistersPDU(address: address, values: values)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseWriteMultipleRegistersPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes single coil (FC 0x05).
    public func writeSingleCoil(
        address: UInt16,
        value: Bool,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> WriteSingleCoilResponse {
        let pdu = buildWriteSingleCoilPDU(address: address, value: value)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseWriteSingleCoilPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes multiple coils (FC 0x0F).
    public func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> WriteMultipleCoilsResponse {
        guard values.count >= 1, values.count <= 1968 else {
            throw .invalidParameter("values count must be 1-1968")
        }

        let pdu = buildWriteMultipleCoilsPDU(address: address, values: values)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseWriteMultipleCoilsPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Mask write register (FC 0x16).
    public func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8 = 1,
    ) async throws(ASCIIClientError) -> MaskWriteRegisterResponse {
        let pdu = buildMaskWriteRegisterPDU(address: address, andMask: andMask, orMask: orMask)
        let responsePDU = try await sendRequest(unitId: unitId, pdu: pdu)

        do {
            return try parseMaskWriteRegisterPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    // MARK: Internal

    let serialPort: SerialPortActor

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
    private func attemptReconnect() async throws(ASCIIClientError) {
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
    private func shouldAttemptReconnect(for error: ASCIIClientError) -> Bool {
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

    private func validateReadParameters(count: UInt16, maxCount: UInt16) throws(ASCIIClientError) {
        guard count >= 1 else {
            throw .invalidParameter("count must be >= 1")
        }
        guard count <= maxCount else {
            throw .invalidParameter("count must be <= \(maxCount)")
        }
    }

    // MARK: - Request Execution

    /// Sends ASCII request with retry and error recovery.
    ///
    /// Handles:
    /// - Retries on retryable errors (timeout, LRC, I/O)
    /// - Auto-reconnect on I/O errors (libmodbus MODBUS_ERROR_RECOVERY_LINK pattern)
    /// - Buffer flush between retries
    private func sendRequest(
        unitId: UInt8,
        pdu: [UInt8],
    ) async throws(ASCIIClientError) -> [UInt8] {
        var lastError: ASCIIClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performRequest(unitId: unitId, pdu: pdu)
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

    private func performRequest(
        unitId: UInt8,
        pdu: [UInt8],
    ) async throws(ASCIIClientError) -> [UInt8] {
        guard await serialPort.isOpen else {
            throw .notConnected
        }

        // Build ASCII frame
        let request: [UInt8]
        do {
            request = try buildASCIIFrame(unitId: unitId, pdu: pdu)
        } catch {
            throw .frameEncodingFailed("\(error)")
        }

        // Log TX
        logger?.trace("TX: \(request.hexString)")

        // Send and receive
        let response: [UInt8]
        do {
            response = try await serialPort.asciiTransaction(
                request: request,
                timeout: configuration.serialConfiguration.timeout,
                handleLocalEcho: configuration.handleLocalEcho,
            )
        } catch {
            if case .readTimeout = error {
                throw .timeout
            }
            throw .ioError("\(error)")
        }

        // Validate minimum size
        guard response.count >= ASCIIFrameConstants.minimumFrameSize else {
            throw .frameTooShort(expected: ASCIIFrameConstants.minimumFrameSize, got: response.count)
        }

        // Log RX
        logger?.trace("RX: \(response.hexString)")

        // Decode ASCII frame
        let (responseUnitId, responsePDU): (UInt8, [UInt8])
        do {
            (responseUnitId, responsePDU) = try parseASCIIFrame(response)
        } catch {
            switch error {
            case .invalidLRC:
                throw .lrcError
            case .frameTooShort:
                throw .frameTooShort(expected: ASCIIFrameConstants.minimumFrameSize, got: response.count)
            case .invalidHexCharacter:
                throw .invalidHexCharacter
            default:
                throw .frameDecodingFailed("\(error)")
            }
        }

        // Validate unit ID
        guard responseUnitId == unitId else {
            throw .unitIdMismatch(expected: unitId, got: responseUnitId)
        }

        return responsePDU
    }

    // MARK: - Error Mapping

    private func mapPDUError(_ error: PDUError) -> ASCIIClientError {
        switch error {
        case .pduTooShort:
            .frameTooShort(expected: 2, got: 0)
        case let .exceptionResponse(exception):
            .modbusException(exception)
        case let .unexpectedFunctionCode(expected, got):
            .functionCodeMismatch(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            .byteCountMismatch(expected: Int(expected), got: Int(got))
        case let .unknownException(code):
            .modbusException(ModbusException(rawValue: code) ?? .slaveDeviceFailure)
        case .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            .frameDecodingFailed("\(error)")
        }
    }
}

// MARK: Service

extension ModbusASCIIClient: Service {
    public func run() async throws {
        try await gracefulShutdown()
        await close()
    }
}
