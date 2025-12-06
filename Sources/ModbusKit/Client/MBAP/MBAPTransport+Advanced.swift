// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Advanced Operations (FC 0x16, 0x17, 0x18)

/// Mask Write Register (FC 0x16), Read/Write Multiple Registers (FC 0x17),
/// and Read FIFO Queue (FC 0x18) implementation.
///
/// ## Function Code 0x16 - Mask Write Register
///
/// Modifies a single register using AND and OR masks:
/// ```
/// Result = (Current AND And_Mask) OR (Or_Mask AND (NOT And_Mask))
/// ```
///
/// Use cases:
/// - Set specific bits: `andMask = 0xFFFF, orMask = bits_to_set`
/// - Clear specific bits: `andMask = ~bits_to_clear, orMask = 0x0000`
/// - Toggle specific bits: Requires read-modify-write
///
/// ## Function Code 0x17 - Read/Write Multiple Registers
///
/// Performs a write operation followed by a read operation in a single
/// Modbus transaction. Useful for atomic read-modify-write operations.
///
/// ## Function Code 0x18 - Read FIFO Queue
///
/// Reads the contents of a First-In-First-Out (FIFO) queue.
/// Returns the count of registers in the queue followed by the values.
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.16 (FC 0x16)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.17 (FC 0x17)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.18 (FC 0x18)
extension MBAPTransport {
    // MARK: Internal

    // MARK: - Mask Write Register (FC 0x16)

    /// Sends a mask write register request with automatic retry.
    ///
    /// Modifies a register using the formula:
    /// `Result = (Current AND andMask) OR (orMask AND (NOT andMask))`
    ///
    /// - Parameters:
    ///   - address: Register address (0x0000-0xFFFF)
    ///   - andMask: 16-bit AND mask
    ///   - orMask: 16-bit OR mask
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response echoing address and masks
    /// - Throws: `ModbusClientError` on failure
    func sendMaskWriteRegisterRequest(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performMaskWriteRegisterRequest(
                    address: address,
                    andMask: andMask,
                    orMask: orMask,
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

    // MARK: - Read/Write Multiple Registers (FC 0x17)

    /// Sends a read/write multiple registers request with automatic retry.
    ///
    /// Atomically writes to one range and reads from another in a single transaction.
    ///
    /// - Parameters:
    ///   - readAddress: Starting address for read operation
    ///   - readCount: Number of registers to read (1-125)
    ///   - writeAddress: Starting address for write operation
    ///   - writeValues: Values to write (1-121 registers)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response containing read register values
    /// - Throws: `ModbusClientError` on failure
    func sendReadWriteMultipleRegistersRequest(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performReadWriteMultipleRegistersRequest(
                    readAddress: readAddress,
                    readCount: readCount,
                    writeAddress: writeAddress,
                    writeValues: writeValues,
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

    // MARK: - Read FIFO Queue (FC 0x18)

    /// Sends a read FIFO queue request with automatic retry.
    ///
    /// Reads the contents of a FIFO queue of holding registers.
    /// The response includes the count and values of registers in the queue.
    ///
    /// - Parameters:
    ///   - address: FIFO pointer address (0x0000-0xFFFF)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response containing FIFO queue values
    /// - Throws: `ModbusClientError` on failure
    func sendReadFIFOQueueRequest(
        address: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performReadFIFOQueueRequest(address: address, unitId: unitId)
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

    /// Performs a single mask write register attempt.
    private func performMaskWriteRegisterRequest(
        address: UInt16,
        andMask: UInt16,
        orMask: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> MaskWriteRegisterResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildMaskWriteRegisterPDU(address: address, andMask: andMask, orMask: orMask)
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
            return MaskWriteRegisterResponse(address: address, andMask: andMask, orMask: orMask)
        }

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseMaskWriteRegisterResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses mask write register response.
    private func parseMaskWriteRegisterResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> MaskWriteRegisterResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseMaskWriteRegisterPDU(pdu)
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

    /// Performs a single read/write multiple registers attempt.
    private func performReadWriteMultipleRegistersRequest(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildReadWriteMultipleRegistersPDU(
            readAddress: readAddress,
            readCount: readCount,
            writeAddress: writeAddress,
            writeValues: writeValues,
        )
        let adu = buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)

        var buffer = ch.allocator.buffer(capacity: adu.count)
        buffer.writeBytes(adu)
        logger?.trace("TX: \(adu.hexString)")

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseReadWriteMultipleRegistersResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses read/write multiple registers response.
    private func parseReadWriteMultipleRegistersResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> ReadWriteMultipleRegistersResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseReadWriteMultipleRegistersPDU(pdu)
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

    /// Performs a single read FIFO queue attempt.
    private func performReadFIFOQueueRequest(
        address: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFIFOQueueResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildReadFIFOQueuePDU(address: address)
        let adu = buildModbusTCPADU(transactionId: transactionId, unitId: unitId, pdu: pdu)

        var buffer = ch.allocator.buffer(capacity: adu.count)
        buffer.writeBytes(adu)
        logger?.trace("TX: \(adu.hexString)")

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseReadFIFOQueueResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses read FIFO queue response.
    private func parseReadFIFOQueueResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> ReadFIFOQueueResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseReadFIFOQueuePDU(pdu)
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
