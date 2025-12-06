// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Parameter Validation

/// Validates read request parameters.
///
/// - Parameters:
///   - count: Number of registers
/// - Throws: `ModbusClientError.invalidParameter` if validation fails
@inlinable
func validateReadParameters(count: UInt16) throws(ModbusClientError) {
    guard count >= 1 else {
        throw .invalidParameter("count must be >= 1")
    }
    guard count <= ModbusClientLimits.maxReadRegisters else {
        throw .invalidParameter("count must be <= \(ModbusClientLimits.maxReadRegisters)")
    }
}

/// Validates write multiple registers parameters.
///
/// - Parameters:
///   - values: Values to write
/// - Throws: `ModbusClientError.invalidParameter` if validation fails
@inlinable
func validateWriteParameters(values: [UInt16]) throws(ModbusClientError) {
    guard !values.isEmpty else {
        throw .invalidParameter("values must not be empty")
    }
    guard values.count <= ModbusClientLimits.maxWriteRegisters else {
        throw .invalidParameter("values count must be <= \(ModbusClientLimits.maxWriteRegisters)")
    }
}

// MARK: - Coil Validation

/// Validates read coils/discrete inputs parameters.
///
/// - Parameters:
///   - count: Number of coils/inputs
/// - Throws: `ModbusClientError.invalidParameter` if validation fails
@inlinable
func validateReadCoilsParameters(count: UInt16) throws(ModbusClientError) {
    guard count >= 1 else {
        throw .invalidParameter("count must be >= 1")
    }
    guard count <= ModbusLimits.maxReadCoils else {
        throw .invalidParameter("count must be <= \(ModbusLimits.maxReadCoils)")
    }
}

/// Validates write multiple coils parameters.
///
/// - Parameters:
///   - values: Values to write
/// - Throws: `ModbusClientError.invalidParameter` if validation fails
@inlinable
func validateWriteCoilsParameters(values: [Bool]) throws(ModbusClientError) {
    guard !values.isEmpty else {
        throw .invalidParameter("values must not be empty")
    }
    guard values.count <= ModbusLimits.maxWriteCoils else {
        throw .invalidParameter("values count must be <= \(ModbusLimits.maxWriteCoils)")
    }
}

// MARK: - Advanced Operations Validation

/// Validates read/write multiple registers write parameters.
///
/// FC 0x17 allows max 121 write registers (vs 123 for FC 0x10).
///
/// - Parameters:
///   - values: Values to write
/// - Throws: `ModbusClientError.invalidParameter` if validation fails
@inlinable
func validateReadWriteWriteParameters(values: [UInt16]) throws(ModbusClientError) {
    guard !values.isEmpty else {
        throw .invalidParameter("write values must not be empty")
    }
    guard values.count <= ModbusLimits.maxReadWriteWriteRegisters else {
        throw .invalidParameter("write values count must be <= \(ModbusLimits.maxReadWriteWriteRegisters)")
    }
}
