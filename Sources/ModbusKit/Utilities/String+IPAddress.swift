// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

#if canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Darwin)
    import Darwin.C
#elseif canImport(Android)
    import Android
#else
    #error("Unsupported platform")
#endif

// MARK: - IP Address Detection

extension String {
    /// Checks if this string is an IP address (IPv4 or IPv6).
    ///
    /// Uses POSIX `inet_pton` for reliable detection, matching the approach
    /// used by swift-nio-ssl internally.
    ///
    /// Per TLS specification (RFC 6066), SNI only supports DNS hostnames.
    /// IP addresses should not be sent as SNI - pass `nil` to `NIOSSLClientHandler`
    /// when connecting to IP addresses.
    ///
    /// ## Thread Safety
    ///
    /// This function is thread-safe. `inet_pton` writes to caller-provided
    /// stack buffers and has no shared state.
    ///
    /// ## Examples
    ///
    /// ```swift
    /// "192.168.1.100".isIPAddress    // true (IPv4)
    /// "127.0.0.1".isIPAddress        // true (IPv4)
    /// "::1".isIPAddress              // true (IPv6)
    /// "2001:db8::1".isIPAddress      // true (IPv6)
    /// "localhost".isIPAddress        // false
    /// "example.com".isIPAddress      // false
    /// ```
    ///
    /// - Returns: `true` if this string is a valid IPv4 or IPv6 address
    @usableFromInline
    var isIPAddress: Bool {
        // Stack-allocated buffers for inet_pton output
        var ipv4Addr = in_addr()
        var ipv6Addr = in6_addr()

        return withCString { ptr in
            inet_pton(AF_INET, ptr, &ipv4Addr) == 1 ||
                inet_pton(AF_INET6, ptr, &ipv6Addr) == 1
        }
    }
}
