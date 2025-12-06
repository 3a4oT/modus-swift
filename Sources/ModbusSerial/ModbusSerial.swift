// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

#if !os(macOS) && !os(Linux) && !os(Android)
    #error("ModbusSerial is only available on macOS, Linux, and Android")
#endif

// ModbusSerial — Serial RTU transport for Modbus protocol.
//
// This module provides native RS-485/RS-232 Modbus RTU support using POSIX termios.
// No SwiftNIO dependency — suitable for embedded and resource-constrained environments.
//
// ## Quick Start
//
// ```swift
// import ModbusSerial
//
// let client = ModbusRTUClient(
//     port: "/dev/ttyUSB0",
//     baudRate: 9600,
//     parity: .none
// )
//
// try await client.connect()
// let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
// await client.close()
// ```
//
// ## Architecture
//
// ```
// ModbusSerial/
// ├── Port/           # Serial port abstraction
// │   ├── SerialPort.swift           # Protocol
// │   ├── SerialConfiguration.swift  # Configuration
// │   └── POSIXSerialPort.swift      # termios implementation
// ├── Client/
// │   └── ModbusRTUClient.swift      # Async RTU client
// └── Transport/
//     └── RTUTiming.swift            # T1.5/T3.5 timing
// ```

@_exported import ModbusCore
