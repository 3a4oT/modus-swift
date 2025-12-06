// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - CoilTestData

/// Test data provider for Coils (FC 0x01, 0x05, 0x0F).
///
/// Pattern: alternating False/True (pymodbus 1-based offset)
/// - Even addresses (0, 2, 4, ...): False
/// - Odd addresses (1, 3, 5, ...): True
///
/// Note: pymodbus uses 1-based internal indexing, so the server
/// data `[i % 2 == 0 for i in range(1000)]` results in address 0 returning False.
enum CoilTestData: ReferenceTestDataProvider {
    /// Address space size configured in reference server.
    static let addressCount: UInt16 = 1000

    /// Returns expected coil value at address.
    ///
    /// - Parameter address: Coil address (0-999)
    /// - Returns: False for even addresses, True for odd (1-based offset)
    static func value(at address: UInt16) -> Bool {
        (address + 1) % 2 == 0
    }

    /// Generates expected coil values as bit array.
    ///
    /// Useful for validating FC 0x01 responses where coils
    /// are packed into bytes.
    ///
    /// - Parameters:
    ///   - address: Starting address
    ///   - count: Number of coils
    /// - Returns: Array of boolean values
    static func bitValues(startingAt address: UInt16, count: UInt16) -> [Bool] {
        values(startingAt: address, count: count)
    }
}
