// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOSSL
import Testing

// MARK: - TLS Error Handling Tests

extension PymodbusIntegrationTests {
    // MARK: - mTLS Tests (Mutual TLS)

    @Test("Connection with client certificate succeeds")
    func connectionWithClientCertificate() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .noHostnameVerification
            let clientCerts = try NIOSSLCertificate.fromPEMFile(certsDirectory + "/client.crt")
            tlsConfig.certificateChain = clientCerts.map { .certificate($0) }
            let privateKey = try NIOSSLPrivateKey(file: certsDirectory + "/client.key", format: .pem)
            tlsConfig.privateKey = .privateKey(privateKey)

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                #expect(client.isConnected)

                let response = try await client.readHoldingRegisters(
                    address: 0,
                    count: 1,
                    unitId: 1,
                )
                #expect(response.registers.count == 1)
            }
        }
    }

    // MARK: - Certificate Verification Tests

    @Test("Connection with valid CA certificate succeeds")
    func connectionWithValidCA() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .noHostnameVerification

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                #expect(client.isConnected)

                let response = try await client.readHoldingRegisters(
                    address: 0,
                    count: 1,
                    unitId: 1,
                )
                #expect(response.registers.count == 1)
            }
        }
    }

    @Test(
        "Connection with full verification and localhost succeeds",
        .enabled(if: !TLSReferenceServerManager.isDevcontainer, "localhost unreachable in devcontainer"),
    )
    func connectionWithFullVerificationLocalhost() async throws {
        try await TLSReferenceServerManager.withServer { _, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .fullVerification

            try await withModbusTLSClient(
                host: "localhost",
                port: port,
                timeout: .milliseconds(1000),
                tlsConfiguration: tlsConfig,
            ) { client in
                #expect(client.isConnected)
            }
        }
    }

    /// Per RFC 5246 Section 7.2.2, unknown_ca (48) is a fatal alert.
    @Test(
        "Connection fails with untrusted certificate (RFC 5246)",
        .enabled(if: !TLSReferenceServerManager.isDevcontainer, "localhost unreachable in devcontainer"),
    )
    func connectionFailsWithUntrustedCertificate() async throws {
        try await TLSReferenceServerManager.withServer { _, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .fullVerification

            await #expect(throws: ModbusClientError.self) {
                try await withModbusTLSClient(
                    host: "localhost",
                    port: port,
                    timeout: .milliseconds(1000),
                    tlsConfiguration: tlsConfig,
                ) { client in
                    _ = try await client.readHoldingRegisters(address: 0, count: 1, unitId: 1)
                }
            }
        }
    }

    /// Per RFC 6066 Section 3, hostname verification must fail when
    /// the server certificate does not match the requested hostname.
    @Test("Connection fails with hostname mismatch (RFC 6066)")
    func connectionFailsWithHostnameMismatch() async throws {
        try await TLSReferenceServerManager.withServer { _, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .fullVerification

            await #expect(throws: ModbusClientError.self) {
                try await withModbusTLSClient(
                    host: "invalid-hostname.local",
                    port: port,
                    timeout: .milliseconds(1000),
                    tlsConfiguration: tlsConfig,
                ) { _ in }
            }
        }
    }

    // MARK: - TLS Version Tests

    /// MODBUS/TCP Security requires TLS 1.2 minimum.
    @Test("TLS 1.2 connection succeeds (MODBUS/TCP Security requirement)")
    func tls12ConnectionSucceeds() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .noHostnameVerification
            tlsConfig.minimumTLSVersion = .tlsv12
            tlsConfig.maximumTLSVersion = .tlsv12

            try await withModbusTLSClient(
                host: host,
                port: port,
                timeout: .seconds(5),
                tlsConfiguration: tlsConfig,
            ) { client in
                #expect(client.isConnected)
            }
        }
    }

    @Test("TLS 1.3 connection succeeds when server supports it")
    func tls13ConnectionSucceeds() async throws {
        try await TLSReferenceServerManager.withServer { host, port in
            var tlsConfig = ModbusTLSConfiguration.makeClientConfiguration()
            tlsConfig.trustRoots = .file(certsDirectory + "/ca.crt")
            tlsConfig.certificateVerification = .noHostnameVerification
            tlsConfig.minimumTLSVersion = .tlsv13
            tlsConfig.maximumTLSVersion = .tlsv13

            do {
                try await withModbusTLSClient(
                    host: host,
                    port: port,
                    timeout: .seconds(5),
                    tlsConfiguration: tlsConfig,
                ) { client in
                    #expect(client.isConnected)
                }
            } catch {
                #expect(error is ModbusClientError)
            }
        }
    }

    // MARK: - Connection Error Tests

    @Test("Connection timeout is respected")
    func connectionTimeoutIsRespected() async throws {
        let tlsConfig = ModbusTLSConfiguration.makeInsecureClientConfiguration()

        let startTime = ContinuousClock.now

        await #expect(throws: ModbusClientError.self) {
            try await withModbusTLSClient(
                host: "10.255.255.1",
                port: 802,
                timeout: .milliseconds(500),
                tlsConfiguration: tlsConfig,
            ) { _ in }
        }

        let elapsed = ContinuousClock.now - startTime
        #expect(elapsed < .seconds(3))
    }
}
