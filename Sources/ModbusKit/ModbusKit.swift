// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// Re-export ModbusCore so consumers get binary helpers, CRC, etc.
@_exported import ModbusCore

// MARK: - ModbusKit

/// Pure Modbus TCP implementation.
///
/// This module provides:
/// - MBAP header construction and parsing
/// - PDU builder/parser (0x03, 0x04, etc.)
/// - Async/await client with SwiftNIO
/// - Register decoding helpers (UInt16, Int32, Float32)
/// - Word order configuration
///
/// **No domain knowledge** — can be used for any Modbus device:
/// PLC, HVAC, energy meters, BMS, industrial sensors, smart-home.
public enum ModbusKit {}
