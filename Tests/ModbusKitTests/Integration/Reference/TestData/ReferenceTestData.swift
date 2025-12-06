// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ReferenceTestDataProvider

/// Protocol for reference test data providers.
///
/// Each provider generates expected values for a specific Modbus data type,
/// matching the patterns defined in Scripts/reference_server.py.
protocol ReferenceTestDataProvider {
    associatedtype Value

    /// Returns the expected value at the given address.
    static func value(at address: UInt16) -> Value

    /// Returns expected values for a range starting at address.
    static func values(startingAt address: UInt16, count: UInt16) -> [Value]
}

extension ReferenceTestDataProvider {
    static func values(startingAt address: UInt16, count: UInt16) -> [Value] {
        (0 ..< count).map { value(at: address + $0) }
    }
}

// MARK: - ReferenceTestData

/// Namespace for reference server test data patterns.
///
/// The pymodbus reference server provides predictable data patterns
/// for each Modbus data type. Use these providers to generate expected
/// values for validation tests.
///
/// Data patterns match Scripts/reference_server.py:
/// - Coils: alternating True/False (even addresses = True)
/// - Discrete Inputs: first 100 True, rest False
/// - Holding Registers: sequential 0, 1, 2, ...
/// - Input Registers: value = address * 10
enum ReferenceTestData {
    typealias Coils = CoilTestData
    typealias DiscreteInputs = DiscreteInputTestData
    typealias HoldingRegisters = HoldingRegisterTestData
    typealias InputRegisters = InputRegisterTestData
}
