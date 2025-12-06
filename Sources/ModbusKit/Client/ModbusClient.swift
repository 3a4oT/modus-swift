// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - ModbusClientLimits

/// Protocol limits per Modbus specification.
public enum ModbusClientLimits {
    /// Maximum registers per read request (per Modbus spec)
    public static let maxReadRegisters: UInt16 = 125

    /// Maximum registers per write request (per Modbus spec)
    /// Reference: pymodbus MODBUS_MAX_WRITE_REGISTERS = 123
    public static let maxWriteRegisters: UInt16 = 123

    /// Maximum frame size (per Modbus TCP spec)
    public static let maxFrameSize = MBAPConstants.maximumADUSize

    /// Minimum valid response size
    public static let minResponseSize = MBAPConstants.minimumADUSize
}

// MARK: - ModbusClient

/// Async Modbus client protocol.
///
/// API based on pymodbus `AsyncModbusTcpClient`:
/// - `connect()` / `close()` for connection lifecycle
/// - `readHoldingRegisters()` / `readInputRegisters()` for reading
/// - All operations use typed throws with `ModbusClientError`
///
/// Reference: pymodbus client module, goburrow/modbus TCPClient
public protocol ModbusClient: Sendable {
    /// Whether the client is currently connected.
    var isConnected: Bool { get }

    /// Connects to the Modbus device.
    ///
    /// - Throws: `ModbusClientError.connectionFailed` if connection fails
    /// - Throws: `ModbusClientError.timeout` if connection times out
    /// - Throws: `ModbusClientError.alreadyConnected` if already connected
    func connect() async throws(ModbusClientError)

    /// Closes the connection gracefully.
    ///
    /// Safe to call multiple times. Does nothing if not connected.
    func close() async

    /// Reads holding registers (Function Code 0x03).
    ///
    /// - Parameters:
    ///   - address: Starting register address (0-65535)
    ///   - count: Number of registers to read (1-125)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with register values
    /// - Throws: `ModbusClientError` on any failure
    func readHoldingRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse

    /// Reads input registers (Function Code 0x04).
    ///
    /// - Parameters:
    ///   - address: Starting register address (0-65535)
    ///   - count: Number of registers to read (1-125)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with register values
    /// - Throws: `ModbusClientError` on any failure
    func readInputRegisters(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse

    /// Writes a single register (Function Code 0x06).
    ///
    /// API based on pymodbus `write_register(address, value)`.
    ///
    /// - Parameters:
    ///   - address: Register address (0-65535)
    ///   - value: Value to write (0-65535)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response echoing address and value written
    /// - Throws: `ModbusClientError` on any failure
    func writeSingleRegister(
        address: UInt16,
        value: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse

    /// Writes multiple registers (Function Code 0x10).
    ///
    /// API based on pymodbus `write_registers(address, values)`.
    ///
    /// - Parameters:
    ///   - address: Starting register address (0-65535)
    ///   - values: Values to write (1-123 registers per Modbus spec)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response confirming address and quantity written
    /// - Throws: `ModbusClientError` on any failure
    func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse

    // MARK: - Coil Operations

    /// Reads coils (Function Code 0x01).
    ///
    /// API based on pymodbus `read_coils(address, count)`.
    ///
    /// - Parameters:
    ///   - address: Starting coil address (0-65535)
    ///   - count: Number of coils to read (1-2000)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with coil values
    /// - Throws: `ModbusClientError` on any failure
    func readCoils(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse

    /// Reads discrete inputs (Function Code 0x02).
    ///
    /// API based on pymodbus `read_discrete_inputs(address, count)`.
    ///
    /// - Parameters:
    ///   - address: Starting input address (0-65535)
    ///   - count: Number of inputs to read (1-2000)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with input values
    /// - Throws: `ModbusClientError` on any failure
    func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse

    /// Writes a single coil (Function Code 0x05).
    ///
    /// API based on pymodbus `write_coil(address, value)`.
    ///
    /// - Parameters:
    ///   - address: Coil address (0-65535)
    ///   - value: Value to write (true = ON, false = OFF)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response echoing address and value written
    /// - Throws: `ModbusClientError` on any failure
    func writeSingleCoil(
        address: UInt16,
        value: Bool,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse

    /// Writes multiple coils (Function Code 0x0F).
    ///
    /// API based on pymodbus `write_coils(address, values)`.
    ///
    /// - Parameters:
    ///   - address: Starting coil address (0-65535)
    ///   - values: Values to write (1-1968 coils per Modbus spec)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response confirming address and quantity written
    /// - Throws: `ModbusClientError` on any failure
    func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse

    // MARK: - Advanced Operations

    /// Mask write register (Function Code 0x16).
    ///
    /// Applies formula: `Result = (Current AND andMask) OR orMask`
    ///
    /// API based on pymodbus `mask_write_register(address, and_mask, or_mask)`.
    ///
    /// - Parameters:
    ///   - address: Register address (0-65535)
    ///   - andMask: AND mask for bitwise operation
    ///   - orMask: OR mask for bitwise operation
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response echoing address and masks
    /// - Throws: `ModbusClientError` on any failure
    func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse

    /// Read/write multiple registers (Function Code 0x17).
    ///
    /// Performs read and write in a single transaction.
    ///
    /// API based on pymodbus `readwrite_registers(read_address, read_count, write_address, write_registers)`.
    ///
    /// - Parameters:
    ///   - readAddress: Starting address for read
    ///   - readCount: Number of registers to read (1-125)
    ///   - writeAddress: Starting address for write
    ///   - writeValues: Values to write (1-121)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with read register values
    /// - Throws: `ModbusClientError` on any failure
    func readWriteMultipleRegisters(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse

    /// Read FIFO queue (Function Code 0x18).
    ///
    /// Reads up to 31 registers from FIFO queue.
    ///
    /// API based on goburrow/modbus `ReadFIFOQueue`.
    ///
    /// - Parameters:
    ///   - address: FIFO pointer address (0-65535)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with FIFO count and register values
    /// - Throws: `ModbusClientError` on any failure
    func readFIFOQueue(
        address: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse
}
