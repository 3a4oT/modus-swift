// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Logging
import Metrics

// MARK: - ModbusUDPClient

/// Modbus UDP client implementation.
///
/// Connectionless UDP transport for Modbus protocol.
/// Uses same MBAP framing as TCP — only transport layer differs.
///
/// **Key Differences from TCP:**
/// - No connect/disconnect state — UDP is connectionless
/// - Retries more important — UDP doesn't guarantee delivery
/// - Better for broadcast — natural multicast support
/// - No idle timeout — no persistent connection to manage
///
/// **Architecture:**
/// Uses `UDPTransport` protocol for transport abstraction, enabling:
/// - Production: `NIOUDPTransport` (SwiftNIO DatagramBootstrap)
/// - Testing: `MockUDPTransport` (deterministic, no I/O)
///
/// Usage:
/// ```swift
/// let client = ModbusUDPClient(host: "192.168.1.100", port: 502)
/// let response = try await client.readHoldingRegisters(address: 0, count: 10)
/// print(response.registers)
/// await client.close()
/// ```
///
/// Reference: pymodbus ModbusUdpClient
public final class ModbusUDPClient: ModbusClient, @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates a Modbus UDP client with NIO transport (production).
    ///
    /// - Parameters:
    ///   - host: Target hostname or IP address
    ///   - port: Target UDP port (default: 502)
    ///   - timeout: Response timeout (default: 3 seconds)
    ///   - retries: Number of retry attempts (default: 0)
    ///   - logger: Optional logger for debugging
    ///   - metrics: Optional metrics for observability
    public init(
        host: String,
        port: Int = MBAPConstants.defaultPort,
        timeout: Duration = .seconds(3),
        retries: Int = 0,
        logger: Logger? = nil,
        metrics: ModbusMetrics? = nil,
    ) {
        configuration = ModbusUDPClientConfiguration(
            host: host,
            port: port,
            timeout: timeout,
            retries: retries,
        )
        let transportConfig = UDPTransportConfiguration(host: host, port: port)
        transport = NIOUDPTransport(configuration: transportConfig)
        self.logger = logger
        self.metrics = metrics
        transactionIdGenerator = TransactionIdGenerator()
    }

    /// Creates a Modbus UDP client with configuration (production).
    ///
    /// - Parameters:
    ///   - configuration: UDP client configuration
    ///   - logger: Optional logger for debugging
    ///   - metrics: Optional metrics for observability
    public init(
        configuration: ModbusUDPClientConfiguration,
        logger: Logger? = nil,
        metrics: ModbusMetrics? = nil,
    ) {
        self.configuration = configuration
        let transportConfig = UDPTransportConfiguration(host: configuration.host, port: configuration.port)
        transport = NIOUDPTransport(configuration: transportConfig)
        self.logger = logger
        self.metrics = metrics
        transactionIdGenerator = TransactionIdGenerator()
    }

    /// Creates a Modbus UDP client with custom transport (testing).
    ///
    /// - Parameters:
    ///   - transport: UDP transport implementation
    ///   - configuration: UDP client configuration
    ///   - logger: Optional logger for debugging
    ///   - metrics: Optional metrics for observability
    public init(
        transport: UDPTransport,
        configuration: ModbusUDPClientConfiguration,
        logger: Logger? = nil,
        metrics: ModbusMetrics? = nil,
    ) {
        self.configuration = configuration
        self.transport = transport
        self.logger = logger
        self.metrics = metrics
        transactionIdGenerator = TransactionIdGenerator()
    }

    // MARK: Public

    /// Client configuration.
    public let configuration: ModbusUDPClientConfiguration

    /// Whether the client has a bound socket.
    ///
    /// Note: For UDP this just means we have a bound socket,
    /// not that we're "connected" to anything.
    public var isConnected: Bool {
        transport.isBound
    }

    /// Binds the UDP socket.
    ///
    /// For UDP, "connect" means binding a local socket.
    /// The client can then send to any address.
    ///
    /// - Throws: `ModbusClientError.connectionFailed` if bind fails
    public func connect() async throws(ModbusClientError) {
        if transport.isBound {
            throw .alreadyConnected
        }

        logger?.debug("Binding UDP socket for \(configuration.host):\(configuration.port)")

        do {
            try await transport.bind()
            metrics?.recordConnect()
            logger?.debug("UDP socket bound, ready to communicate with \(configuration.host):\(configuration.port)")
        } catch {
            throw .connectionFailed("UDP bind failed: \(error)")
        }
    }

    /// Closes the UDP socket.
    public func close() async {
        await transport.close()
        metrics?.recordDisconnect()
        logger?.debug("UDP socket closed")
    }

    // MARK: - Register Read Operations

    /// Reads holding registers (Function Code 0x03).
    public func readHoldingRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try validateReadParameters(count: count)
        return try await sendReadRequest(
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
        return try await sendReadRequest(
            functionCode: ModbusFunctionCode.readInputRegisters,
            address: address,
            count: count,
            unitId: unitId,
        )
    }

    // MARK: - Register Write Operations

    /// Writes a single register (Function Code 0x06).
    public func writeSingleRegister(
        address: UInt16,
        value: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse {
        let pdu = buildWriteSingleRegisterPDU(address: address, value: value)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseWriteSingleRegisterPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes multiple registers (Function Code 0x10).
    public func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        try validateWriteParameters(values: values)
        let pdu = buildWriteMultipleRegistersPDU(address: address, values: values)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseWriteMultipleRegistersPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    // MARK: - Coil Operations

    /// Reads coils (Function Code 0x01).
    public func readCoils(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try validateReadCoilsParameters(count: count)
        let pdu = buildReadCoilsPDU(address: address, count: count)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadBitsPDU(
                responseBytes,
                expectedFunction: ModbusFunctionCode.readCoils,
                requestedCount: count,
            )
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Reads discrete inputs (Function Code 0x02).
    public func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try validateReadCoilsParameters(count: count)
        let pdu = buildReadDiscreteInputsPDU(address: address, count: count)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadBitsPDU(
                responseBytes,
                expectedFunction: ModbusFunctionCode.readDiscreteInputs,
                requestedCount: count,
            )
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes a single coil (Function Code 0x05).
    public func writeSingleCoil(
        address: UInt16,
        value: Bool,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse {
        let pdu = buildWriteSingleCoilPDU(address: address, value: value)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseWriteSingleCoilPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Writes multiple coils (Function Code 0x0F).
    public func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        try validateWriteCoilsParameters(values: values)
        let pdu = buildWriteMultipleCoilsPDU(address: address, values: values)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseWriteMultipleCoilsPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    // MARK: - Advanced Operations

    /// Mask write register (Function Code 0x16).
    public func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse {
        let pdu = buildMaskWriteRegisterPDU(address: address, andMask: andMask, orMask: orMask)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseMaskWriteRegisterPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
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
        try validateWriteParameters(values: writeValues)

        let pdu = buildReadWriteMultipleRegistersPDU(
            readAddress: readAddress,
            readCount: readCount,
            writeAddress: writeAddress,
            writeValues: writeValues,
        )
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadWriteMultipleRegistersPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Read FIFO queue (Function Code 0x18).
    public func readFIFOQueue(
        address: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse {
        let pdu = buildReadFIFOQueuePDU(address: address)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadFIFOQueuePDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
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
        let pdu = buildReadFileRecordPDU(records: records)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadFileRecordPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
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
        let pdu = buildWriteFileRecordPDU(records: records)
        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseWriteFileRecordPDU(responseBytes)
        } catch {
            throw mapPDUError(error)
        }
    }

    // MARK: Internal

    /// Sends a request with retry logic.
    func sendRequest(
        pdu: [UInt8],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> [UInt8] {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performRequest(pdu: pdu, unitId: unitId)
            } catch {
                lastError = error
                guard error.isRetryable, attempt < maxAttempts else {
                    if !error.isRetryable {
                        throw error
                    }
                    break
                }
                if let fc = pdu.first {
                    metrics?.recordRetry(functionCode: fc)
                }
                logger?.debug("UDP request failed (attempt \(attempt)/\(maxAttempts)): \(error), retrying...")
            }
        }

        throw lastError ?? .timeout
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

    // MARK: Private

    private let transport: UDPTransport
    private let logger: Logger?
    private let metrics: ModbusMetrics?
    private let transactionIdGenerator: TransactionIdGenerator

    // MARK: - Internal Request Handling

    /// Sends a read registers request with retry logic.
    private func sendReadRequest(
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        let pdu: [UInt8] =
            if functionCode == ModbusFunctionCode.readHoldingRegisters {
                buildReadHoldingRegistersPDU(address: address, count: count)
            } else {
                buildReadInputRegistersPDU(address: address, count: count)
            }

        let responseBytes = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseReadRegistersPDU(responseBytes, expectedFunction: functionCode)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Performs a single request attempt.
    private func performRequest(
        pdu: [UInt8],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> [UInt8] {
        // Auto-bind if not bound
        if !transport.isBound {
            try await connect()
        }

        let transactionId = transactionIdGenerator.next()
        let adu = buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)

        logger?.trace("TX UDP: \(adu.hexString)")

        // Send request
        do {
            try await transport.send(adu)
        } catch {
            throw .ioError("UDP send failed: \(error)")
        }

        // Wait for response with timeout
        let startTime = ContinuousClock.now
        let responseBytes: [UInt8]
        do {
            responseBytes = try await transport.receive(timeout: configuration.timeout)
        } catch {
            switch error {
            case .timeout:
                throw ModbusClientError.timeout
            case .notBound:
                throw ModbusClientError.notConnected
            default:
                throw ModbusClientError.ioError("\(error)")
            }
        }

        let duration = ContinuousClock.now - startTime
        if let fc = pdu.first {
            metrics?.recordRequest(functionCode: fc, duration: duration)
        }

        logger?.trace("RX UDP: \(responseBytes.hexString)")

        // Parse MBAP and validate
        do {
            let (_, responsePDU) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return responsePDU
        } catch {
            throw mapMBAPError(error)
        }
    }

    /// Maps MBAP errors to client errors.
    private func mapMBAPError(_ error: MBAPError) -> ModbusClientError {
        switch error {
        case let .transactionIdMismatch(expected, got):
            .transactionIdMismatch(expected: expected, got: got)
        case let .unitIdMismatch(expected, got):
            .unitIdMismatch(expected: expected, got: got)
        default:
            .mbapError("\(error)")
        }
    }
}

// MARK: - Scoped Client Helper

/// Executes a closure with a bound Modbus UDP client, ensuring proper cleanup.
///
/// This function follows the scoped resource management pattern used by:
/// - grpc-swift 2: `withGRPCClient { ... }`
/// - swift-nio: `channel.executeThenClose { ... }`
///
/// The client socket is automatically closed when the closure exits (normally or via error).
///
/// ## When to Use
///
/// **Use `withModbusUDPClient` when:**
/// - CLI tools and scripts (one-off commands)
/// - Tests
/// - Operations where you explicitly want fresh socket each time
///
/// **Use `ModbusUDPClient` directly when:**
/// - Web frameworks (Vapor, Hummingbird) — shared client across HTTP requests
/// - Polling services — avoid socket rebind overhead on each poll
/// - Any scenario with repeated operations
/// - ServiceLifecycle integration needed
///
/// ## Performance Consideration
///
/// `withModbusUDPClient` binds a new UDP socket on each call.
/// While UDP has no handshake, socket bind still has kernel overhead.
/// Use a long-lived client for high-frequency or latency-sensitive scenarios.
///
/// ## Examples
///
/// **CLI tool (use this helper):**
/// ```swift
/// // Good: one-off command, socket overhead acceptable
/// let registers = try await withModbusUDPClient(host: "192.168.1.100") { client in
///     try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1).registers
/// }
/// ```
///
/// **Web framework (use client directly):**
/// ```swift
/// // Create shared client at app startup
/// let modbusClient = ModbusUDPClient(host: "192.168.1.100")
///
/// // Hummingbird
/// app.addServices(modbusClient)
///
/// // Request handler reuses the same socket
/// app.get("registers") { req in
///     try await modbusClient.readHoldingRegisters(address: 0, count: 10, unitId: 1)
/// }
/// ```
///
/// **Polling service (use client directly):**
/// ```swift
/// let client = ModbusUDPClient(host: "192.168.1.100")
/// try await client.connect()
///
/// // Reuses socket for all polls
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
///   - port: UDP port (default: 502)
///   - timeout: Response timeout (default: 3 seconds)
///   - retries: Number of retry attempts (default: 0)
///   - logger: Optional logger for debugging
///   - metrics: Optional metrics for observability
///   - body: Closure that receives the bound client
/// - Returns: The result of the closure
/// - Throws: Bind errors or errors from the closure
@inlinable
public func withModbusUDPClient<Result>(
    host: String,
    port: Int = MBAPConstants.defaultPort,
    timeout: Duration = .seconds(3),
    retries: Int = 0,
    logger: Logger? = nil,
    metrics: ModbusMetrics? = nil,
    _ body: (ModbusUDPClient) async throws -> Result,
) async throws -> Result {
    let client = ModbusUDPClient(
        host: host,
        port: port,
        timeout: timeout,
        retries: retries,
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

/// Executes a closure with a bound Modbus UDP client using configuration.
///
/// Same as ``withModbusUDPClient(host:port:timeout:retries:logger:metrics:_:)`` but uses
/// ``ModbusUDPClientConfiguration`` for all settings in one struct.
///
/// - Parameters:
///   - configuration: UDP client configuration
///   - logger: Optional logger for debugging
///   - metrics: Optional metrics for observability
///   - body: Closure that receives the bound client
/// - Returns: The result of the closure
/// - Throws: Bind errors or errors from the closure
@inlinable
public func withModbusUDPClient<Result>(
    configuration: ModbusUDPClientConfiguration,
    logger: Logger? = nil,
    metrics: ModbusMetrics? = nil,
    _ body: (ModbusUDPClient) async throws -> Result,
) async throws -> Result {
    let client = ModbusUDPClient(
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
