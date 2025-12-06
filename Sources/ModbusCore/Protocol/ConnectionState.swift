// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ConnectionState

/// Explicit connection state machine for Modbus clients.
///
/// Common across all transports (TCP, TLS, UDP, RTU, ASCII).
/// Prevents race conditions and invalid state transitions.
public enum ConnectionState: Sendable, Equatable {
    /// Not connected / port closed
    case disconnected

    /// Connection / port opening in progress
    case connecting

    /// Connected / port open and ready
    case connected

    /// Disconnection / port closing in progress
    case disconnecting
}
