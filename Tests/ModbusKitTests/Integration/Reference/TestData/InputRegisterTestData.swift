// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - InputRegisterTestData

/// Test data provider for Input Registers (FC 0x04).
///
/// Pattern: value = (address + 1) * 10
/// - Address 0: value 10
/// - Address 1: value 20
/// - Address 5: value 60
/// - Address N: value (N + 1) * 10
///
/// Note: pymodbus uses 1-based internal indexing, so the server
/// data `[i * 10 for i in range(1000)]` results in address 0 returning 10.
enum InputRegisterTestData: ReferenceTestDataProvider {
    /// Address space size configured in reference server.
    static let addressCount: UInt16 = 1000

    /// Maximum registers readable in single FC 0x04 request.
    static let maxReadCount: UInt16 = 125

    /// Multiplier applied to address to get value.
    static let multiplier: UInt16 = 10

    /// Returns expected input register value at address.
    ///
    /// - Parameter address: Input register address (0-999)
    /// - Returns: Value equal to (address + 1) * 10 (pymodbus 1-based indexing)
    static func value(at address: UInt16) -> UInt16 {
        (address + 1) * multiplier
    }

    /// Generates expected register values for validation.
    ///
    /// - Parameters:
    ///   - address: Starting address
    ///   - count: Number of registers
    /// - Returns: Array of UInt16 values
    static func registerValues(startingAt address: UInt16, count: UInt16) -> [UInt16] {
        values(startingAt: address, count: count)
    }
}
