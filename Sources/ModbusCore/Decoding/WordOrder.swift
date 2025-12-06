// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - WordOrder

/// Word order for decoding multi-register values (32-bit, 64-bit).
///
/// When reading 32-bit values from Modbus, two 16-bit registers must be combined.
/// Different devices use different byte/word ordering conventions.
///
/// Notation uses letters A, B, C, D where:
/// - A = most significant byte of high word
/// - B = least significant byte of high word
/// - C = most significant byte of low word
/// - D = least significant byte of low word
///
/// For value `0x12345678`:
/// - A = 0x12, B = 0x34, C = 0x56, D = 0x78
///
/// Reference: pymodbus `Endian.BIG`/`Endian.LITTLE` for byteorder/wordorder
///
/// Common device configurations:
/// - **Deye/Solis inverters**: AB_CD (Big Endian)
/// - **Some Modicon PLCs**: CD_AB (Little Endian words)
/// - **Varies by manufacturer**: Always verify with device documentation
public enum WordOrder: Sendable, Equatable {
    /// Big Endian words, Big Endian bytes: [AB][CD]
    ///
    /// Most common for industrial devices.
    /// Register 0: 0x1234 (high word)
    /// Register 1: 0x5678 (low word)
    /// Result: 0x12345678
    case abcd

    /// Big Endian words, Little Endian bytes: [BA][DC]
    ///
    /// Uncommon, used by some legacy systems.
    /// Register 0: 0x3412 (high word, bytes swapped)
    /// Register 1: 0x7856 (low word, bytes swapped)
    /// Result: 0x12345678
    case badc

    /// Little Endian words, Big Endian bytes: [CD][AB]
    ///
    /// Common for Modicon and some Schneider devices.
    /// Register 0: 0x5678 (low word)
    /// Register 1: 0x1234 (high word)
    /// Result: 0x12345678
    case cdab

    /// Little Endian words, Little Endian bytes: [DC][BA]
    ///
    /// Full Little Endian, used by some PLCs.
    /// Register 0: 0x7856 (low word, bytes swapped)
    /// Register 1: 0x3412 (high word, bytes swapped)
    /// Result: 0x12345678
    case dcba
}

// MARK: - WordOrder Decoding

/// Decodes a UInt32 from two 16-bit registers using specified word order.
///
/// - Parameters:
///   - registers: Tuple of two register values
///   - order: Word order configuration
/// - Returns: Decoded 32-bit unsigned value
@inlinable
public func decodeUInt32(
    _ registers: (UInt16, UInt16),
    order: WordOrder,
) -> UInt32 {
    let (r0, r1) = registers

    switch order {
    case .abcd:
        // [AB][CD] - r0 is high word, r1 is low word
        return (UInt32(r0) << 16) | UInt32(r1)

    case .badc:
        // [BA][DC] - swap bytes within each register
        let high = r0.byteSwapped
        let low = r1.byteSwapped
        return (UInt32(high) << 16) | UInt32(low)

    case .cdab:
        // [CD][AB] - r0 is low word, r1 is high word
        return (UInt32(r1) << 16) | UInt32(r0)

    case .dcba:
        // [DC][BA] - r0 is low word (swapped), r1 is high word (swapped)
        let high = r1.byteSwapped
        let low = r0.byteSwapped
        return (UInt32(high) << 16) | UInt32(low)
    }
}

/// Decodes an Int32 from two 16-bit registers using specified word order.
///
/// - Parameters:
///   - registers: Tuple of two register values
///   - order: Word order configuration
/// - Returns: Decoded 32-bit signed value
@inlinable
public func decodeInt32(
    _ registers: (UInt16, UInt16),
    order: WordOrder,
) -> Int32 {
    Int32(bitPattern: decodeUInt32(registers, order: order))
}

/// Decodes a Float32 from two 16-bit registers using specified word order.
///
/// Uses IEEE 754 single-precision floating-point format.
///
/// - Parameters:
///   - registers: Tuple of two register values
///   - order: Word order configuration
/// - Returns: Decoded 32-bit float value
@inlinable
public func decodeFloat32(
    _ registers: (UInt16, UInt16),
    order: WordOrder,
) -> Float {
    Float(bitPattern: decodeUInt32(registers, order: order))
}

// MARK: - ReadRegistersResponse Extension

extension ReadRegistersResponse {
    /// Decodes a UInt32 from two consecutive registers using specified word order.
    ///
    /// - Parameters:
    ///   - index: Starting register index (0-based)
    ///   - order: Word order configuration (default: .abcd)
    /// - Returns: Decoded value, or nil if not enough registers
    public func uint32Value(at index: Int, order: WordOrder) -> UInt32? {
        guard index >= 0, index + 1 < registers.count else {
            return nil
        }
        return decodeUInt32((registers[index], registers[index + 1]), order: order)
    }

    /// Decodes an Int32 from two consecutive registers using specified word order.
    ///
    /// - Parameters:
    ///   - index: Starting register index (0-based)
    ///   - order: Word order configuration (default: .abcd)
    /// - Returns: Decoded value, or nil if not enough registers
    public func int32Value(at index: Int, order: WordOrder) -> Int32? {
        guard let unsigned = uint32Value(at: index, order: order) else {
            return nil
        }
        return Int32(bitPattern: unsigned)
    }

    /// Decodes a Float32 from two consecutive registers using specified word order.
    ///
    /// - Parameters:
    ///   - index: Starting register index (0-based)
    ///   - order: Word order configuration
    /// - Returns: Decoded float value, or nil if not enough registers
    public func float32Value(at index: Int, order: WordOrder) -> Float? {
        guard let bits = uint32Value(at: index, order: order) else {
            return nil
        }
        return Float(bitPattern: bits)
    }
}
