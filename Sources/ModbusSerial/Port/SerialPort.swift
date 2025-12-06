// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - SerialPort

/// Protocol for serial port implementations.
///
/// This abstraction allows for:
/// - Platform-specific implementations (POSIX termios)
/// - Mock implementations for testing
///
/// ## Implementation Requirements
///
/// Implementations must:
/// 1. Support exclusive access mode (O_EXCL equivalent)
/// 2. Configure raw mode (no echo, no line processing)
/// 3. Disable flow control (required for Modbus RTU)
/// 4. Handle EINTR during read/write operations
public protocol SerialPort: Sendable {
    /// Whether the port is currently open.
    var isOpen: Bool { get async }

    /// Opens the serial port with the given configuration.
    ///
    /// - Parameter configuration: Serial port configuration
    /// - Throws: `SerialPortError` if open fails
    func open(configuration: SerialConfiguration) async throws(SerialPortError)

    /// Closes the serial port.
    ///
    /// Safe to call multiple times. No-op if already closed.
    func close() async

    /// Reads bytes from the serial port.
    ///
    /// Blocks until at least one byte is available or timeout expires.
    ///
    /// - Parameters:
    ///   - maxBytes: Maximum number of bytes to read
    ///   - timeout: Read timeout
    /// - Returns: Bytes read (1 to maxBytes)
    /// - Throws: `SerialPortError.readTimeout` if no data within timeout
    func read(maxBytes: Int, timeout: Duration) async throws(SerialPortError) -> [UInt8]

    /// Writes bytes to the serial port.
    ///
    /// Writes all bytes or throws on error.
    ///
    /// - Parameters:
    ///   - bytes: Bytes to write
    ///   - timeout: Write timeout
    /// - Throws: `SerialPortError` on failure
    func write(_ bytes: [UInt8], timeout: Duration) async throws(SerialPortError)

    /// Discards all data in input and output buffers.
    ///
    /// Call before sending a new request to clear stale data.
    func flush() async throws(SerialPortError)
}
