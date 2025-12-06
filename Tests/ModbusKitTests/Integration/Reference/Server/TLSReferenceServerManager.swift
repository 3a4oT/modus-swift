// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Foundation
import NIOCore
import NIOPosix
import NIOSSL

// MARK: - TLSReferenceServerManager

/// Configuration for connecting to pymodbus TLS reference server.
///
/// The server must be started manually before running tests:
///
/// ```bash
/// # Start TLS server via Docker
/// docker compose up -d pymodbus-tls-server
///
/// # Or run directly (requires certificates)
/// cd docker/pymodbus-tls-server
/// python3 tls_reference_server.py --port 5021 -v
/// ```
///
/// Then run tests:
/// ```bash
/// swift test --filter PymodbusTLSValidation
/// ```
enum TLSReferenceServerManager {
    /// Default host for TLS reference server.
    /// Override with `MODBUS_TEST_HOST` env var (e.g., `host.docker.internal` in devcontainer).
    static let defaultHost: String = {
        if let env = getenv("MODBUS_TEST_HOST") {
            return String(cString: env)
        }
        return "127.0.0.1"
    }()

    /// Returns true if running in devcontainer (localhost is not the Docker host).
    static let isDevcontainer: Bool = getenv("MODBUS_TEST_HOST") != nil

    /// Default port for TLS reference server.
    /// Server should be started with: `--port 5021`
    /// Note: Port 5021 used instead of standard 802 to avoid requiring root.
    static let defaultPort = 5021

    /// Connection timeout for server availability check.
    static let connectionTimeout: Duration = .seconds(2)

    /// Path to test certificates (relative to package root).
    static let certsPath = "docker/pymodbus-tls-server/certs"

    /// Checks if the TLS reference server is available.
    ///
    /// Attempts a TLS connection to verify the server is running and
    /// accepting secure connections.
    ///
    /// - Returns: True if server is reachable via TLS
    static func isServerAvailable() async -> Bool {
        do {
            let timeoutNanos = connectionTimeout.components.seconds * 1_000_000_000 +
                connectionTimeout.components.attoseconds / 1_000_000_000

            // Create insecure TLS config for availability check
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none

            let sslContext = try NIOSSLContext(configuration: tlsConfig)

            let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connectTimeout(.nanoseconds(timeoutNanos))
                .channelInitializer { channel in
                    // SNI doesn't support IP addresses, use nil for availability check
                    let sslHandler = try! NIOSSLClientHandler(
                        context: sslContext,
                        serverHostname: nil,
                    )
                    return channel.pipeline.addHandler(sslHandler)
                }

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

    /// Runs test body with TLS server connection.
    ///
    /// Fails if server is not available.
    ///
    /// - Parameters:
    ///   - host: Server host (default: 127.0.0.1)
    ///   - port: Server port (default: 5021)
    ///   - body: Test closure receiving host and port
    /// - Throws: `TLSReferenceServerError.serverNotRunning` if server unavailable
    @discardableResult
    static func withServer<Result>(
        host: String = defaultHost,
        port: Int = defaultPort,
        body: (String, Int) async throws -> Result,
    ) async throws -> Result {
        guard await isServerAvailable() else {
            throw TLSReferenceServerError.serverNotRunning(host: host, port: port)
        }
        return try await body(host, port)
    }

    /// Returns path to CA certificate for TLS verification.
    ///
    /// - Parameter packageRoot: Root directory of the package
    /// - Returns: Absolute path to ca.crt
    static func caCertificatePath(packageRoot: String) -> String {
        "\(packageRoot)/\(certsPath)/ca.crt"
    }

    /// Returns path to client certificate for mTLS.
    ///
    /// - Parameter packageRoot: Root directory of the package
    /// - Returns: Absolute path to client.crt
    static func clientCertificatePath(packageRoot: String) -> String {
        "\(packageRoot)/\(certsPath)/client.crt"
    }

    /// Returns path to client key for mTLS.
    ///
    /// - Parameter packageRoot: Root directory of the package
    /// - Returns: Absolute path to client.key
    static func clientKeyPath(packageRoot: String) -> String {
        "\(packageRoot)/\(certsPath)/client.key"
    }
}

// MARK: - TLSReferenceServerError

/// Errors for TLS reference server management.
enum TLSReferenceServerError: Error, CustomStringConvertible {
    /// TLS server is not running or not reachable.
    case serverNotRunning(host: String, port: Int)

    /// Certificate file not found.
    case certificateNotFound(path: String)

    // MARK: Internal

    var description: String {
        switch self {
        case let .serverNotRunning(host, port):
            """
            TLS Reference server not running at \(host):\(port).

            Start the server with:
                docker compose up -d pymodbus-tls-server

            Or run directly:
                cd docker/pymodbus-tls-server
                python3 tls_reference_server.py --port \(port) -v
            """
        case let .certificateNotFound(path):
            """
            Certificate not found at: \(path)

            Generate certificates with:
                cd docker/pymodbus-tls-server
                ./generate_certs.sh certs
            """
        }
    }
}
