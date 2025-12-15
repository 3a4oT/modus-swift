// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Register Array Decoding

/// Decodes a UInt64 from an array of 1-4 registers using Little Endian word order.
///
/// Common for Deye/Solis inverter alarm/fault bitmasks where register count varies.
/// Uses CDAB word order (first register is LSW).
///
/// - Parameter registers: Array of 1-4 register values
/// - Returns: Decoded value, or nil if array is empty
///
/// ## Example
///
/// ```swift
/// // Device Alarm: 2 registers (32-bit)
/// let alarmRegisters: [UInt16] = [0x0002, 0x0000]  // Bit 1 set
/// let alarmBits = decodeRegistersLE(alarmRegisters)  // 0x00000002
///
/// // Device Fault: 4 registers (64-bit)
/// let faultRegisters: [UInt16] = [0x0040, 0x0000, 0x0000, 0x0000]  // Bit 6 set
/// let faultBits = decodeRegistersLE(faultRegisters)  // 0x0000000000000040
/// ```
@inlinable
public func decodeRegistersLE(_ registers: [UInt16]) -> UInt64? {
    guard !registers.isEmpty else {
        return nil
    }

    var result: UInt64 = 0
    for (index, register) in registers.prefix(4).enumerated() {
        result |= UInt64(register) << (index * 16)
    }
    return result
}

/// Decodes a UInt64 from an array of 1-4 registers using Big Endian word order.
///
/// First register is MSW (most significant word).
///
/// - Parameter registers: Array of 1-4 register values
/// - Returns: Decoded value, or nil if array is empty
@inlinable
public func decodeRegistersBE(_ registers: [UInt16]) -> UInt64? {
    guard !registers.isEmpty else {
        return nil
    }

    let count = min(registers.count, 4)
    var result: UInt64 = 0
    for (index, register) in registers.prefix(4).enumerated() {
        let shift = (count - 1 - index) * 16
        result |= UInt64(register) << shift
    }
    return result
}

// MARK: - Array Extension

extension [UInt16] {
    /// Decodes registers to UInt64 using Little Endian word order (CDAB).
    ///
    /// Common for Deye/Solis inverters.
    public var uint64LE: UInt64? {
        decodeRegistersLE(self)
    }

    /// Decodes registers to UInt64 using Big Endian word order (ABCD).
    public var uint64BE: UInt64? {
        decodeRegistersBE(self)
    }
}
