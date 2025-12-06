// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Write Registers (FC 0x06, 0x10)

/// Write Single Register (FC 0x06) and Write Multiple Registers (FC 0x10) implementation.
///
/// ## Function Code 0x06 - Write Single Register
///
/// Writes a single 16-bit value to a holding register.
/// The response echoes the address and value written.
///
/// ## Function Code 0x10 - Write Multiple Registers
///
/// Writes a contiguous block of registers (1-123 registers).
/// The response contains the starting address and quantity written.
///
/// ## Broadcast Support
///
/// Both functions support broadcast (unitId = 0). In broadcast mode,
/// no response is expected from devices.
///
/// ## Limits
///
/// - FC 0x06: Single register only
/// - FC 0x10: Maximum 123 registers per request
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.6 (FC 0x06)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.12 (FC 0x10)
extension MBAPTransport {
    // MARK: Internal

    // MARK: - Write Single Register (FC 0x06)

    /// Sends a write single register request with automatic retry.
    ///
    /// - Parameters:
    ///   - address: Register address (0x0000-0xFFFF)
    ///   - value: 16-bit value to write
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response echoing address and value written
    /// - Throws: `ModbusClientError` on failure
    func sendWriteSingleRegisterRequest(
        address: UInt16,
        value: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performWriteSingleRegisterRequest(
                    address: address,
                    value: value,
                    unitId: unitId,
                )
            } catch {
                lastError = error
                guard error.isRetryable else {
                    throw error
                }
                guard attempt < maxAttempts else {
                    break
                }
            }
        }

        throw lastError ?? .connectionFailed("All retry attempts failed")
    }

    // MARK: - Write Multiple Registers (FC 0x10)

    /// Sends a write multiple registers request with automatic retry.
    ///
    /// - Parameters:
    ///   - address: Starting register address (0x0000-0xFFFF)
    ///   - values: Array of 16-bit values to write (1-123 values)
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response with starting address and quantity written
    /// - Throws: `ModbusClientError` on failure
    func sendWriteMultipleRegistersRequest(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performWriteMultipleRegistersRequest(
                    address: address,
                    values: values,
                    unitId: unitId,
                )
            } catch {
                lastError = error
                guard error.isRetryable else {
                    throw error
                }
                guard attempt < maxAttempts else {
                    break
                }
            }
        }

        throw lastError ?? .connectionFailed("All retry attempts failed")
    }

    // MARK: Private

    /// Performs a single write single register attempt.
    private func performWriteSingleRegisterRequest(
        address: UInt16,
        value: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleRegisterResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildWriteSingleRegisterPDU(address: address, value: value)
        let adu = buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)

        var buffer = ch.allocator.buffer(capacity: adu.count)
        buffer.writeBytes(adu)
        logger?.trace("TX: \(adu.hexString)")

        // Broadcast: no response expected (Modbus spec section 4.1.1)
        if unitId == ModbusAddress.broadcast {
            do {
                try await ch.writeAndFlush(buffer)
                recordActivity()
            } catch {
                throw .ioError("Write failed: \(error)")
            }
            return WriteSingleRegisterResponse(address: address, value: value)
        }

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseWriteSingleRegisterResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses write single register response.
    private func parseWriteSingleRegisterResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> WriteSingleRegisterResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseWriteSingleRegisterPDU(pdu)
        } catch let error as MBAPError {
            throw mapMBAPError(error)
        } catch let error as PDUError {
            throw mapPDUError(error)
        } catch let error as ModbusClientError {
            throw error
        } catch {
            throw .ioError("\(error)")
        }
    }

    /// Performs a single write multiple registers attempt.
    private func performWriteMultipleRegistersRequest(
        address: UInt16,
        values: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildWriteMultipleRegistersPDU(address: address, values: values)
        let adu = buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)

        var buffer = ch.allocator.buffer(capacity: adu.count)
        buffer.writeBytes(adu)
        logger?.trace("TX: \(adu.hexString)")

        // Broadcast: no response expected (Modbus spec section 4.1.1)
        if unitId == ModbusAddress.broadcast {
            do {
                try await ch.writeAndFlush(buffer)
                recordActivity()
            } catch {
                throw .ioError("Write failed: \(error)")
            }
            return WriteMultipleRegistersResponse(address: address, quantity: UInt16(values.count))
        }

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseWriteMultipleRegistersResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses write multiple registers response.
    private func parseWriteMultipleRegistersResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> WriteMultipleRegistersResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseWriteMultipleRegistersPDU(pdu)
        } catch let error as MBAPError {
            throw mapMBAPError(error)
        } catch let error as PDUError {
            throw mapPDUError(error)
        } catch let error as ModbusClientError {
            throw error
        } catch {
            throw .ioError("\(error)")
        }
    }
}
