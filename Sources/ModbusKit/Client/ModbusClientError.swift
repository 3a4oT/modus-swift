// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ModbusClientError

/// Errors that can occur during Modbus client operations.
///
/// This is the canonical error type for all client operations.
/// All async client methods throw this type exclusively.
public enum ModbusClientError: Error, Equatable, Sendable {
    /// Not connected to device
    case notConnected

    /// Already connected
    case alreadyConnected

    /// Connection failed with reason
    case connectionFailed(String)

    /// Operation timed out
    case timeout

    /// Transaction ID mismatch in response
    case transactionIdMismatch(expected: UInt16, got: UInt16)

    /// Unit ID mismatch in response
    case unitIdMismatch(expected: UInt8, got: UInt8)

    /// Invalid response from device
    case invalidResponse(String)

    /// Modbus exception response from device
    case modbusException(ModbusException)

    /// MBAP protocol error
    case mbapError(String)

    /// PDU protocol error
    case pduError(String)

    /// I/O error during communication
    case ioError(String)

    /// Invalid parameter (e.g., count > 125)
    case invalidParameter(String)

    /// Channel closed unexpectedly
    case channelClosed

    /// TLS configuration error (invalid certificate, key, etc.)
    case tlsConfigurationError(String)

    /// TLS handshake failed
    case tlsHandshakeFailed(String)

    /// Too many pending requests (pipelining limit reached)
    ///
    /// Thrown when attempting to send a request while the maximum number
    /// of in-flight requests (`PipeliningConfiguration.maxInFlight`) is reached.
    case tooManyPendingRequests

    /// Transaction ID already in use
    ///
    /// Thrown when attempting to register a request with a Transaction ID
    /// that is already pending. This is extremely rare (requires 65535 in-flight
    /// requests to exhaust all IDs).
    case transactionIdInUse(UInt16)

    // MARK: Public

    /// Whether this error is transient and operation can be retried.
    ///
    /// Retryable errors are typically network/timing issues.
    /// Non-retryable errors are protocol violations or device rejections.
    public var isRetryable: Bool {
        switch self {
        case .timeout,
             .ioError,
             .channelClosed,
             .connectionFailed,
             .tlsHandshakeFailed:
            true
        case .notConnected,
             .alreadyConnected,
             .invalidParameter,
             .modbusException,
             .transactionIdMismatch,
             .unitIdMismatch,
             .invalidResponse,
             .mbapError,
             .pduError,
             .tlsConfigurationError,
             .tooManyPendingRequests,
             .transactionIdInUse:
            false
        }
    }

    /// Short label for metrics dimension.
    public var metricsLabel: String {
        switch self {
        case .notConnected: "not_connected"
        case .alreadyConnected: "already_connected"
        case .connectionFailed: "connection_failed"
        case .timeout: "timeout"
        case .transactionIdMismatch: "transaction_id_mismatch"
        case .unitIdMismatch: "unit_id_mismatch"
        case .invalidResponse: "invalid_response"
        case .modbusException: "modbus_exception"
        case .mbapError: "mbap_error"
        case .pduError: "pdu_error"
        case .ioError: "io_error"
        case .invalidParameter: "invalid_parameter"
        case .channelClosed: "channel_closed"
        case .tlsConfigurationError: "tls_configuration_error"
        case .tlsHandshakeFailed: "tls_handshake_failed"
        case .tooManyPendingRequests: "too_many_pending_requests"
        case .transactionIdInUse: "transaction_id_in_use"
        }
    }
}
