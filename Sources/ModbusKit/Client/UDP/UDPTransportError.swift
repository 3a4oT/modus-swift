// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - UDPTransportError

/// Errors from UDP transport operations.
public enum UDPTransportError: Error, Equatable, Sendable {
    /// Failed to bind local socket.
    case bindFailed(String)

    /// Failed to send datagram.
    case sendFailed(String)

    /// Failed to receive datagram.
    case receiveFailed(String)

    /// Receive timeout expired.
    case timeout

    /// Transport not bound.
    case notBound

    /// Transport already bound.
    case alreadyBound
}
