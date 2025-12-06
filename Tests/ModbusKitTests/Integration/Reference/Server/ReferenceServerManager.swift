// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore
import NIOPosix

// MARK: - ReferenceServerManager

/// Configuration for connecting to pymodbus reference server.
///
/// Start the Docker server before running tests:
///
/// ```bash
/// docker compose up -d pymodbus-server
/// swift test --filter PymodbusValidation
/// docker compose down
/// ```
enum ReferenceServerManager {
    /// Default host for reference server.
    /// Override with `MODBUS_TEST_HOST` env var (e.g., `host.docker.internal` in devcontainer).
    static let defaultHost: String = {
        if let env = getenv("MODBUS_TEST_HOST") {
            return String(cString: env)
        }
        return "127.0.0.1"
    }()

    /// Default port for reference server.
    /// Server should be started with: `--port 5020`
    static let defaultPort = 5020

    /// Connection timeout for server availability check.
    static let connectionTimeout: Duration = .seconds(2)

    /// Checks if the reference server is available.
    ///
    /// Uses SwiftNIO ClientBootstrap for consistency with ModbusTCPClient.
    /// This ensures proper resource management and integration with the NIO event loop.
    ///
    /// - Returns: True if server is reachable
    static func isServerAvailable() async -> Bool {
        do {
            let timeoutNanos = connectionTimeout.components.seconds * 1_000_000_000 +
                connectionTimeout.components.attoseconds / 1_000_000_000

            let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connectTimeout(.nanoseconds(timeoutNanos))

            let channel = try await bootstrap.connect(
                host: defaultHost,
                port: defaultPort,
            ).get()

            try await channel.close()
            return true
        } catch {
            return false
        }
    }

    /// Runs test body with server connection.
    ///
    /// Fails if server is not available.
    ///
    /// - Parameters:
    ///   - host: Server host (default: 127.0.0.1)
    ///   - port: Server port (default: 5020)
    ///   - body: Test closure receiving host and port
    /// - Throws: `ReferenceServerError.serverNotRunning` if server unavailable
    @discardableResult
    static func withServer<Result>(
        host: String = defaultHost,
        port: Int = defaultPort,
        body: (String, Int) async throws -> Result,
    ) async throws -> Result {
        guard await isServerAvailable() else {
            throw ReferenceServerError.serverNotRunning(host: host, port: port)
        }
        return try await body(host, port)
    }
}
