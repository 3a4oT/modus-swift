// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Hex Formatting (Foundation-free)

/// Formats a byte as uppercase hex string with leading zero.
///
/// Uses `String(_:radix:uppercase:)` instead of `String(format:)` to avoid
/// Foundation dependency. This makes the code compatible with Embedded Swift
/// and reduces binary size.
///
/// - Parameter byte: Byte to format
/// - Returns: Two-character hex string (e.g., "0A", "FF")
///
/// ## Example
///
/// ```swift
/// formatHex(0x0A)  // "0A"
/// formatHex(0xFF)  // "FF"
/// formatHex(0x00)  // "00"
/// ```
@inlinable
public func formatHex(_ byte: UInt8) -> String {
    let hex = String(byte, radix: 16, uppercase: true)
    return byte < 16 ? "0\(hex)" : hex
}

/// Formats a byte array as space-separated hex string.
///
/// - Parameter bytes: Bytes to format
/// - Returns: Hex string (e.g., "01 03 00 6B 00 03 54 08")
///
/// ## Example
///
/// ```swift
/// formatHexBytes([0x01, 0x03, 0x00, 0x6B])  // "01 03 00 6B"
/// ```
@inlinable
public func formatHexBytes(_ bytes: [UInt8]) -> String {
    bytes.map { formatHex($0) }.joined(separator: " ")
}

/// Formats a byte array as space-separated hex string.
///
/// Generic version for any `Sequence` of `UInt8`.
@inlinable
public func formatHexBytes(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { formatHex($0) }.joined(separator: " ")
}

/// Formats a 16-bit value as 4-character hex string.
///
/// - Parameter value: Value to format
/// - Returns: Four-character hex string (e.g., "006B", "FFFF")
@inlinable
public func formatHex16(_ value: UInt16) -> String {
    let hex = String(value, radix: 16, uppercase: true)
    let padding = String(repeating: "0", count: 4 - hex.count)
    return padding + hex
}

/// Formats a function code as "0x" prefixed hex string.
///
/// - Parameter functionCode: Modbus function code
/// - Returns: Prefixed hex string (e.g., "0x03", "0x10")
@inlinable
public func formatFunctionCode(_ functionCode: UInt8) -> String {
    "0x\(formatHex(functionCode))"
}

// MARK: - Array Extension

extension [UInt8] {
    /// Formats bytes as space-separated hex string.
    ///
    /// ```swift
    /// [0x01, 0x03, 0x00, 0x6B].hexString  // "01 03 00 6B"
    /// ```
    @inlinable
    public var hexString: String {
        map { formatHex($0) }.joined(separator: " ")
    }
}

extension ArraySlice where Element == UInt8 {
    /// Formats bytes as space-separated hex string.
    @inlinable
    public var hexString: String {
        map { formatHex($0) }.joined(separator: " ")
    }
}
