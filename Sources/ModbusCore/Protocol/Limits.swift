// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - PDUSize

/// PDU size constants.
///
/// Verified against:
/// - pymodbus: MIN_SIZE calculations
/// - libmodbus: _MIN_REQ_LENGTH definitions
public enum PDUSize {
    /// Read request PDU size: func(1) + addr(2) + count(2) = 5
    public static let readRequest = 5

    /// Minimum read response PDU size: func(1) + byteCount(1) = 2
    public static let minimumReadResponse = 2

    /// Exception response PDU size: func(1) + code(1) = 2
    public static let exceptionResponse = 2

    /// Write single register request/response: func(1) + addr(2) + value(2) = 5
    public static let writeSingleRegister = 5

    /// Write multiple registers response: func(1) + addr(2) + quantity(2) = 5
    public static let writeMultipleRegistersResponse = 5

    /// Write multiple registers request header: func(1) + addr(2) + quantity(2) + byteCount(1) = 6
    public static let writeMultipleRegistersRequestHeader = 6

    /// Mask write register request/response: func(1) + addr(2) + andMask(2) + orMask(2) = 7
    public static let maskWriteRegister = 7

    /// Read FIFO queue request: func(1) + addr(2) = 3
    public static let readFIFOQueueRequest = 3

    /// Device Identification request: func(1) + mei(1) + readCode(1) + objId(1) = 4
    public static let deviceIdentificationRequest = 4

    /// Device Identification minimum response: func(1) + mei(1) + readCode(1) +
    /// conformity(1) + moreFollows(1) + nextObjId(1) + numObjects(1) = 7
    public static let deviceIdentificationMinResponse = 7
}

// MARK: - ModbusAddress

/// Special Modbus addresses.
///
/// Per Modbus Application Protocol Specification V1.1b3
public enum ModbusAddress {
    /// Broadcast address — all slaves process request, none respond.
    ///
    /// **Usage:** Only for write operations (FC 0x05, 0x06, 0x0F, 0x10).
    /// Read operations with broadcast address are invalid (no response expected).
    ///
    /// Reference: Modbus spec section 4.1.1
    public static let broadcast: UInt8 = 0
}

// MARK: - ModbusLimits

/// Protocol limits for Modbus operations.
///
/// Per Modbus Application Protocol Specification V1.1b3
public enum ModbusLimits {
    /// Maximum coils per read request (per Modbus spec: 0x07D0 = 2000)
    public static let maxReadCoils: UInt16 = 2000
    /// Maximum coils per write multiple request (per Modbus spec: 0x07B0 = 1968)
    public static let maxWriteCoils: UInt16 = 1968
    /// Maximum registers per write multiple request (per Modbus spec: 0x007B = 123)
    public static let maxWriteRegisters: UInt16 = 123
    /// Maximum registers per read request (per Modbus spec: 0x007D = 125)
    public static let maxReadRegisters: UInt16 = 125
    /// Maximum registers for read/write operation write part (per Modbus spec: 0x0079 = 121)
    public static let maxReadWriteWriteRegisters: UInt16 = 121
    /// Maximum FIFO count (per Modbus spec: 31)
    public static let maxFIFOCount: UInt16 = 31
}

// MARK: - Coil Constants

/// Value for coil ON state (0xFF00 per Modbus spec)
public let CoilOn: UInt16 = 0xFF00

/// Value for coil OFF state (0x0000 per Modbus spec)
public let CoilOff: UInt16 = 0x0000
