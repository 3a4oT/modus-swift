// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ServiceLifecycle

// MARK: - Service Conformance

extension ModbusUDPClient: Service {
    /// Runs the client as a service.
    ///
    /// Waits for graceful shutdown signal, then closes the socket.
    public func run() async throws {
        try await gracefulShutdown()
        await close()
    }
}
