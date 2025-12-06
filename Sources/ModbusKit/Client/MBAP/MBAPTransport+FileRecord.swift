// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - File Record Operations (FC 0x14, 0x15)

/// Read File Record (FC 0x14) and Write File Record (FC 0x15) implementation.
///
/// ## Function Code 0x14 - Read File Record
///
/// Reads records from extended memory files. Each sub-request specifies:
/// - File number (0x0000-0xFFFF)
/// - Record number (0x0000-0x270F)
/// - Record length in registers
///
/// ## Function Code 0x15 - Write File Record
///
/// Writes records to extended memory files. The response echoes the request.
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.14 (FC 0x14)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.15 (FC 0x15)
/// - pymodbus `ReadFileRecordRequest`, `WriteFileRecordRequest`
extension MBAPTransport {
    // MARK: Internal

    // MARK: - Read File Record (FC 0x14)

    /// Sends a read file record request with automatic retry.
    ///
    /// - Parameters:
    ///   - records: File records specifying what to read
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response containing file record data
    /// - Throws: `ModbusClientError` on failure
    func sendReadFileRecordRequest(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFileRecordResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performReadFileRecordRequest(
                    records: records,
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

    // MARK: - Write File Record (FC 0x15)

    /// Sends a write file record request with automatic retry.
    ///
    /// - Parameters:
    ///   - records: File records with data to write
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response echoing the written records
    /// - Throws: `ModbusClientError` on failure
    func sendWriteFileRecordRequest(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteFileRecordResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performWriteFileRecordRequest(
                    records: records,
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

    /// Performs a single read file record attempt.
    private func performReadFileRecordRequest(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadFileRecordResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildReadFileRecordPDU(records: records)
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

        return try parseReadFileRecordResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses read file record response.
    private func parseReadFileRecordResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> ReadFileRecordResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseReadFileRecordPDU(pdu)
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

    /// Performs a single write file record attempt.
    private func performWriteFileRecordRequest(
        records: [FileRecord],
        unitId: UInt8,
    ) async throws(ModbusClientError) -> WriteFileRecordResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildWriteFileRecordPDU(records: records)
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

        return try parseWriteFileRecordResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses write file record response.
    private func parseWriteFileRecordResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> WriteFileRecordResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseWriteFileRecordPDU(pdu)
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
