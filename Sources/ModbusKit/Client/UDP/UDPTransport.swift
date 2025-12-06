// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - UDPTransport

/// Protocol for UDP transport implementations.
///
/// This abstraction allows for:
/// - SwiftNIO implementation for production
/// - Mock implementation for testing
///
/// UDP is connectionless, so the transport:
/// - Binds to a local port on first send (lazy initialization)
/// - Sends datagrams to remote address
/// - Receives datagrams with timeout
///
/// Reference: pymodbus ModbusUdpClient transport layer
public protocol UDPTransport: Sendable {
    /// Whether the transport is bound to a local port.
    var isBound: Bool { get }

    /// Binds the UDP socket to a local port.
    ///
    /// - Throws: `UDPTransportError` if bind fails
    func bind() async throws(UDPTransportError)

    /// Closes the UDP socket.
    ///
    /// Safe to call multiple times. No-op if not bound.
    func close() async

    /// Sends a datagram to the configured remote address.
    ///
    /// Auto-binds if not already bound.
    ///
    /// - Parameter data: Bytes to send
    /// - Throws: `UDPTransportError` on failure
    func send(_ data: [UInt8]) async throws(UDPTransportError)

    /// Receives a datagram with timeout.
    ///
    /// - Parameter timeout: Maximum time to wait for response
    /// - Returns: Received bytes
    /// - Throws: `UDPTransportError.timeout` if no data within timeout
    func receive(timeout: Duration) async throws(UDPTransportError) -> [UInt8]
}
