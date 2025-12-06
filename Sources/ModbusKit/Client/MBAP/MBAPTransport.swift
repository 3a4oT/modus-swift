// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Logging
import NIOCore

// MARK: - MBAPTransport

/// Internal protocol for shared MBAP-based transport logic.
///
/// MBAP (Modbus Application Protocol) is the framing layer used by both
/// Modbus TCP and Modbus TLS transports. This protocol defines the common
/// interface allowing code reuse between `ModbusTCPClient` and `ModbusTLSClient`.
///
/// ## MBAP Frame Structure
///
/// ```
/// +------------------+------------------+------------------+
/// | MBAP Header (7)  | Function Code(1) | Data (N)         |
/// +------------------+------------------+------------------+
/// | Transaction ID   | Unit ID          | PDU              |
/// | Protocol ID      |                  |                  |
/// | Length           |                  |                  |
/// +------------------+------------------+------------------+
/// ```
///
/// ## Supported Function Codes
///
/// All standard Modbus TCP function codes are implemented:
/// - **Read**: 0x01, 0x02, 0x03, 0x04
/// - **Write**: 0x05, 0x06, 0x0F, 0x10
/// - **Advanced**: 0x16, 0x17, 0x18
/// - **Device Identification**: 0x2B/0x0E
///
/// ## Reference
///
/// - MODBUS Messaging on TCP/IP Implementation Guide V1.0b
/// - MODBUS Application Protocol Specification V1.1b3
///
/// - Note: This is an internal protocol, not part of public API.
protocol MBAPTransport: AnyObject, Sendable {
    /// Client configuration containing host, port, timeout, etc.
    var configuration: ModbusClientConfiguration { get }

    /// Optional logger for request/response tracing.
    var logger: Logger? { get }

    /// Optional metrics collector for observability.
    var metrics: ModbusMetrics? { get }

    /// Current NIO channel (nil if disconnected).
    var channel: Channel? { get }

    /// Whether the client is currently connected.
    var isConnected: Bool { get }

    /// Generates next transaction ID (1-65535, wraps around).
    func nextTransactionId() -> UInt16

    /// Records activity timestamp for idle timeout tracking.
    func recordActivity()

    /// Ensures connection is established, auto-reconnecting if configured.
    ///
    /// Behavior depends on `configuration.reconnectionStrategy`:
    /// - `.disabled`: Throws `notConnected` if disconnected
    /// - `.immediate`: Reconnects immediately
    /// - `.exponentialBackoff`: Waits with increasing delay between attempts
    func ensureConnected() async throws(ModbusClientError)

    /// Sends request data and waits for response with proper pipelining support.
    ///
    /// This method ensures correct ordering of operations for pipelining:
    /// 1. **Pipelining mode**: Register promise → Write → Wait for promise
    /// 2. **Serial mode**: Write → Wait for next response
    ///
    /// The ordering is critical for pipelining because the response may arrive
    /// before the `await` point, so the promise must be registered first.
    ///
    /// - Parameters:
    ///   - channel: Active NIO channel
    ///   - data: Request data to write
    ///   - transactionId: Transaction ID for response matching
    /// - Returns: Raw response bytes including MBAP header
    /// - Throws: `timeout` if no response within configured timeout
    /// - Throws: `tooManyPendingRequests` if pipelining limit reached
    /// - Throws: `ioError` if write fails
    func sendRequest(
        channel: Channel,
        data: ByteBuffer,
        transactionId: UInt16,
    ) async throws(ModbusClientError) -> [UInt8]

    /// Maps MBAP-level errors to client errors.
    func mapMBAPError(_ error: MBAPError) -> ModbusClientError

    /// Maps PDU-level errors to client errors.
    func mapPDUError(_ error: PDUError) -> ModbusClientError
}
