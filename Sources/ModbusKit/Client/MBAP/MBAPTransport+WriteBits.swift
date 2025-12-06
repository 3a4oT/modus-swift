// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Write Bits (FC 0x05, 0x0F)

/// Write Single Coil (FC 0x05) and Write Multiple Coils (FC 0x0F) implementation.
///
/// ## Function Code 0x05 - Write Single Coil
///
/// Writes a single coil (1-bit output) to ON or OFF state.
/// - ON state: value `0xFF00`
/// - OFF state: value `0x0000`
///
/// ## Function Code 0x0F - Write Multiple Coils
///
/// Writes a contiguous block of coils (1-1968 coils).
/// Coils are packed as bits, LSB first within each byte.
///
/// ## Broadcast Support
///
/// Both functions support broadcast (unitId = 0). In broadcast mode,
/// no response is expected from devices.
///
/// ## Limits
///
/// - FC 0x05: Single coil only
/// - FC 0x0F: Maximum 1968 coils per request (0x7B0)
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.5 (FC 0x05)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.11 (FC 0x0F)
extension MBAPTransport {
    // MARK: Internal

    // MARK: - Write Single Coil (FC 0x05)

    /// Sends a write single coil request with automatic retry.
    ///
    /// - Parameters:
    ///   - address: Coil address (0x0000-0xFFFF)
    ///   - value: `true` for ON (0xFF00), `false` for OFF (0x0000)
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response echoing address and value written
    /// - Throws: `ModbusClientError` on failure
    func sendWriteSingleCoilRequest(
        address: UInt16,
        value: Bool,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performWriteSingleCoilRequest(
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

    // MARK: - Write Multiple Coils (FC 0x0F)

    /// Sends a write multiple coils request with automatic retry.
    ///
    /// - Parameters:
    ///   - address: Starting coil address (0x0000-0xFFFF)
    ///   - values: Array of boolean values to write (1-1968 values)
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response with starting address and quantity written
    /// - Throws: `ModbusClientError` on failure
    func sendWriteMultipleCoilsRequest(
        address: UInt16,
        values: [Bool],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performWriteMultipleCoilsRequest(
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

    /// Performs a single write single coil attempt.
    private func performWriteSingleCoilRequest(
        address: UInt16,
        value: Bool,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteSingleCoilResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildWriteSingleCoilPDU(address: address, value: value)
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
            return WriteSingleCoilResponse(address: address, value: value)
        }

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseWriteSingleCoilResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses write single coil response.
    private func parseWriteSingleCoilResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> WriteSingleCoilResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseWriteSingleCoilPDU(pdu)
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

    /// Performs a single write multiple coils attempt.
    private func performWriteMultipleCoilsRequest(
        address: UInt16,
        values: [Bool],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildWriteMultipleCoilsPDU(address: address, values: values)
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
            return WriteMultipleCoilsResponse(address: address, quantity: UInt16(values.count))
        }

        // Send request and wait for response (handles both serial and pipelining modes)
        let responseBytes = try await sendRequest(
            channel: ch,
            data: buffer,
            transactionId: transactionId,
        )
        logger?.trace("RX: \(responseBytes.hexString)")

        return try parseWriteMultipleCoilsResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses write multiple coils response.
    private func parseWriteMultipleCoilsResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> WriteMultipleCoilsResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseWriteMultipleCoilsPDU(pdu)
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
