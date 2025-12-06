// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - HoldingRegisterTestData

/// Test data provider for Holding Registers (FC 0x03, 0x06, 0x10).
///
/// Pattern: sequential values = address + 1
/// - Address 0: value 1
/// - Address 1: value 2
/// - Address N: value N + 1
///
/// Note: pymodbus uses 1-based internal indexing, so the server
/// data `list(range(1000))` results in address 0 returning 1.
enum HoldingRegisterTestData: ReferenceTestDataProvider {
    /// Address space size configured in reference server.
    static let addressCount: UInt16 = 1000

    /// Maximum registers readable in single FC 0x03 request.
    static let maxReadCount: UInt16 = 125

    /// Maximum registers writable in single FC 0x10 request.
    static let maxWriteCount: UInt16 = 123

    /// Returns expected holding register value at address.
    ///
    /// - Parameter address: Holding register address (0-999)
    /// - Returns: Value equal to address + 1 (pymodbus 1-based indexing)
    static func value(at address: UInt16) -> UInt16 {
        address + 1
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
