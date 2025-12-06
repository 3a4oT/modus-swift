// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore

// MARK: - RTUClientError

/// Errors for ModbusRTUClient operations.
public enum RTUClientError: Error, Sendable, Equatable {
    /// Serial port is not open.
    case notConnected

    /// Serial port is already open.
    case alreadyConnected

    /// Failed to open serial port.
    case connectionFailed(String)

    /// Request timed out waiting for response.
    case timeout

    /// CRC-16 verification failed.
    case crcError

    /// Response frame too short.
    case frameTooShort(expected: Int, got: Int)

    /// Unit ID in response doesn't match request.
    case unitIdMismatch(expected: UInt8, got: UInt8)

    /// Function code in response doesn't match request.
    case functionCodeMismatch(expected: UInt8, got: UInt8)

    /// Byte count in response doesn't match expected.
    case byteCountMismatch(expected: Int, got: Int)

    /// Modbus exception response received.
    case modbusException(ModbusException)

    /// Invalid parameter value.
    case invalidParameter(String)

    /// I/O error during read/write.
    case ioError(String)

    // MARK: Public

    /// Whether this error is retryable.
    ///
    /// Retryable: timeout, CRC error, I/O error.
    /// Non-retryable: Modbus exception, validation errors.
    public var isRetryable: Bool {
        switch self {
        case .timeout,
             .crcError,
             .ioError,
             .frameTooShort:
            true
        case .notConnected,
             .alreadyConnected,
             .connectionFailed,
             .unitIdMismatch,
             .functionCodeMismatch,
             .byteCountMismatch,
             .modbusException,
             .invalidParameter:
            false
        }
    }
}

// MARK: - ASCIIClientError

/// Errors for ModbusASCIIClient operations.
public enum ASCIIClientError: Error, Sendable, Equatable {
    /// Serial port is not open.
    case notConnected

    /// Serial port is already open.
    case alreadyConnected

    /// Failed to open serial port.
    case connectionFailed(String)

    /// Request timed out waiting for response.
    case timeout

    /// LRC checksum verification failed.
    case lrcError

    /// Invalid hex character in ASCII frame.
    case invalidHexCharacter

    /// Failed to encode ASCII frame.
    case frameEncodingFailed(String)

    /// Failed to decode ASCII frame.
    case frameDecodingFailed(String)

    /// Response frame too short.
    case frameTooShort(expected: Int, got: Int)

    /// Unit ID in response doesn't match request.
    case unitIdMismatch(expected: UInt8, got: UInt8)

    /// Function code in response doesn't match request.
    case functionCodeMismatch(expected: UInt8, got: UInt8)

    /// Byte count in response doesn't match expected.
    case byteCountMismatch(expected: Int, got: Int)

    /// Modbus exception response received.
    case modbusException(ModbusException)

    /// Invalid parameter value.
    case invalidParameter(String)

    /// I/O error during read/write.
    case ioError(String)

    // MARK: Public

    /// Whether this error is retryable.
    ///
    /// Retryable: timeout, LRC error, I/O error.
    /// Non-retryable: Modbus exception, validation errors.
    public var isRetryable: Bool {
        switch self {
        case .timeout,
             .lrcError,
             .invalidHexCharacter,
             .ioError,
             .frameTooShort:
            true
        case .notConnected,
             .alreadyConnected,
             .connectionFailed,
             .frameEncodingFailed,
             .frameDecodingFailed,
             .unitIdMismatch,
             .functionCodeMismatch,
             .byteCountMismatch,
             .modbusException,
             .invalidParameter:
            false
        }
    }
}
