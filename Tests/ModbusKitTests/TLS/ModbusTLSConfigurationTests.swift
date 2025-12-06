// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOSSL
import Testing

/// Tests for ModbusTLSConfiguration.
///
/// Reference: MODBUS/TCP Security Protocol Specification v36
@Suite("ModbusTLSConfiguration")
struct ModbusTLSConfigurationTests {
    // MARK: - Factory Methods

    @Test("makeClientConfiguration creates secure defaults")
    func makeClientConfigurationDefaults() {
        let config = ModbusTLSConfiguration.makeClientConfiguration()

        // Per spec: TLS 1.2 minimum required
        #expect(config.minimumTLSVersion == .tlsv12)
        #expect(config.maximumTLSVersion == nil)

        // Secure defaults
        #expect(config.certificateVerification == .fullVerification)
        #expect(config.certificateChain.isEmpty)
        #expect(config.privateKey == nil)
    }

    @Test("makeInsecureClientConfiguration disables verification")
    func makeInsecureClientConfigurationDefaults() {
        let config = ModbusTLSConfiguration.makeInsecureClientConfiguration()

        // Still requires TLS 1.2+ per spec
        #expect(config.minimumTLSVersion == .tlsv12)

        // Verification disabled for development
        #expect(config.certificateVerification == .none)
    }

    // MARK: - NIOSSL Conversion

    @Test("makeNIOSSLConfiguration converts correctly")
    func makeNIOSSLConfigurationConverts() {
        var config = ModbusTLSConfiguration.makeClientConfiguration()
        config.minimumTLSVersion = .tlsv12
        config.maximumTLSVersion = .tlsv13
        config.certificateVerification = .noHostnameVerification

        let nioConfig = config.makeNIOSSLConfiguration()

        #expect(nioConfig.minimumTLSVersion == .tlsv12)
        #expect(nioConfig.maximumTLSVersion == .tlsv13)
        #expect(nioConfig.certificateVerification == .noHostnameVerification)
    }

    @Test("makeNIOSSLConfiguration preserves trust roots")
    func makeNIOSSLConfigurationPreservesTrustRoots() {
        var config = ModbusTLSConfiguration.makeClientConfiguration()
        config.trustRoots = .default

        let nioConfig = config.makeNIOSSLConfiguration()

        // Trust roots should be set
        #expect(nioConfig.trustRoots != nil)
    }

    // MARK: - Custom Configuration

    @Test("Custom TLS version constraints")
    func customTLSVersionConstraints() {
        let config = ModbusTLSConfiguration(
            minimumTLSVersion: .tlsv13,
            maximumTLSVersion: .tlsv13,
        )

        #expect(config.minimumTLSVersion == .tlsv13)
        #expect(config.maximumTLSVersion == .tlsv13)

        let nioConfig = config.makeNIOSSLConfiguration()
        #expect(nioConfig.minimumTLSVersion == .tlsv13)
        #expect(nioConfig.maximumTLSVersion == .tlsv13)
    }

    @Test("Configuration with certificate chain")
    func configurationWithCertificateChain() {
        var config = ModbusTLSConfiguration.makeClientConfiguration()
        config.certificateChain = [.file("/path/to/cert.pem")]
        config.privateKey = .file("/path/to/key.pem")

        #expect(config.certificateChain.count == 1)
        #expect(config.privateKey != nil)
    }

    // MARK: - Constants

    @Test("Default TLS port is 802")
    func defaultTLSPort() {
        // Per MODBUS/TCP Security spec: port 802
        #expect(ModbusTLSDefaultPort == 802)
    }
}
