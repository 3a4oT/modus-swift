// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Binary Parsing Helpers

// Safe binary parsing helpers with bounds checking.
//
// **Design Philosophy:**
// - All functions return Optional — nil if out of bounds
// - Caller decides: `guard let` for safety, `!` if bounds pre-validated
// - No crashes on malformed network data
//
// **Why Optional instead of throwing?**
// - Simpler call sites (no try/catch)
// - Composable with `?` and `guard let`
// - Zero overhead when force-unwrapped after validation
//
// **Reference:** pymodbus has known bugs from insufficient bounds checking
// before struct.unpack. We prevent this class of bugs by design.

// MARK: - Single Byte

/// Reads a UInt8 value from a Span at the given offset.
///
/// - Parameters:
///   - data: Source data span
///   - offset: Byte offset to read from
/// - Returns: UInt8 value, or nil if offset is out of bounds
@inlinable
public func readUInt8(_ data: Span<UInt8>, at offset: Int) -> UInt8? {
    guard offset >= 0, offset < data.count else {
        return nil
    }
    return data[offset]
}

// MARK: - Big Endian (Modbus PDU standard)

/// Reads a UInt16 value from a Span at the given offset (Big Endian).
///
/// Modbus uses Big Endian for all multi-byte values in PDUs.
///
/// - Parameters:
///   - data: Source data span
///   - offset: Byte offset to read from
/// - Returns: UInt16 value in native byte order, or nil if out of bounds
@inlinable
public func readUInt16BE(_ data: Span<UInt8>, at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= data.count else {
        return nil
    }
    return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
}

/// Reads a UInt32 value from a Span at the given offset (Big Endian).
///
/// - Parameters:
///   - data: Source data span
///   - offset: Byte offset to read from
/// - Returns: UInt32 value in native byte order, or nil if out of bounds
@inlinable
public func readUInt32BE(_ data: Span<UInt8>, at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= data.count else {
        return nil
    }
    return (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
}

// MARK: - Little Endian (CRC-16 in RTU frames)

/// Reads a UInt16 value from a Span at the given offset (Little Endian).
///
/// Used by Modbus RTU for CRC-16 verification (CRC is stored in LE order).
///
/// - Parameters:
///   - data: Source data span
///   - offset: Byte offset to read from
/// - Returns: UInt16 value in native byte order, or nil if out of bounds
@inlinable
public func readUInt16LE(_ data: Span<UInt8>, at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= data.count else {
        return nil
    }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

/// Reads a UInt32 value from a Span at the given offset (Little Endian).
///
/// - Parameters:
///   - data: Source data span
///   - offset: Byte offset to read from
/// - Returns: UInt32 value in native byte order, or nil if out of bounds
@inlinable
public func readUInt32LE(_ data: Span<UInt8>, at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= data.count else {
        return nil
    }
    return UInt32(data[offset]) |
        (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) |
        (UInt32(data[offset + 3]) << 24)
}

// MARK: - Array Convenience Overloads

/// Reads a UInt8 value from an Array at the given offset.
@inlinable
public func readUInt8(_ data: [UInt8], at offset: Int) -> UInt8? {
    readUInt8(data.span, at: offset)
}

/// Reads a UInt16 value from an Array at the given offset (Big Endian).
@inlinable
public func readUInt16BE(_ data: [UInt8], at offset: Int) -> UInt16? {
    readUInt16BE(data.span, at: offset)
}

/// Reads a UInt16 value from an Array at the given offset (Little Endian).
@inlinable
public func readUInt16LE(_ data: [UInt8], at offset: Int) -> UInt16? {
    readUInt16LE(data.span, at: offset)
}

/// Reads a UInt32 value from an Array at the given offset (Big Endian).
@inlinable
public func readUInt32BE(_ data: [UInt8], at offset: Int) -> UInt32? {
    readUInt32BE(data.span, at: offset)
}

/// Reads a UInt32 value from an Array at the given offset (Little Endian).
@inlinable
public func readUInt32LE(_ data: [UInt8], at offset: Int) -> UInt32? {
    readUInt32LE(data.span, at: offset)
}
