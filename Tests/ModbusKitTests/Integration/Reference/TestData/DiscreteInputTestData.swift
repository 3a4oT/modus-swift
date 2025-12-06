// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - DiscreteInputTestData

/// Test data provider for Discrete Inputs (FC 0x02).
///
/// Pattern: first 99 addresses True, rest False (pymodbus 1-based offset)
/// - Addresses 0-98: True
/// - Addresses 99+: False
///
/// Note: pymodbus uses 1-based internal indexing, so the server
/// data `[i < 100 for i in range(1000)]` results in address 0 returning index 1's value.
enum DiscreteInputTestData: ReferenceTestDataProvider {
    /// Address space size configured in reference server.
    static let addressCount: UInt16 = 1000

    /// Boundary address where values change from True to False (adjusted for 1-based indexing).
    static let trueBoundary: UInt16 = 99

    /// Returns expected discrete input value at address.
    ///
    /// - Parameter address: Discrete input address (0-999)
    /// - Returns: True for addresses 0-98, False for 99+ (1-based offset)
    static func value(at address: UInt16) -> Bool {
        address < trueBoundary
    }

    /// Generates expected discrete input values as bit array.
    ///
    /// - Parameters:
    ///   - address: Starting address
    ///   - count: Number of discrete inputs
    /// - Returns: Array of boolean values
    static func bitValues(startingAt address: UInt16, count: UInt16) -> [Bool] {
        values(startingAt: address, count: count)
    }
}
