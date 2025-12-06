// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - ModbusCore

/// Modbus protocol primitives with zero dependencies.
///
/// This module provides:
/// - CRC-16/MODBUS checksum calculation
/// - LRC checksum for ASCII mode
/// - Binary parsing helpers (safe bounds-checked)
/// - PDU builders/parsers for all standard function codes (0x01-0x18)
/// - MBAP header handling (TCP framing)
/// - RTU framing for Serial transport
/// - ASCII framing for Serial transport
/// - Word order decoding for multi-register values
///
/// **Zero Dependencies** — pure Swift, no external packages required.
public enum ModbusCore {}
