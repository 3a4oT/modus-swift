// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Logging
import Metrics
import NIOCore
import NIOPosix
import ServiceLifecycle
import Synchronization

// MARK: - ModbusTCPClient

/// Modbus TCP client implementation using SwiftNIO.
///
/// Thread-safe async client for Modbus TCP communication.
/// Uses `Mutex` for request serialization matching goburrow/pymodbus behavior.
///
/// **Concurrency Model:**
/// Requests are serialized using `Synchronization.Mutex`. This matches:
/// - pymodbus: uses `asyncio.Lock()` to prevent concurrent transactions
/// - goburrow/modbus: uses `sync.Mutex` for serialized access
///
/// Reason: Many Modbus devices don't support concurrent requests and will break
/// if a second request is sent before receiving the first response.
/// See: https://github.com/pymodbus-dev/pymodbus/issues/475
///
/// **Idle Timeout:**
/// Connection automatically closes after `idleTimeout` of inactivity.
/// Reference: goburrow/modbus uses `time.AfterFunc` with 60s default.
///
/// ## Usage
///
/// **Simple (one-off operations):**
/// ```swift
/// let client = ModbusTCPClient(host: "192.168.1.100", port: 502)
/// try await client.connect()
///
/// let response = try await client.readHoldingRegisters(address: 0, count: 10)
/// print(response.registers)
///
/// await client.close()
/// ```
///
/// **Long-running service:**
/// ```swift
/// let client = ModbusTCPClient(host: "192.168.1.100")
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
/// Reference: pymodbus AsyncModbusTcpClient, goburrow/modbus TCPClient
public final class ModbusTCPClient: ModbusClient, MBAPTransport, @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates a Modbus TCP client.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address
    ///   - port: TCP port (default: 502)
    ///   - timeout: Connection and read timeout (default: 3 seconds)
    ///   - logger: Optional logger for debugging (default: nil, no logging)
    ///   - metrics: Optional metrics for observability (default: nil, no metrics)
    public init(
        host: String,
        port: Int = MBAPConstants.defaultPort,
        timeout: Duration = .seconds(3),
        logger: Logger? = nil,
        metrics: ModbusMetrics? = nil,
    ) {
        configuration = ModbusClientConfiguration(
            host: host,
            port: port,
            timeout: timeout,
        )
        self.logger = logger
        self.metrics = metrics
        transactionIdGenerator = TransactionIdGenerator()
        _state = Mutex(.disconnected)
        _channel = Mutex(nil)
        _lastActivity = Mutex(ContinuousClock.now)
        _idleTimerTask = Mutex(nil)
        _currentReconnectDelay = Mutex(nil)
        eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    }

    /// Creates a Modbus TCP client with configuration.
    ///
    /// - Parameters:
    ///   - configuration: Client configuration
    ///   - logger: Optional logger for debugging (default: nil, no logging)
    ///   - metrics: Optional metrics for observability (default: nil, no metrics)
    public init(configuration: ModbusClientConfiguration, logger: Logger? = nil, metrics: ModbusMetrics? = nil) {
        self.configuration = configuration
        self.logger = logger
        self.metrics = metrics
        transactionIdGenerator = TransactionIdGenerator()
        _state = Mutex(.disconnected)
        _channel = Mutex(nil)
        _lastActivity = Mutex(ContinuousClock.now)
        _idleTimerTask = Mutex(nil)
        _currentReconnectDelay = Mutex(nil)
        eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    }

    deinit {
        _idleTimerTask.withLock { $0?.cancel() }
    }

    // MARK: Public

    /// Client configuration.
    public let configuration: ModbusClientConfiguration

    /// Whether the client is currently connected.
    public var isConnected: Bool {
        _state.withLock { $0 == .connected }
    }

    /// Current connection state.
    public var connectionState: ConnectionState {
        _state.withLock { $0 }
    }

    /// Connects to the Modbus device.
    ///
    /// - Throws: `ModbusClientError.connectionFailed` if connection fails
    /// - Throws: `ModbusClientError.timeout` if connection times out
    /// - Throws: `ModbusClientError.alreadyConnected` if already connected
    public func connect() async throws(ModbusClientError) {
        // Check current state and wait for disconnecting to complete if needed
        var currentState = _state.withLock { $0 }

        // If already connected, nothing to do
        if currentState == .connected {
            return
        }

        // If disconnecting, wait for it to complete (with timeout)
        if currentState == .disconnecting {
            let startTime = ContinuousClock.now
            while currentState == .disconnecting {
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    throw .connectionFailed("Connection cancelled while waiting for close")
                }
                let elapsed = ContinuousClock.now - startTime
                if elapsed > configuration.timeout {
                    throw .connectionFailed("Timeout waiting for previous connection to close")
                }
                currentState = _state.withLock { $0 }
            }
        }

        // Now state should be .disconnected
        guard currentState == .disconnected else {
            if currentState == .connected {
                return // Another thread connected while we waited
            }
            throw .connectionFailed("Invalid state: \(currentState)")
        }

        // Atomically transition to .connecting
        var transitioned = false
        _state.withLock { state in
            if state == .disconnected {
                state = .connecting
                transitioned = true
            }
        }

        guard transitioned else {
            // Another thread beat us to it
            let finalState = _state.withLock { $0 }
            if finalState == .connected {
                return
            }
            throw .connectionFailed("Failed to transition to connecting state: \(finalState)")
        }
        logger?.debug("Connecting to \(configuration.host):\(configuration.port)")

        do {
            // Convert Duration to NIO TimeAmount for bootstrap
            let timeoutNanos = configuration.timeout.components.seconds * 1_000_000_000 +
                configuration.timeout.components.attoseconds / 1_000_000_000
            // SO_KEEPALIVE: Recommended by Modbus TCP Implementation Guide
            // to detect crashed/rebooted peers. OS sends probes after idle period.
            // Reference: https://www.modbus.org/file/secure/messagingimplementationguide.pdf
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .channelOption(.socketOption(.so_reuseaddr), value: 1)
                .channelOption(.socketOption(.so_keepalive), value: 1)
                .connectTimeout(.nanoseconds(timeoutNanos))
                .channelInitializer { [pipelining = configuration.pipelining] channel in
                    // Select handler mode based on pipelining configuration
                    let handlerMode: ModbusResponseHandler.Mode = pipelining.isEnabled
                        ? .pipelining(maxInFlight: pipelining.maxInFlight)
                        : .serial

                    return channel.pipeline.addHandlers([
                        ByteToMessageHandler(ModbusFrameDecoder()),
                        ModbusResponseHandler(mode: handlerMode),
                    ])
                }

            let newChannel = try await bootstrap.connect(
                host: configuration.host,
                port: configuration.port,
            ).get()

            _channel.withLock { $0 = newChannel }
            _state.withLock { $0 = .connected }
            recordActivity()
            metrics?.recordConnect()
            logger?.debug("Connected to \(configuration.host):\(configuration.port)")

        } catch {
            _state.withLock { $0 = .disconnected }
            _channel.withLock { $0 = nil }

            if "\(error)".contains("timed out") || "\(error)".contains("timeout") {
                throw .timeout
            }
            throw .connectionFailed("\(error)")
        }
    }

    /// Closes the connection gracefully.
    public func close() async {
        let currentState = _state.withLock { $0 }
        guard currentState == .connected || currentState == .connecting else {
            return
        }

        _state.withLock { $0 = .disconnecting }
        cancelIdleTimer()
        logger?.debug("Disconnecting from \(configuration.host):\(configuration.port)")

        let ch = _channel.withLock { $0 }
        if let ch {
            try? await ch.close()
        }

        _channel.withLock { $0 = nil }
        _state.withLock { $0 = .disconnected }
        metrics?.recordDisconnect()
        logger?.debug("Disconnected from \(configuration.host):\(configuration.port)")
    }

    /// Reads holding registers (Function Code 0x03).
    public func readHoldingRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count)
        return try await sendReadRegistersRequest(
            functionCode: ModbusFunctionCode.readHoldingRegisters,
            address: address,
            count: count,
            unitId: unitId,
        )
    }

    /// Reads input registers (Function Code 0x04).
    public func readInputRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count)
        return try await sendReadRegistersRequest(
            functionCode: ModbusFunctionCode.readInputRegisters,
            address: address,
            count: count,
            unitId: unitId,
        )
    }

    /// Writes a single register (Function Code 0x06).
    public func writeSingleRegister(
        address: UInt16,
        value: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse {
        try await sendWriteSingleRegisterRequest(
            address: address,
            value: value,
            unitId: unitId,
        )
    }

    /// Writes multiple registers (Function Code 0x10).
    public func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        try validateWriteParameters(values: values)
        return try await sendWriteMultipleRegistersRequest(
            address: address,
            values: values,
            unitId: unitId,
        )
    }

    // MARK: - Coil Operations

    /// Reads coils (Function Code 0x01).
    public func readCoils(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try validateReadCoilsParameters(count: count)
        return try await sendReadBitsRequest(
            functionCode: ModbusFunctionCode.readCoils,
            address: address,
            count: count,
            unitId: unitId,
        )
    }

    /// Reads discrete inputs (Function Code 0x02).
    public func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try validateReadCoilsParameters(count: count)
        return try await sendReadBitsRequest(
            functionCode: ModbusFunctionCode.readDiscreteInputs,
            address: address,
            count: count,
            unitId: unitId,
        )
    }

    /// Writes a single coil (Function Code 0x05).
    public func writeSingleCoil(
        address: UInt16,
        value: Bool,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse {
        try await sendWriteSingleCoilRequest(
            address: address,
            value: value,
            unitId: unitId,
        )
    }

    /// Writes multiple coils (Function Code 0x0F).
    public func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        try validateWriteCoilsParameters(values: values)
        return try await sendWriteMultipleCoilsRequest(
            address: address,
            values: values,
            unitId: unitId,
        )
    }

    // MARK: - Advanced Operations (FC 0x16, 0x17, 0x18)

    /// Mask write register (Function Code 0x16).
    public func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse {
        try await sendMaskWriteRegisterRequest(
            address: address,
            andMask: andMask,
            orMask: orMask,
            unitId: unitId,
        )
    }

    /// Read/write multiple registers (Function Code 0x17).
    public func readWriteMultipleRegisters(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse {
        try validateReadParameters(count: readCount)
        try validateReadWriteWriteParameters(values: writeValues)
        return try await sendReadWriteMultipleRegistersRequest(
            readAddress: readAddress,
            readCount: readCount,
            writeAddress: writeAddress,
            writeValues: writeValues,
            unitId: unitId,
        )
    }

    /// Read FIFO queue (Function Code 0x18).
    public func readFIFOQueue(
        address: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse {
        try await sendReadFIFOQueueRequest(address: address, unitId: unitId)
    }

    // MARK: - File Record Operations (FC 0x14, 0x15)

    /// Read file record (Function Code 0x14).
    ///
    /// Reads records from extended memory files.
    ///
    /// - Parameters:
    ///   - records: File records specifying what to read (file number, record number, length)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response containing file record data
    /// - Throws: `ModbusClientError` on failure
    public func readFileRecord(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFileRecordResponse {
        try await sendReadFileRecordRequest(records: records, unitId: unitId)
    }

    /// Write file record (Function Code 0x15).
    ///
    /// Writes records to extended memory files.
    ///
    /// - Parameters:
    ///   - records: File records with data to write
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response echoing the written records
    /// - Throws: `ModbusClientError` on failure
    public func writeFileRecord(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteFileRecordResponse {
        try await sendWriteFileRecordRequest(records: records, unitId: unitId)
    }

    // MARK: Internal

    // MARK: Internal (ModbusTCPTransport)

    var logger: Logger?
    var metrics: ModbusMetrics?

    /// Current channel (internal for extensions).
    var channel: Channel? {
        _channel.withLock { $0 }
    }

    /// Generates next transaction ID (internal for extensions).
    func nextTransactionId() -> UInt16 {
        transactionIdGenerator.next()
    }

    /// Sends request and waits for response with proper pipelining support.
    ///
    /// **Serial mode:**
    /// 1. Write data to channel
    /// 2. Wait for next response
    ///
    /// **Pipelining mode:**
    /// 1. Register promise with Transaction ID (before write!)
    /// 2. Write data to channel
    /// 3. Wait for promise resolution
    ///
    /// The ordering in pipelining mode is critical: the promise must be registered
    /// before the write, because the response may arrive before the await point.
    func sendRequest(
        channel: Channel,
        data: ByteBuffer,
        transactionId: UInt16,
    ) async throws(ModbusClientError) -> [UInt8] {
        let handler: ModbusResponseHandler
        do {
            handler = try await channel.pipeline.handler(type: ModbusResponseHandler.self).get()
        } catch {
            throw .ioError("Handler not found: \(error)")
        }

        let eventLoop = channel.eventLoop

        // Choose timeout based on mode
        let timeout = configuration.pipelining.isEnabled
            ? configuration.pipelining.requestTimeout
            : configuration.timeout

        switch handler.mode {
        case .serial:
            // Serial mode: write first, then wait
            do {
                try await channel.writeAndFlush(data)
                recordActivity()
            } catch {
                throw .ioError("Write failed: \(error)")
            }

            return try await waitForSerialResponse(handler: handler, eventLoop: eventLoop, timeout: timeout)

        case .pipelining:
            // Pipelining mode: register BEFORE write, then write, then wait
            let promise = eventLoop.makePromise(of: [UInt8].self)

            // Step 1: Register promise (throws if limit reached or ID in use)
            do {
                try handler.registerRequest(transactionId: transactionId, promise: promise)
                metrics?.recordPipeliningPendingRequests(handler.pendingCount)
            } catch {
                if case .tooManyPendingRequests = error {
                    metrics?.recordPipeliningBackpressure()
                }
                throw error
            }

            // Step 2: Write (if fails, cancel the registered promise)
            do {
                try await channel.writeAndFlush(data)
                recordActivity()
            } catch {
                handler.cancelRequest(transactionId: transactionId)
                metrics?.recordPipeliningPendingRequests(handler.pendingCount)
                throw .ioError("Write failed: \(error)")
            }

            // Step 3: Wait for promise with timeout
            return try await waitForPipeliningResponse(
                promise: promise,
                transactionId: transactionId,
                handler: handler,
                timeout: timeout,
            )
        }
    }

    /// Maps MBAP errors to client errors.
    func mapMBAPError(_ error: MBAPError) -> ModbusClientError {
        switch error {
        case let .transactionIdMismatch(expected, got):
            .transactionIdMismatch(expected: expected, got: got)
        case let .unitIdMismatch(expected, got):
            .unitIdMismatch(expected: expected, got: got)
        default:
            .mbapError("\(error)")
        }
    }

    /// Maps PDU errors to client errors.
    func mapPDUError(_ error: PDUError) -> ModbusClientError {
        switch error {
        case let .exceptionResponse(exception):
            .modbusException(exception)
        default:
            .pduError("\(error)")
        }
    }

    // MARK: - Idle Timeout

    /// Records activity and resets idle timer.
    /// Reference: goburrow/modbus `lastActivity = time.Now()` in Send()
    func recordActivity() {
        _lastActivity.withLock { $0 = ContinuousClock.now }
        resetIdleTimer()
    }

    // MARK: - Auto-Reconnection

    /// Ensures connection is established based on reconnection strategy.
    /// Reference: goburrow/modbus `connect()` call in `Send()`
    func ensureConnected() async throws(ModbusClientError) {
        let currentState = _state.withLock { $0 }

        // Already connected - nothing to do
        if currentState == .connected {
            resetReconnectDelay()
            return
        }

        // Check strategy
        switch configuration.reconnectionStrategy {
        case .disabled:
            throw .notConnected

        case .immediate:
            // goburrow pattern: just connect
            metrics?.recordReconnection()
            try await connect()
            resetReconnectDelay()

        case let .exponentialBackoff(initialDelay, maxDelay):
            // pymodbus pattern: wait before reconnect
            let delay = _currentReconnectDelay.withLock { currentDelay -> Duration in
                let delayToUse = currentDelay ?? initialDelay
                // Double for next attempt, capped at max
                let nextDelay = min(delayToUse * 2, maxDelay)
                currentDelay = nextDelay
                return delayToUse
            }

            do {
                try await Task.sleep(for: delay)
            } catch {
                throw .connectionFailed("Reconnection cancelled")
            }
            metrics?.recordReconnection()
            try await connect()
            // Note: delay resets on successful request, not connect
        }
    }

    // MARK: Private

    private let eventLoopGroup: EventLoopGroup
    private let transactionIdGenerator: TransactionIdGenerator
    private let _state: Mutex<ConnectionState>
    private let _channel: Mutex<Channel?>
    private let _lastActivity: Mutex<ContinuousClock.Instant>
    private let _idleTimerTask: Mutex<Task<Void, Never>?>
    private let _currentReconnectDelay: Mutex<Duration?>

    // MARK: - Private Response Waiters

    /// Waits for next response in serial mode.
    private func waitForSerialResponse(
        handler: ModbusResponseHandler,
        eventLoop: EventLoop,
        timeout: Duration,
    ) async throws(ModbusClientError) -> [UInt8] {
        do {
            return try await withThrowingTaskGroup(of: [UInt8].self) { group in
                group.addTask {
                    try await handler.waitForResponse(on: eventLoop)
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ModbusClientError.timeout
                }

                guard let result = try await group.next() else {
                    throw ModbusClientError.timeout
                }
                group.cancelAll()
                return result
            }
        } catch let error as ModbusClientError {
            throw error
        } catch {
            throw .timeout
        }
    }

    /// Waits for specific Transaction ID response in pipelining mode.
    private func waitForPipeliningResponse(
        promise: EventLoopPromise<[UInt8]>,
        transactionId: UInt16,
        handler: ModbusResponseHandler,
        timeout: Duration,
    ) async throws(ModbusClientError) -> [UInt8] {
        do {
            return try await withThrowingTaskGroup(of: [UInt8].self) { group in
                group.addTask {
                    try await promise.futureResult.get()
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ModbusClientError.timeout
                }

                do {
                    guard let result = try await group.next() else {
                        handler.cancelRequest(transactionId: transactionId)
                        metrics?.recordPipeliningTimeout()
                        metrics?.recordPipeliningPendingRequests(handler.pendingCount)
                        throw ModbusClientError.timeout
                    }
                    group.cancelAll()
                    metrics?.recordPipeliningPendingRequests(handler.pendingCount)
                    return result
                } catch {
                    // Cancel pending request on timeout or error
                    handler.cancelRequest(transactionId: transactionId)
                    if case ModbusClientError.timeout = error {
                        metrics?.recordPipeliningTimeout()
                    }
                    metrics?.recordPipeliningPendingRequests(handler.pendingCount)
                    throw error
                }
            }
        } catch let error as ModbusClientError {
            throw error
        } catch {
            throw .timeout
        }
    }

    /// Resets the idle timer.
    /// Reference: goburrow/modbus `time.AfterFunc(mb.IdleTimeout, mb.closeIdle)`
    private func resetIdleTimer() {
        guard let idleTimeout = configuration.idleTimeout else {
            return
        }

        _idleTimerTask.withLock { task in
            task?.cancel()
            task = Task { [weak self] in
                try? await Task.sleep(for: idleTimeout)
                guard !Task.isCancelled else {
                    return
                }
                await self?.closeIfIdle()
            }
        }
    }

    /// Cancels the idle timer.
    private func cancelIdleTimer() {
        _idleTimerTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    /// Closes connection if idle timeout exceeded.
    /// Reference: goburrow/modbus `closeIdle()` function
    private func closeIfIdle() async {
        guard let idleTimeout = configuration.idleTimeout else {
            return
        }

        let lastActivity = _lastActivity.withLock { $0 }
        let elapsed = ContinuousClock.now - lastActivity

        if elapsed >= idleTimeout {
            await close()
        }
    }

    /// Resets reconnect delay after successful operation.
    private func resetReconnectDelay() {
        _currentReconnectDelay.withLock { $0 = nil }
    }
}

// MARK: - Scoped Client Helper

/// Executes a closure with a connected Modbus TCP client, ensuring proper cleanup.
///
/// This function follows the scoped resource management pattern used by:
/// - grpc-swift 2: `withGRPCClient { ... }`
/// - swift-nio: `channel.executeThenClose { ... }`
///
/// The client is automatically closed when the closure exits (normally or via error).
///
/// ## When to Use
///
/// **Use `withModbusTCPClient` when:**
/// - CLI tools and scripts (one-off commands)
/// - Tests
/// - Operations where you explicitly want fresh connection each time
///
/// **Use `ModbusTCPClient` directly when:**
/// - Web frameworks (Vapor, Hummingbird) — shared client across HTTP requests
/// - Polling services — avoid reconnect overhead on each poll
/// - Any scenario with repeated operations
/// - ServiceLifecycle integration needed
///
/// ## Performance Consideration
///
/// `withModbusTCPClient` creates a new TCP connection on each call.
/// For repeated operations, this adds ~1-10ms overhead per call (TCP handshake).
/// Use a long-lived client for high-frequency or latency-sensitive scenarios.
///
/// ## Examples
///
/// **CLI tool (use this helper):**
/// ```swift
/// // Good: one-off command, connection overhead acceptable
/// let registers = try await withModbusTCPClient(host: "192.168.1.100") { client in
///     try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1).registers
/// }
/// ```
///
/// **Web framework (use client directly):**
/// ```swift
/// // Create shared client at app startup
/// let modbusClient = ModbusTCPClient(host: "192.168.1.100")
///
/// // Hummingbird
/// app.addServices(modbusClient)
///
/// // Vapor
/// app.lifecycle.use(modbusClient)
///
/// // Request handler reuses the same connection
/// app.get("registers") { req in
///     try await modbusClient.readHoldingRegisters(address: 0, count: 10, unitId: 1)
/// }
/// ```
///
/// **Polling service (use client directly):**
/// ```swift
/// let client = ModbusTCPClient(host: "192.168.1.100")
/// try await client.connect()
///
/// // Reuses connection for all polls
/// while !Task.isCancelled {
///     let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
///     process(response)
///     try await Task.sleep(for: .seconds(5))
/// }
///
/// await client.close()
/// ```
///
/// - Parameters:
///   - host: Hostname or IP address
///   - port: TCP port (default: 502)
///   - timeout: Connection and read timeout (default: 3 seconds)
///   - logger: Optional logger for debugging
///   - metrics: Optional metrics for observability
///   - body: Closure that receives the connected client
/// - Returns: The result of the closure
/// - Throws: Connection errors or errors from the closure
@inlinable
public func withModbusTCPClient<Result>(
    host: String,
    port: Int = MBAPConstants.defaultPort,
    timeout: Duration = .seconds(3),
    logger: Logger? = nil,
    metrics: ModbusMetrics? = nil,
    _ body: (ModbusTCPClient) async throws -> Result,
) async throws -> Result {
    let client = ModbusTCPClient(
        host: host,
        port: port,
        timeout: timeout,
        logger: logger,
        metrics: metrics,
    )
    try await client.connect()

    do {
        let result = try await body(client)
        await client.close()
        return result
    } catch {
        await client.close()
        throw error
    }
}

/// Executes a closure with a connected Modbus TCP client using configuration.
///
/// Same as ``withModbusTCPClient(host:port:timeout:logger:metrics:_:)`` but uses
/// ``ModbusClientConfiguration`` for advanced settings like reconnection and idle timeout.
///
/// - Parameters:
///   - configuration: Client configuration
///   - logger: Optional logger for debugging
///   - metrics: Optional metrics for observability
///   - body: Closure that receives the connected client
/// - Returns: The result of the closure
/// - Throws: Connection errors or errors from the closure
@inlinable
public func withModbusTCPClient<Result>(
    configuration: ModbusClientConfiguration,
    logger: Logger? = nil,
    metrics: ModbusMetrics? = nil,
    _ body: (ModbusTCPClient) async throws -> Result,
) async throws -> Result {
    let client = ModbusTCPClient(
        configuration: configuration,
        logger: logger,
        metrics: metrics,
    )
    try await client.connect()

    do {
        let result = try await body(client)
        await client.close()
        return result
    } catch {
        await client.close()
        throw error
    }
}
