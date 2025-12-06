// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Read Bits (FC 0x01, 0x02)

/// Read Coils (FC 0x01) and Read Discrete Inputs (FC 0x02) implementation.
///
/// ## Function Code 0x01 - Read Coils
///
/// Reads the status of coils (1-bit read/write outputs) in a remote device.
/// Response contains packed bits, LSB first within each byte.
///
/// ## Function Code 0x02 - Read Discrete Inputs
///
/// Reads the status of discrete inputs (1-bit read-only inputs) in a remote device.
/// Typically represents switch states, sensor triggers, etc.
///
/// ## Bit Packing
///
/// Response bytes contain 8 coils/inputs each:
/// - Bit 0 of byte 0 = first coil/input
/// - Bit 7 of byte 0 = eighth coil/input
/// - Bit 0 of byte 1 = ninth coil/input, etc.
///
/// ## Limits
///
/// - Maximum 2000 coils/inputs per request (Modbus specification limit)
/// - Address range: 0x0000 to 0xFFFF
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.1 (FC 0x01)
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.2 (FC 0x02)
extension MBAPTransport {
    // MARK: Internal

    /// Sends a read bits request with automatic retry on transient errors.
    ///
    /// - Parameters:
    ///   - functionCode: Either `0x01` (coils) or `0x02` (discrete inputs)
    ///   - address: Starting address (0x0000-0xFFFF)
    ///   - count: Number of bits to read (1-2000)
    ///   - unitId: Unit identifier (1-247, or 0 for broadcast)
    /// - Returns: Response containing bit values
    /// - Throws: `ModbusClientError` on failure
    func sendReadBitsRequest(
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performReadBitsRequest(
                    functionCode: functionCode,
                    address: address,
                    count: count,
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

    /// Performs a single read bits request attempt.
    private func performReadBitsRequest(
        functionCode: UInt8,
        address: UInt16,
        count: UInt16,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> ReadBitsResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()

        let pdu: [UInt8] =
            if functionCode == ModbusFunctionCode.readCoils {
                buildReadCoilsPDU(address: address, count: count)
            } else {
                buildReadDiscreteInputsPDU(address: address, count: count)
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

        return try parseReadBitsResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
            expectedFunction: functionCode,
            requestedCount: count,
        )
    }

    /// Parses read bits response.
    private func parseReadBitsResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
        expectedFunction: UInt8,
        requestedCount: UInt16,
    ) throws(ModbusClientError) -> ReadBitsResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseReadBitsPDU(pdu, expectedFunction: expectedFunction, requestedCount: requestedCount)
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
