// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - SerialConfiguration

/// Configuration for serial port connection.
///
/// Based on pymodbus `serial.Serial` and goburrow/serial parameters.
///
/// ## Example
///
/// ```swift
/// let config = SerialConfiguration(
///     port: "/dev/ttyUSB0",
///     baudRate: .b9600,
///     parity: .none,
///     stopBits: .one,
///     dataBits: .eight
/// )
/// ```
public struct SerialConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates a serial configuration.
    ///
    /// - Parameters:
    ///   - port: Serial port path (e.g., "/dev/ttyUSB0", "/dev/tty.usbserial")
    ///   - baudRate: Baud rate (default: 9600)
    ///   - parity: Parity mode (default: .none)
    ///   - stopBits: Number of stop bits (default: .one)
    ///   - dataBits: Number of data bits (default: .eight)
    ///   - timeout: Read/write timeout (default: 1 second)
    public init(
        port: String,
        baudRate: BaudRate = .b9600,
        parity: Parity = .none,
        stopBits: StopBits = .one,
        dataBits: DataBits = .eight,
        timeout: Duration = .seconds(1),
    ) {
        self.port = port
        self.baudRate = baudRate
        self.parity = parity
        self.stopBits = stopBits
        self.dataBits = dataBits
        self.timeout = timeout
    }

    // MARK: Public

    /// Serial port path (e.g., "/dev/ttyUSB0", "/dev/tty.usbserial-1420")
    public let port: String

    /// Baud rate
    public let baudRate: BaudRate

    /// Parity mode
    public let parity: Parity

    /// Number of stop bits
    public let stopBits: StopBits

    /// Number of data bits
    public let dataBits: DataBits

    /// Read/write timeout
    public let timeout: Duration
}

// MARK: - BaudRate

/// Supported baud rates.
///
/// Standard POSIX baud rates from termios.h.
public enum BaudRate: Int, Sendable, Equatable, CaseIterable {
    case b300 = 300
    case b600 = 600
    case b1200 = 1200
    case b2400 = 2400
    case b4800 = 4800
    case b9600 = 9600
    case b19200 = 19200
    case b38400 = 38400
    case b57600 = 57600
    case b115200 = 115_200
    case b230400 = 230_400

    // MARK: Public

    /// Whether this baud rate uses fixed timing (> 19200).
    ///
    /// Per Modbus spec, baud rates above 19200 use fixed T1.5/T3.5 values.
    public var usesFixedTiming: Bool {
        rawValue > 19200
    }
}

// MARK: - Parity

/// Parity modes for serial communication.
public enum Parity: Sendable, Equatable {
    /// No parity bit
    case none
    /// Odd parity
    case odd
    /// Even parity
    case even
}

// MARK: - StopBits

/// Number of stop bits.
public enum StopBits: Sendable, Equatable {
    /// One stop bit
    case one
    /// Two stop bits
    case two
}

// MARK: - DataBits

/// Number of data bits per character.
public enum DataBits: Int, Sendable, Equatable {
    /// 7 data bits (used with some parity configurations)
    case seven = 7
    /// 8 data bits (most common)
    case eight = 8
}
