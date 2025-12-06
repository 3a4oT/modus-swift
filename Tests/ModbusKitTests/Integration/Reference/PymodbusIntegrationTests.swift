// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - PymodbusIntegrationTests

/// Integration tests against pymodbus reference server (TCP and TLS).
///
/// All tests run serialized to avoid connection conflicts.
///
/// ## Requirements
///
/// Start the reference servers before running tests:
///
/// ```bash
/// docker compose up -d pymodbus-server pymodbus-tls-server
/// swift test --filter PymodbusIntegrationTests
/// docker compose down
/// ```
///
/// ## Test Certificates (TLS)
///
/// TLS tests use certificates from `docker/pymodbus-tls-server/certs/`:
/// - `ca.crt` - CA certificate (for client trust)
/// - `server.crt` - Server certificate (signed by CA)
/// - `client.crt` - Client certificate (for mTLS)
///
/// ## TLS Specification References
///
/// - RFC 5246 Section 7.2.2: Alert Protocol
/// - RFC 6066: TLS Extensions (SNI)
/// - MODBUS/TCP Security Protocol Specification
@Suite("Pymodbus Integration", .serialized)
struct PymodbusIntegrationTests {
    /// Path to TLS certificates directory.
    var certsDirectory: String {
        let filePath = #filePath
        let components = filePath.split(separator: "/")
        guard let testsIndex = components.firstIndex(of: "Tests") else {
            fatalError("Could not find Tests directory in path: \(filePath)")
        }
        let backendComponents = components[..<testsIndex]
        let backendPath = "/" + backendComponents.joined(separator: "/")
        return backendPath + "/docker/pymodbus-tls-server/certs"
    }
}
