// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - UDPTransportConfiguration

/// Configuration for UDP transport.
public struct UDPTransportConfiguration: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates UDP transport configuration.
    ///
    /// - Parameters:
    ///   - host: Remote hostname or IP address
    ///   - port: Remote UDP port
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    // MARK: Public

    /// Remote hostname or IP address.
    public let host: String

    /// Remote UDP port.
    public let port: Int
}
