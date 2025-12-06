// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ModbusFunctionCode

/// Modbus function codes.
///
/// Reference: Modbus Application Protocol Specification V1.1b3
/// Verified against: pymodbus, libmodbus, goburrow/modbus
public enum ModbusFunctionCode {
    /// Read Coils (FC 01)
    public static let readCoils: UInt8 = 0x01
    /// Read Discrete Inputs (FC 02)
    public static let readDiscreteInputs: UInt8 = 0x02
    /// Read Holding Registers (FC 03)
    public static let readHoldingRegisters: UInt8 = 0x03
    /// Read Input Registers (FC 04)
    public static let readInputRegisters: UInt8 = 0x04
    /// Write Single Coil (FC 05)
    public static let writeSingleCoil: UInt8 = 0x05
    /// Write Single Register (FC 06)
    public static let writeSingleRegister: UInt8 = 0x06
    /// Read Exception Status (FC 07) — Serial Line only
    public static let readExceptionStatus: UInt8 = 0x07
    /// Diagnostics (FC 08) — Serial Line only
    public static let diagnostics: UInt8 = 0x08
    /// Get Comm Event Counter (FC 11) — Serial Line only
    public static let getCommEventCounter: UInt8 = 0x0B
    /// Get Comm Event Log (FC 12) — Serial Line only
    public static let getCommEventLog: UInt8 = 0x0C
    /// Write Multiple Coils (FC 15)
    public static let writeMultipleCoils: UInt8 = 0x0F
    /// Write Multiple Registers (FC 16)
    public static let writeMultipleRegisters: UInt8 = 0x10
    /// Report Server ID (FC 17) — Serial Line only
    public static let reportServerId: UInt8 = 0x11
    /// Mask Write Register (FC 22)
    public static let maskWriteRegister: UInt8 = 0x16
    /// Read/Write Multiple Registers (FC 23)
    public static let readWriteMultipleRegisters: UInt8 = 0x17
    /// Read FIFO Queue (FC 24)
    public static let readFIFOQueue: UInt8 = 0x18

    /// Read File Record (FC 20)
    public static let readFileRecord: UInt8 = 0x14
    /// Write File Record (FC 21)
    public static let writeFileRecord: UInt8 = 0x15

    /// Encapsulated Interface Transport (FC 43) — MEI
    public static let encapsulatedInterface: UInt8 = 0x2B

    /// Exception response flag (added to function code)
    public static let exceptionFlag: UInt8 = 0x80
}
