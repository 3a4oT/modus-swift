// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOSSL

// MARK: - ModbusTLSConfiguration

/// TLS configuration for Modbus/TCP Security (port 802).
///
/// Implements MODBUS/TCP Security Protocol Specification requirements:
/// - TLS 1.2 minimum (MUST NOT negotiate to lower versions)
/// - X.509v3 certificate-based authentication
/// - Optional mutual TLS (mTLS) for client authentication
///
/// ## Default Configuration
///
/// The default configuration uses system trust roots and full certificate
/// verification, suitable for connecting to servers with valid certificates:
///
/// ```swift
/// let config = ModbusTLSConfiguration.makeClientConfiguration()
/// let client = ModbusTLSClient(host: "192.168.1.100", tlsConfiguration: config)
/// ```
///
/// ## Custom Certificate Authority
///
/// For servers using private/self-signed certificates:
///
/// ```swift
/// var config = ModbusTLSConfiguration.makeClientConfiguration()
/// config.trustRoots = .file("/path/to/ca.pem")
/// ```
///
/// ## Mutual TLS (mTLS)
///
/// For client certificate authentication:
///
/// ```swift
/// var config = ModbusTLSConfiguration.makeClientConfiguration()
/// config.certificateChain = [.file("/path/to/client-cert.pem")]
/// config.privateKey = .file("/path/to/client-key.pem")
/// ```
///
/// ## Development/Testing (Insecure)
///
/// For development with self-signed certificates (NOT for production):
///
/// ```swift
/// var config = ModbusTLSConfiguration.makeClientConfiguration()
/// config.certificateVerification = .none
/// ```
///
/// Reference:
/// - MODBUS/TCP Security Protocol Specification v36 (2021-07-30)
/// - pymodbus `generate_ssl()` in transport.py
/// - tokio-modbus TLS configuration
public struct ModbusTLSConfiguration: Sendable {
    // MARK: Lifecycle

    /// Creates a TLS configuration with specified parameters.
    ///
    /// - Parameters:
    ///   - minimumTLSVersion: Minimum TLS version (default: TLS 1.2 per spec)
    ///   - maximumTLSVersion: Maximum TLS version (default: nil = highest available)
    ///   - certificateVerification: Server certificate verification mode
    ///   - trustRoots: Certificate authorities for verification
    ///   - certificateChain: Client certificates for mTLS
    ///   - privateKey: Client private key for mTLS
    public init(
        minimumTLSVersion: TLSVersion = .tlsv12,
        maximumTLSVersion: TLSVersion? = nil,
        certificateVerification: CertificateVerification = .fullVerification,
        trustRoots: NIOSSLTrustRoots = .default,
        certificateChain: [NIOSSLCertificateSource] = [],
        privateKey: NIOSSLPrivateKeySource? = nil,
    ) {
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.certificateVerification = certificateVerification
        self.trustRoots = trustRoots
        self.certificateChain = certificateChain
        self.privateKey = privateKey
    }

    // MARK: Public

    /// Minimum TLS version to accept.
    ///
    /// Per MODBUS/TCP Security spec: "The version must be TLS v1.2 or higher,
    /// not negotiate down to previous versions of TLS or use SSL3.0 or lower."
    ///
    /// Default: `.tlsv12`
    public var minimumTLSVersion: TLSVersion

    /// Maximum TLS version to accept.
    ///
    /// Default: `nil` (use highest available, typically TLS 1.3)
    public var maximumTLSVersion: TLSVersion?

    /// Server certificate verification mode.
    ///
    /// - `.fullVerification`: Verify certificate chain and hostname (default, recommended)
    /// - `.noHostnameVerification`: Verify chain only, skip hostname check
    /// - `.none`: Skip all verification (INSECURE, development only)
    ///
    /// Reference: pymodbus uses `verify_mode = ssl.CERT_NONE` by default,
    /// but spec recommends full verification for production.
    public var certificateVerification: CertificateVerification

    /// Trust roots for server certificate verification.
    ///
    /// - `.default`: System certificate store
    /// - `.file(path)`: PEM file or directory with CA certificates
    /// - `.certificates([NIOSSLCertificate])`: Explicit certificate list
    public var trustRoots: NIOSSLTrustRoots

    /// Client certificate chain for mutual TLS (mTLS).
    ///
    /// Required when server demands client authentication.
    /// Certificates should be in order: client cert first, then intermediates.
    public var certificateChain: [NIOSSLCertificateSource]

    /// Client private key for mutual TLS (mTLS).
    ///
    /// Must correspond to the first certificate in `certificateChain`.
    public var privateKey: NIOSSLPrivateKeySource?

    // MARK: - Factory Methods

    /// Creates a client configuration with secure defaults.
    ///
    /// Settings:
    /// - TLS 1.2 minimum (per Modbus/TCP Security spec)
    /// - Full certificate verification enabled
    /// - System trust roots
    /// - No client certificate (server-only authentication)
    ///
    /// Reference: Follows MODBUS/TCP Security Protocol Specification defaults.
    public static func makeClientConfiguration() -> ModbusTLSConfiguration {
        ModbusTLSConfiguration(
            minimumTLSVersion: .tlsv12,
            maximumTLSVersion: nil,
            certificateVerification: .fullVerification,
            trustRoots: .default,
            certificateChain: [],
            privateKey: nil,
        )
    }

    /// Creates a client configuration for development/testing.
    ///
    /// **WARNING:** Disables certificate verification. Use only for development
    /// with self-signed certificates. Never use in production.
    ///
    /// Reference: pymodbus default behavior with `verify_mode = ssl.CERT_NONE`
    public static func makeInsecureClientConfiguration() -> ModbusTLSConfiguration {
        ModbusTLSConfiguration(
            minimumTLSVersion: .tlsv12,
            maximumTLSVersion: nil,
            certificateVerification: .none,
            trustRoots: .default,
            certificateChain: [],
            privateKey: nil,
        )
    }

    // MARK: Internal

    /// Converts to NIOSSL TLSConfiguration.
    func makeNIOSSLConfiguration() -> TLSConfiguration {
        var config = TLSConfiguration.makeClientConfiguration()

        // TLS version constraints (spec requires 1.2+)
        config.minimumTLSVersion = minimumTLSVersion
        config.maximumTLSVersion = maximumTLSVersion

        // Certificate verification
        config.certificateVerification = certificateVerification

        // Trust roots
        config.trustRoots = trustRoots

        // Client certificate for mTLS
        if !certificateChain.isEmpty {
            config.certificateChain = certificateChain
        }
        if let privateKey {
            config.privateKey = privateKey
        }

        return config
    }
}

// MARK: - Constants

/// Default port for Modbus/TCP Security (TLS).
///
/// Per MODBUS/TCP Security Protocol Specification:
/// "The Modbus/TCP Security protocol is registered under port 802."
public let ModbusTLSDefaultPort = 802
