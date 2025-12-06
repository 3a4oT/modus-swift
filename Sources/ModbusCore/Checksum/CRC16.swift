// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Modbus CRC-16

/// Calculates CRC-16/MODBUS checksum.
///
/// Algorithm parameters:
/// - Polynomial: 0x8005 (reversed: 0xA001)
/// - Initial value: 0xFFFF
/// - Input reflected: Yes
/// - Output reflected: Yes
/// - XOR out: 0x0000
/// - Check value: 0x4B37 (for ASCII "123456789")
///
/// Reference: Modbus Serial Line Protocol and Implementation Guide V1.02
///
/// - Parameter bytes: Data bytes to calculate CRC over
/// - Returns: 16-bit CRC value (low byte first in Modbus frame)
@inlinable
public func calculateModbusCRC16(_ bytes: Span<UInt8>) -> UInt16 {
    var crc: UInt16 = 0xFFFF

    for i in bytes.indices {
        crc ^= UInt16(bytes[i])
        for _ in 0 ..< 8 {
            if crc & 0x0001 != 0 {
                crc = (crc >> 1) ^ 0xA001
            } else {
                crc >>= 1
            }
        }
    }

    return crc
}

// MARK: - CRC Byte Extraction

/// Extracts CRC low byte (first byte in Modbus frame)
@inlinable
public func crcLowByte(_ crc: UInt16) -> UInt8 {
    UInt8(truncatingIfNeeded: crc)
}

/// Extracts CRC high byte (second byte in Modbus frame)
@inlinable
public func crcHighByte(_ crc: UInt16) -> UInt8 {
    UInt8(truncatingIfNeeded: crc >> 8)
}

// MARK: - CRC Verification (Hot Path - Span)

/// Verifies CRC of a complete Modbus frame (including CRC bytes at end)
///
/// - Parameter frame: Complete Modbus RTU frame with CRC
/// - Returns: true if CRC is valid
@inlinable
public func verifyModbusCRC(_ frame: Span<UInt8>) -> Bool {
    guard frame.count >= 3 else {
        return false
    }

    let dataLength = frame.count - 2

    // Calculate CRC over data portion
    var crc: UInt16 = 0xFFFF
    for i in 0 ..< dataLength {
        // Defense in depth: use safe access
        guard let byte = readUInt8(frame, at: i) else {
            return false
        }
        crc ^= UInt16(byte)
        for _ in 0 ..< 8 {
            if crc & 0x0001 != 0 {
                crc = (crc >> 1) ^ 0xA001
            } else {
                crc >>= 1
            }
        }
    }

    // Defense in depth: use safe access for CRC bytes
    guard let frameCRC = readUInt16LE(frame, at: dataLength) else {
        return false
    }

    return crc == frameCRC
}

// MARK: - Convenience API (Build Phase - Array)

/// Calculates CRC-16/MODBUS checksum (convenience overload for Array)
///
/// - Parameter bytes: Data bytes to calculate CRC over
/// - Returns: 16-bit CRC value
@inlinable
public func calculateModbusCRC16(_ bytes: [UInt8]) -> UInt16 {
    calculateModbusCRC16(bytes.span)
}

/// Calculates CRC-16/MODBUS checksum (convenience overload for ArraySlice)
///
/// - Parameter bytes: Data bytes to calculate CRC over
/// - Returns: 16-bit CRC value
@inlinable
public func calculateModbusCRC16(_ bytes: ArraySlice<UInt8>) -> UInt16 {
    calculateModbusCRC16(bytes.span)
}

/// Verifies CRC of a complete Modbus frame (convenience overload for Array)
///
/// - Parameter frame: Complete Modbus RTU frame with CRC
/// - Returns: true if CRC is valid
@inlinable
public func verifyModbusCRC(_ frame: [UInt8]) -> Bool {
    verifyModbusCRC(frame.span)
}

/// Appends CRC to a Modbus frame (build phase, allocates new array)
///
/// - Parameter frame: Modbus frame without CRC
/// - Returns: Frame with CRC appended (low byte first)
@inlinable
public func appendModbusCRC(_ frame: [UInt8]) -> [UInt8] {
    let crc = calculateModbusCRC16(frame)
    return frame + [crcLowByte(crc), crcHighByte(crc)]
}
