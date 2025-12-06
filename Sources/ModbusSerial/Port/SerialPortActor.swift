// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - SerialPortActor

/// Actor wrapper for serial port ensuring exclusive access.
///
/// All operations are serialized through the actor, guaranteeing
/// one request at a time (required by Modbus RTU protocol).
///
/// ## Why Actor?
///
/// - Native async/await support (Mutex.withLock doesn't support async)
/// - No NIO dependency — lightweight
/// - Swift runtime handles scheduling
/// - Mutual exclusion guaranteed (one operation at a time)
///
/// ## Note on Ordering
///
/// Actor does NOT guarantee FIFO ordering of concurrent callers.
/// For Modbus request-response this is acceptable — each caller
/// awaits its response before proceeding, so ordering is naturally
/// determined by the caller's code flow.
public actor SerialPortActor {
    // MARK: Lifecycle

    /// Creates a serial port actor with a POSIX serial port.
    ///
    /// - Parameter path: Device path (e.g., "/dev/ttyUSB0")
    public init(path: String) {
        port = POSIXSerialPort(path: path)
    }

    /// Creates a serial port actor with a custom port implementation.
    ///
    /// Primarily for testing with MockSerialPort.
    ///
    /// - Parameter port: Serial port implementation
    public init(port: any SerialPort) {
        self.port = port
    }

    // MARK: Public

    /// Whether the port is open.
    public var isOpen: Bool {
        get async {
            await port.isOpen
        }
    }

    /// Opens the serial port.
    public func open(configuration: SerialConfiguration) async throws(SerialPortError) {
        try await port.open(configuration: configuration)
    }

    /// Closes the serial port.
    public func close() async {
        await port.close()
    }

    /// Performs a complete Modbus RTU transaction atomically.
    ///
    /// 1. Flush buffers
    /// 2. Write request
    /// 3. Wait T3.5 inter-frame delay
    /// 4. Read response until silence
    /// 5. Strip local echo if enabled
    ///
    /// - Parameters:
    ///   - request: RTU frame to send (with CRC)
    ///   - timeout: Response timeout
    ///   - interFrameDelay: T3.5 delay
    ///   - handleLocalEcho: Strip echoed request bytes from response
    /// - Returns: Response bytes
    public func transaction(
        request: [UInt8],
        timeout: Duration,
        interFrameDelay: Duration,
        handleLocalEcho: Bool = false,
    ) async throws(SerialPortError) -> [UInt8] {
        // 1. Flush stale data
        try await port.flush()

        // 2. Send request
        try await port.write(request, timeout: timeout)

        // 3. Wait T3.5
        try? await Task.sleep(for: interFrameDelay)

        // 4. Read response
        var response = try await readResponse(timeout: timeout, interFrameDelay: interFrameDelay)

        // 5. Strip local echo if enabled
        if handleLocalEcho {
            response = stripLocalEcho(response: response, request: request)
        }

        return response
    }

    /// Flushes buffers.
    public func flush() async throws(SerialPortError) {
        try await port.flush()
    }

    /// Performs a complete Modbus ASCII transaction atomically.
    ///
    /// ASCII frames are delimited by ':' start and CR LF end markers,
    /// unlike RTU which uses timing gaps.
    ///
    /// 1. Flush buffers
    /// 2. Write request
    /// 3. Read until CR LF received
    /// 4. Strip local echo if enabled
    ///
    /// - Parameters:
    ///   - request: ASCII frame to send (with ':' and CR LF)
    ///   - timeout: Response timeout
    ///   - handleLocalEcho: Strip echoed request bytes from response
    /// - Returns: Response bytes (including ':' and CR LF)
    public func asciiTransaction(
        request: [UInt8],
        timeout: Duration,
        handleLocalEcho: Bool = false,
    ) async throws(SerialPortError) -> [UInt8] {
        // 1. Flush stale data
        try await port.flush()

        // 2. Send request
        try await port.write(request, timeout: timeout)

        // 3. Read until CR LF
        var response = try await readASCIIResponse(timeout: timeout)

        // 4. Strip local echo if enabled
        if handleLocalEcho {
            response = stripLocalEcho(response: response, request: request)
        }

        return response
    }

    // MARK: Private

    private let port: any SerialPort

    /// Reads until T3.5 silence.
    private func readResponse(
        timeout: Duration,
        interFrameDelay: Duration,
    ) async throws(SerialPortError) -> [UInt8] {
        var response: [UInt8] = []
        let maxSize = RTUFrameLimits.maxFrameSize

        // First chunk — full timeout
        do {
            let chunk = try await port.read(maxBytes: maxSize, timeout: timeout)
            response.append(contentsOf: chunk)
        } catch {
            if case .readTimeout = error {
                throw .readTimeout
            }
            throw error
        }

        // Continue until silence (T3.5 timeout)
        while response.count < maxSize {
            do {
                let chunk = try await port.read(
                    maxBytes: maxSize - response.count,
                    timeout: interFrameDelay,
                )
                response.append(contentsOf: chunk)
            } catch {
                if case .readTimeout = error {
                    break // Normal end of frame
                }
                throw error
            }
        }

        return response
    }

    /// Reads ASCII response until CR LF is received.
    ///
    /// Per Modbus ASCII spec, frames end with CR (0x0D) + LF (0x0A).
    /// Inter-character timeout is 1 second per spec.
    private func readASCIIResponse(timeout: Duration) async throws(SerialPortError) -> [UInt8] {
        var response: [UInt8] = []
        let maxSize = ASCIIFrameLimits.maxFrameSize
        let interCharTimeout = Duration.seconds(1) // Per spec

        // Read until CR LF or timeout
        while response.count < maxSize {
            do {
                let readTimeout = response.isEmpty ? timeout : interCharTimeout
                let chunk = try await port.read(maxBytes: 1, timeout: readTimeout)

                guard !chunk.isEmpty else {
                    continue
                }

                response.append(contentsOf: chunk)

                // Check for CR LF terminator
                if response.count >= 2 {
                    let lastTwo = response.suffix(2)
                    if lastTwo.first == 0x0D, lastTwo.last == 0x0A {
                        break // Frame complete
                    }
                }
            } catch {
                if case .readTimeout = error {
                    if response.isEmpty {
                        throw .readTimeout // No response at all
                    }
                    break // Partial frame, return what we have
                }
                throw error
            }
        }

        return response
    }

    /// Strips local echo from response if present.
    ///
    /// RS-485 half-duplex adapters may echo transmitted bytes back.
    /// This function removes the echoed request from the start of the response.
    ///
    /// Based on pymodbus `handle_local_echo` implementation:
    /// - If response starts with request bytes, strip them
    /// - Otherwise return response unchanged
    ///
    /// - Parameters:
    ///   - response: Raw response bytes (may include echo)
    ///   - request: Original request bytes
    /// - Returns: Response with echo stripped
    private func stripLocalEcho(response: [UInt8], request: [UInt8]) -> [UInt8] {
        guard response.count >= request.count else {
            return response
        }

        // Check if response starts with request (echo)
        let prefix = response.prefix(request.count)
        if prefix.elementsEqual(request) {
            return Array(response.dropFirst(request.count))
        }

        return response
    }
}
