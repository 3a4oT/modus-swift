// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - SerialErrorRecovery

/// Error recovery mode for serial Modbus clients.
///
/// Based on libmodbus `modbus_set_error_recovery()` and pymodbus `reconnect_delay`.
///
/// Reference: libmodbus MODBUS_ERROR_RECOVERY_LINK
public enum SerialErrorRecovery: Sendable, Equatable {
    /// No automatic recovery. Client stays disconnected after I/O error.
    /// User must call `connect()` explicitly.
    /// **Default for backward compatibility.**
    case disabled

    /// Automatic reconnection on I/O errors (libmodbus pattern).
    ///
    /// When enabled, the client will attempt to reconnect after:
    /// - I/O errors (bad file descriptor, broken pipe)
    /// - Repeated timeouts (port may have been unplugged)
    ///
    /// The reconnection sequence:
    /// 1. Close the serial port
    /// 2. Wait for `delay` duration
    /// 3. Attempt to reopen the port
    ///
    /// If reconnection fails, the error is propagated to the caller.
    ///
    /// - Parameter delay: Delay before reconnection attempt (default: response timeout)
    case link(delay: Duration? = nil)

    /// Automatic reconnection with exponential backoff (pymodbus pattern).
    ///
    /// Similar to `.link`, but delay doubles after each failed reconnection
    /// attempt, up to `maxDelay`. Delay resets on successful reconnection.
    ///
    /// Useful for USB-to-serial adapters that may take time to re-enumerate.
    ///
    /// - Parameters:
    ///   - initialDelay: Starting delay between reconnection attempts (default: 100ms)
    ///   - maxDelay: Maximum delay cap (default: 30 seconds)
    case exponentialBackoff(initialDelay: Duration = .milliseconds(100), maxDelay: Duration = .seconds(30))
}

// MARK: - RTUClientConfiguration

/// Configuration for ModbusRTUClient.
///
/// Based on pymodbus and goburrow/modbus serial client parameters.
public struct RTUClientConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates an RTU client configuration.
    ///
    /// - Parameters:
    ///   - serialConfiguration: Serial port configuration
    ///   - retries: Number of retries on retryable errors (default: 3)
    ///   - errorRecovery: Error recovery mode (default: .disabled)
    ///   - handleLocalEcho: Strip echoed request bytes from response (default: false)
    public init(
        serialConfiguration: SerialConfiguration,
        retries: Int = 3,
        errorRecovery: SerialErrorRecovery = .disabled,
        handleLocalEcho: Bool = false,
    ) {
        self.serialConfiguration = serialConfiguration
        self.retries = retries
        self.errorRecovery = errorRecovery
        self.handleLocalEcho = handleLocalEcho
    }

    // MARK: Public

    /// Serial port configuration.
    public let serialConfiguration: SerialConfiguration

    /// Number of retries on retryable errors.
    ///
    /// Retryable errors: timeout, CRC error, I/O error.
    /// Non-retryable errors: Modbus exception, parameter validation.
    public let retries: Int

    /// Error recovery mode for automatic reconnection.
    ///
    /// When enabled, the client will attempt to reconnect after I/O errors
    /// such as a disconnected USB-to-serial adapter.
    ///
    /// Reference: libmodbus `MODBUS_ERROR_RECOVERY_LINK`
    public let errorRecovery: SerialErrorRecovery

    /// Handle local echo from RS-485 half-duplex adapters.
    ///
    /// Some USB-to-RS485 adapters echo transmitted bytes back on the receive line.
    /// When enabled, the client strips the echoed request bytes from the response.
    ///
    /// **When to enable:**
    /// - Two-wire RS-485 half-duplex connections
    /// - USB adapters without hardware echo suppression
    /// - If you see CRC errors and the response contains your request
    ///
    /// Reference: pymodbus `handle_local_echo`, minimalmodbus `handle_local_echo`
    public let handleLocalEcho: Bool
}

// MARK: - ASCIIClientConfiguration

/// Configuration for ModbusASCIIClient.
///
/// Based on Modbus Serial Line Protocol V1.02, Section 2.5.
public struct ASCIIClientConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates an ASCII client configuration.
    ///
    /// - Parameters:
    ///   - serialConfiguration: Serial port configuration
    ///   - retries: Number of retries on retryable errors (default: 3)
    ///   - errorRecovery: Error recovery mode (default: .disabled)
    ///   - handleLocalEcho: Strip echoed request bytes from response (default: false)
    public init(
        serialConfiguration: SerialConfiguration,
        retries: Int = 3,
        errorRecovery: SerialErrorRecovery = .disabled,
        handleLocalEcho: Bool = false,
    ) {
        self.serialConfiguration = serialConfiguration
        self.retries = retries
        self.errorRecovery = errorRecovery
        self.handleLocalEcho = handleLocalEcho
    }

    // MARK: Public

    /// Serial port configuration.
    public let serialConfiguration: SerialConfiguration

    /// Number of retries on retryable errors.
    ///
    /// Retryable errors: timeout, LRC error, I/O error.
    /// Non-retryable errors: Modbus exception, parameter validation.
    public let retries: Int

    /// Error recovery mode for automatic reconnection.
    ///
    /// When enabled, the client will attempt to reconnect after I/O errors
    /// such as a disconnected USB-to-serial adapter.
    ///
    /// Reference: libmodbus `MODBUS_ERROR_RECOVERY_LINK`
    public let errorRecovery: SerialErrorRecovery

    /// Handle local echo from RS-485 half-duplex adapters.
    ///
    /// Some USB-to-RS485 adapters echo transmitted bytes back on the receive line.
    /// When enabled, the client strips the echoed request bytes from the response.
    ///
    /// **When to enable:**
    /// - Two-wire RS-485 half-duplex connections
    /// - USB adapters without hardware echo suppression
    /// - If you see LRC errors and the response contains your request
    ///
    /// Reference: pymodbus `handle_local_echo`, minimalmodbus `handle_local_echo`
    public let handleLocalEcho: Bool
}
