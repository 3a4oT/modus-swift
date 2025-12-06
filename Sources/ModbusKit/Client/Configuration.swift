// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Synchronization

// MARK: - ModbusClientConfiguration

/// Configuration for Modbus TCP client.
///
/// Based on pymodbus AsyncModbusTcpClient and goburrow/modbus TCPClient parameters.
public struct ModbusClientConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates a client configuration.
    ///
    /// - Parameters:
    ///   - host: Hostname or IP address
    ///   - port: TCP port (default: 502)
    ///   - timeout: Connection and read timeout (default: 3 seconds)
    ///   - retries: Number of retry attempts (default: 3)
    ///   - idleTimeout: Idle timeout before auto-disconnect (default: 60 seconds, nil to disable)
    ///   - reconnectionStrategy: Strategy for auto-reconnection (default: .immediate)
    ///   - pipelining: Pipelining configuration (default: .disabled for compatibility)
    public init(
        host: String,
        port: Int = MBAPConstants.defaultPort,
        timeout: Duration = .seconds(3),
        retries: Int = 3,
        idleTimeout: Duration? = .seconds(60),
        reconnectionStrategy: ReconnectionStrategy = .immediate,
        pipelining: PipeliningConfiguration = .disabled,
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.retries = retries
        self.idleTimeout = idleTimeout
        self.reconnectionStrategy = reconnectionStrategy
        self.pipelining = pipelining
    }

    // MARK: Public

    /// Hostname or IP address
    public let host: String

    /// TCP port (default: 502)
    public let port: Int

    /// Connection and read timeout (default: 3 seconds)
    public let timeout: Duration

    /// Number of retry attempts (default: 3)
    public let retries: Int

    /// Idle timeout before auto-disconnect.
    ///
    /// Connection automatically closes after this duration of inactivity.
    /// Set to `nil` to disable idle timeout.
    /// Reference: goburrow/modbus uses 60 seconds default.
    public let idleTimeout: Duration?

    /// Strategy for automatic reconnection after connection loss.
    ///
    /// - `.immediate`: Reconnect instantly (goburrow pattern, default)
    /// - `.exponentialBackoff`: Delay doubles on failure (pymodbus pattern)
    /// - `.disabled`: No auto-reconnect, user must call connect()
    public let reconnectionStrategy: ReconnectionStrategy

    /// Pipelining configuration for concurrent requests.
    ///
    /// When enabled, multiple requests can be in-flight simultaneously,
    /// matched by Transaction ID. Default is `.disabled` for compatibility.
    ///
    /// See `PipeliningConfiguration` for details.
    public let pipelining: PipeliningConfiguration
}

// MARK: - PipeliningConfiguration

/// Configuration for Transaction ID pipelining (multiple in-flight requests).
///
/// Modbus TCP specification (Section 4.2) allows multiple outstanding requests
/// on a single connection, matched by Transaction ID. This enables significant
/// throughput improvements for batch operations.
///
/// ## Default Behavior
///
/// Pipelining is **disabled by default** for maximum device compatibility.
/// Many industrial devices only support one outstanding request at a time.
///
/// ## Usage
///
/// ```swift
/// // Serial mode (default) - one request at a time, recommended for most devices
/// let config = ModbusClientConfiguration(host: "192.168.1.100")
///
/// // Pipelining mode - up to 4 concurrent requests
/// let config = ModbusClientConfiguration(
///     host: "192.168.1.100",
///     pipelining: .enabled
/// )
///
/// // Custom pipelining limits
/// let config = ModbusClientConfiguration(
///     host: "192.168.1.100",
///     pipelining: PipeliningConfiguration(maxInFlight: 8)
/// )
/// ```
///
/// ## Concurrent Requests
///
/// With pipelining enabled, use Swift's structured concurrency:
///
/// ```swift
/// async let r1 = client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
/// async let r2 = client.readHoldingRegisters(address: 100, count: 10, unitId: 1)
/// let (result1, result2) = try await (r1, r2)
/// ```
///
/// ## Reference
///
/// - MODBUS Messaging on TCP/IP Implementation Guide V1.0b, Section 4.2
/// - pymodbus issue #475: Device compatibility concerns with pipelining
public struct PipeliningConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates a pipelining configuration.
    ///
    /// - Parameters:
    ///   - maxInFlight: Maximum concurrent in-flight requests (1-65535, default: 4)
    ///   - requestTimeout: Per-request timeout for pipelining mode (default: 3 seconds)
    public init(
        maxInFlight: Int = 4,
        requestTimeout: Duration = .seconds(3),
    ) {
        // Clamp to valid range: 1 (serial) to 65535 (max Transaction ID)
        self.maxInFlight = max(1, min(maxInFlight, 65535))
        self.requestTimeout = requestTimeout
    }

    // MARK: Public

    /// Disabled pipelining (serial mode). **This is the default.**
    ///
    /// Requests are serialized — one at a time. This is the most compatible
    /// mode for industrial Modbus devices and correct choice for 99% of use cases.
    /// Many PLCs and RTUs only support one outstanding request per connection.
    public static let disabled = PipeliningConfiguration(maxInFlight: 1)

    /// Enabled pipelining with 4 concurrent requests.
    ///
    /// Allows up to 4 in-flight requests simultaneously. This limit works with
    /// most Modbus TCP devices that support pipelining.
    ///
    /// **Warning:** Test thoroughly with your specific hardware before enabling
    /// in production. Many industrial devices do not support pipelining.
    ///
    /// Reference: https://control.com/thread/1026194308
    public static let enabled = PipeliningConfiguration(maxInFlight: 4)

    /// Maximum concurrent in-flight requests.
    ///
    /// When this limit is reached, new requests will fail with
    /// `ModbusClientError.tooManyPendingRequests`.
    ///
    /// - Value of 1 means serial mode (no pipelining)
    /// - Values 2-65535 enable pipelining with the specified limit
    public let maxInFlight: Int

    /// Per-request timeout for pipelining mode.
    ///
    /// Each in-flight request has its own timeout. If no response arrives
    /// within this duration, the request fails with `ModbusClientError.timeout`.
    ///
    /// In serial mode, the client's main `timeout` is used instead.
    public let requestTimeout: Duration

    /// Whether pipelining is enabled.
    ///
    /// Returns `true` if `maxInFlight > 1`.
    public var isEnabled: Bool { maxInFlight > 1 }
}

// MARK: - ReconnectionStrategy

/// Strategy for handling reconnection after connection loss.
///
/// Reference implementations:
/// - `.immediate`: goburrow/modbus pattern — reconnect in Send() if disconnected
/// - `.exponentialBackoff`: pymodbus pattern — delay doubles on each failure
public enum ReconnectionStrategy: Sendable, Equatable {
    /// No automatic reconnection. Client stays disconnected after connection loss.
    /// User must call `connect()` explicitly.
    case disabled

    /// Reconnect immediately when disconnected (goburrow/modbus pattern).
    /// Simple and reliable for most Modbus devices.
    /// **Default strategy.**
    case immediate

    /// Reconnect with exponential backoff (pymodbus pattern).
    /// Delay doubles after each failed attempt, up to maxDelay.
    /// Useful for rate-limited or overloaded servers.
    ///
    /// - Parameters:
    ///   - initialDelay: Starting delay between reconnection attempts (default: 100ms)
    ///   - maxDelay: Maximum delay cap (default: 30 seconds)
    case exponentialBackoff(initialDelay: Duration = .milliseconds(100), maxDelay: Duration = .seconds(30))
}

// MARK: - TransactionIdGenerator

/// Thread-safe transaction ID generator.
///
/// Generates sequential IDs from 1 to 65535, wrapping around.
/// ID 0 is skipped as some devices treat it specially.
public final class TransactionIdGenerator: Sendable {
    // MARK: Lifecycle

    public init() {
        _counter = Mutex(0)
    }

    // MARK: Public

    /// Generates the next transaction ID (1-65535).
    public func next() -> UInt16 {
        _counter.withLock { counter in
            counter = counter &+ 1
            if counter == 0 {
                counter = 1 // Skip 0
            }
            return counter
        }
    }

    /// Resets the counter (for testing).
    public func reset() {
        _counter.withLock { $0 = 0 }
    }

    // MARK: Private

    private let _counter: Mutex<UInt16>
}

// MARK: - ModbusUDPClientConfiguration

/// Configuration for Modbus UDP client.
///
/// UDP is connectionless — no connect/disconnect state machine.
/// Retries are more important for UDP due to lack of delivery guarantees.
///
/// Based on pymodbus ModbusUdpClient parameters.
public struct ModbusUDPClientConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates a UDP client configuration.
    ///
    /// - Parameters:
    ///   - host: Target hostname or IP address
    ///   - port: Target UDP port (default: 502)
    ///   - timeout: Response timeout (default: 3 seconds)
    ///   - retries: Number of retry attempts (default: 3, higher than TCP due to unreliable transport)
    public init(
        host: String,
        port: Int = MBAPConstants.defaultPort,
        timeout: Duration = .seconds(3),
        retries: Int = 3,
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.retries = retries
    }

    // MARK: Public

    /// Target hostname or IP address
    public let host: String

    /// Target UDP port (default: 502)
    public let port: Int

    /// Response timeout (default: 3 seconds)
    public let timeout: Duration

    /// Number of retry attempts (default: 3)
    ///
    /// Higher retry count recommended for UDP due to unreliable transport.
    public let retries: Int
}
