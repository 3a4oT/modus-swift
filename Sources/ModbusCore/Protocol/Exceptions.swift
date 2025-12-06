// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ModbusException

/// Modbus exception codes.
///
/// Reference: Modbus Application Protocol Specification V1.1b3
/// Verified against: pymodbus exceptions
public enum ModbusException: UInt8, Error, Equatable, Sendable {
    /// Function code not supported
    case illegalFunction = 0x01
    /// Invalid register address
    case illegalDataAddress = 0x02
    /// Invalid register value
    case illegalDataValue = 0x03
    /// Slave device failure
    case slaveDeviceFailure = 0x04
    /// Request acknowledged, processing
    case acknowledge = 0x05
    /// Slave busy, retry later
    case slaveDeviceBusy = 0x06
    /// Memory parity error
    case memoryParityError = 0x08
    /// Gateway path unavailable
    case gatewayPathUnavailable = 0x0A
    /// Gateway target device failed to respond
    case gatewayTargetDeviceFailed = 0x0B
}
