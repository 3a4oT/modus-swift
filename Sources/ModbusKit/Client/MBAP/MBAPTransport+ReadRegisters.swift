// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Read Registers (FC 0x03, 0x04)

/// Read Holding Registers (FC 0x03) and Read Input Registers (FC 0x04) implementation.
///
/// ## Function Code 0x03 - Read Holding Registers
///
/// Reads the contents of a contiguous block of holding registers in a remote device.
/// Holding registers are 16-bit read/write registers.
///
/// ## Function Code 0x04 - Read Input Registers
///
/// Reads the contents of a contiguous block of input registers in a remote device.
/// Input registers are 16-bit read-only registers (typically sensor values).
///
/// ## Limits
///
/// - Maximum 125 registers per request (Modbus specification limit)
/// - Address range: 0x0000 to 0xFFFF
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.3 (FC 0x03)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.4 (FC 0x04)
extension MBAPTransport {
    // MARK: Internal

    /// Sends a read registers request with automatic retry on transient errors.
    ///
    /// - Parameters:
    ///   - functionCode: Either `0x03` (holding) or `0x04` (input)
    ///   - address: Starting register address (0x0000-0xFFFF)
    ///   - count: Number of registers to read (1-125)
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response containing register values
    /// - Throws: `ModbusClientError` on failure
    func sendReadRegistersRequest(
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1
        let startTime = ContinuousClock.now

        for attempt in 1 ... maxAttempts {
            do {
                let result = try await performReadRegistersRequest(
                    functionCode: functionCode,
                    address: address,
                    count: count,
                    unitId: unitId,
                )
                metrics?.recordRequest(functionCode: functionCode, duration: ContinuousClock.now - startTime)
                return result
            } catch {
                lastError = error
                guard error.isRetryable else {
                    metrics?.recordRequestError(functionCode: functionCode, error: error.metricsLabel)
                    throw error
                }
                guard attempt < maxAttempts else {
                    break
                }
                metrics?.recordRetry(functionCode: functionCode)
                logger?.debug("Retry \(attempt)/\(maxAttempts - 1) after error: \(error)")
            }
        }

        metrics?.recordRequestError(functionCode: functionCode, error: lastError?.metricsLabel ?? "unknown")
        throw lastError ?? .connectionFailed("All retry attempts failed")
    }

    // MARK: Private

    /// Performs a single read registers request attempt.
    private func performReadRegistersRequest(
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadRegistersResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()

        let pdu: [UInt8] =
            if functionCode == ModbusFunctionCode.readHoldingRegisters {
                buildReadHoldingRegistersPDU(address: address, count: count)
            } else {
                buildReadInputRegistersPDU(address: address, count: count)
            }

        let adu = buildModbusTCPADU(
            transactionId: transactionId,
            unitId: unitId,
            pdu: pdu,
        )

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

        return try parseReadRegistersResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
            expectedFunction: functionCode,
        )
    }

    /// Parses read registers response.
    private func parseReadRegistersResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
        expectedFunction: UInt8,
    ) throws(ModbusClientError) -> ReadRegistersResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseReadRegistersPDU(pdu, expectedFunction: expectedFunction)
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
