// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - SerialPortError

/// Errors that can occur during serial port operations.
public enum SerialPortError: Error, Sendable, Equatable {
    /// Failed to open the serial port
    case openFailed(path: String, errno: Int32)

    /// Failed to configure the serial port (tcsetattr failed)
    case configurationFailed(errno: Int32)

    /// Read operation failed
    case readFailed(errno: Int32)

    /// Write operation failed
    case writeFailed(errno: Int32)

    /// Read operation timed out
    case readTimeout

    /// Write operation timed out
    case writeTimeout

    /// Port is not open
    case notOpen

    /// Port is already open
    case alreadyOpen

    /// Unsupported baud rate for this platform
    case unsupportedBaudRate(BaudRate)

    /// Flush operation failed
    case flushFailed(errno: Int32)

    /// Invalid path (must be /dev/* and not contain "..")
    case invalidPath(path: String)
}
