// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Modbus LRC (Longitudinal Redundancy Check)

/// Calculates LRC checksum for Modbus ASCII mode.
///
/// Algorithm (per Modbus Serial Line Protocol V1.02, Section 2.5.1.2):
/// 1. Sum all bytes in the message (excluding start colon and end CR LF)
/// 2. Return two's complement of the least significant byte
///
/// The checksum ensures that sum of all message bytes plus LRC equals zero.
///
/// Reference: libmodbus `lcr8()` implementation
///
/// - Parameter bytes: Message bytes (address + function + data, NOT including ':' or CR LF)
/// - Returns: 8-bit LRC checksum
@inlinable
public func calculateModbusLRC(_ bytes: Span<UInt8>) -> UInt8 {
    var sum: UInt8 = 0
    for i in bytes.indices {
        sum &+= bytes[i]
    }
    // Two's complement: -sum is equivalent to (~sum &+ 1)
    return 0 &- sum
}

// MARK: - LRC Verification

/// Verifies LRC of a Modbus ASCII message (binary form, before hex encoding).
///
/// The message should include all bytes from address through LRC.
/// Verification: sum of all bytes (including LRC) should equal zero.
///
/// - Parameter message: Complete message bytes including LRC at end
/// - Returns: true if LRC is valid (sum equals zero)
@inlinable
public func verifyModbusLRC(_ message: Span<UInt8>) -> Bool {
    guard message.count >= 2 else {
        return false
    }

    var sum: UInt8 = 0
    for i in message.indices {
        sum &+= message[i]
    }

    // Valid if sum equals zero
    return sum == 0
}

// MARK: - Convenience API (Build Phase - Array)

/// Calculates LRC checksum (convenience overload for Array).
///
/// - Parameter bytes: Message bytes
/// - Returns: 8-bit LRC checksum
@inlinable
public func calculateModbusLRC(_ bytes: [UInt8]) -> UInt8 {
    calculateModbusLRC(bytes.span)
}

/// Verifies LRC of a message (convenience overload for Array).
///
/// - Parameter message: Complete message bytes including LRC
/// - Returns: true if LRC is valid
@inlinable
public func verifyModbusLRC(_ message: [UInt8]) -> Bool {
    verifyModbusLRC(message.span)
}

/// Appends LRC to a Modbus ASCII message (build phase).
///
/// - Parameter message: Message bytes (address + function + data)
/// - Returns: Message with LRC appended
@inlinable
public func appendModbusLRC(_ message: [UInt8]) -> [UInt8] {
    let lrc = calculateModbusLRC(message)
    return message + [lrc]
}
