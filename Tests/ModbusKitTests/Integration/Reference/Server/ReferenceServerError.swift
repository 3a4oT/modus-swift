// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ReferenceServerError

/// Errors related to reference server operations.
enum ReferenceServerError: Error, CustomStringConvertible, Sendable {
    /// Server is not running at the expected address.
    case serverNotRunning(host: String, port: Int)

    // MARK: Internal

    var description: String {
        switch self {
        case let .serverNotRunning(host, port):
            """
            Reference server not running at \(host):\(port).

            Start the Docker server:
                docker compose up -d pymodbus-server
            """
        }
    }
}
