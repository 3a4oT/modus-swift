// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Default Parameters Extension

extension ModbusClient {
    /// Reads holding registers with default unit ID (1).
    @inlinable
    public func readHoldingRegisters(
        address: UInt16,
        count: UInt16,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try await readHoldingRegisters(address: address, count: count, unitId: 1)
    }

    /// Reads input registers with default unit ID (1).
    @inlinable
    public func readInputRegisters(
        address: UInt16,
        count: UInt16,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try await readInputRegisters(address: address, count: count, unitId: 1)
    }

    /// Writes a single register with default unit ID (1).
    @inlinable
    public func writeSingleRegister(
        address: UInt16,
        value: UInt16,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse {
        try await writeSingleRegister(address: address, value: value, unitId: 1)
    }

    /// Writes multiple registers with default unit ID (1).
    @inlinable
    public func writeMultipleRegisters(
        address: UInt16,
        values: [UInt16],
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        try await writeMultipleRegisters(address: address, values: values, unitId: 1)
    }

    // MARK: - Coil Operations Default Parameters

    /// Reads coils with default unit ID (1).
    @inlinable
    public func readCoils(
        address: UInt16,
        count: UInt16,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try await readCoils(address: address, count: count, unitId: 1)
    }

    /// Reads discrete inputs with default unit ID (1).
    @inlinable
    public func readDiscreteInputs(
        address: UInt16,
        count: UInt16,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try await readDiscreteInputs(address: address, count: count, unitId: 1)
    }

    /// Writes a single coil with default unit ID (1).
    @inlinable
    public func writeSingleCoil(
        address: UInt16,
        value: Bool,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse {
        try await writeSingleCoil(address: address, value: value, unitId: 1)
    }

    /// Writes multiple coils with default unit ID (1).
    @inlinable
    public func writeMultipleCoils(
        address: UInt16,
        values: [Bool],
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        try await writeMultipleCoils(address: address, values: values, unitId: 1)
    }

    // MARK: - Advanced Operations Default Parameters

    /// Mask write register with default unit ID (1).
    @inlinable
    public func maskWriteRegister(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse {
        try await maskWriteRegister(address: address, andMask: andMask, orMask: orMask, unitId: 1)
    }

    /// Read/write multiple registers with default unit ID (1).
    @inlinable
    public func readWriteMultipleRegisters(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
    ) async throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse {
        try await readWriteMultipleRegisters(
            readAddress: readAddress,
            readCount: readCount,
            writeAddress: writeAddress,
            writeValues: writeValues,
            unitId: 1,
        )
    }

    /// Read FIFO queue with default unit ID (1).
    @inlinable
    public func readFIFOQueue(
        address: UInt16,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse {
        try await readFIFOQueue(address: address, unitId: 1)
    }
}
