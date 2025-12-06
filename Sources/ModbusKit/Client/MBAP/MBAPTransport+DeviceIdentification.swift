// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore

// MARK: - Device Identification (FC 0x2B / MEI 0x0E)

/// Read Device Identification (FC 0x2B / MEI Type 0x0E) implementation.
///
/// ## Overview
///
/// Encapsulated Interface Transport (MEI) with Device Identification allows
/// reading identification and additional information about a remote device.
///
/// ## Read Device ID Codes
///
/// - **Basic** (0x01): VendorName, ProductCode, MajorMinorRevision
/// - **Regular** (0x02): Basic + VendorUrl, ProductName, ModelName, UserApplicationName
/// - **Extended** (0x03): Regular + vendor-specific objects (0x80-0xFF)
/// - **Specific** (0x04): Read a single specific object by ID
///
/// ## Object IDs
///
/// | ID | Name | Category |
/// |----|------|----------|
/// | 0x00 | VendorName | Basic |
/// | 0x01 | ProductCode | Basic |
/// | 0x02 | MajorMinorRevision | Basic |
/// | 0x03 | VendorUrl | Regular |
/// | 0x04 | ProductName | Regular |
/// | 0x05 | ModelName | Regular |
/// | 0x06 | UserApplicationName | Regular |
/// | 0x80-0xFF | Vendor-specific | Extended |
///
/// ## Conformity Level
///
/// Devices report their conformity level in the response:
/// - 0x01: Basic identification (stream access only)
/// - 0x02: Regular identification (stream access only)
/// - 0x03: Extended identification (stream access only)
/// - 0x81: Basic + individual access
/// - 0x82: Regular + individual access
/// - 0x83: Extended + individual access
///
/// ## Reference
///
/// - MODBUS Application Protocol Specification V1.1b3, Section 6.21
/// - pymodbus `read_device_information()` implementation
extension MBAPTransport {
    // MARK: Internal

    /// Sends a read device identification request with automatic retry.
    ///
    /// - Parameters:
    ///   - readCode: Read device ID code (.basic, .regular, .extended, .specific)
    ///   - objectId: Starting object ID (0x00 for stream, or specific ID for .specific)
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response containing device identification objects
    /// - Throws: `ModbusClientError` on failure
    func sendReadDeviceIdentificationRequest(
        readCode: ReadDeviceIdCode,
        objectId: UInt8,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        var lastError: ModbusClientError?
        let maxAttempts = configuration.retries + 1

        for attempt in 1 ... maxAttempts {
            do {
                return try await performReadDeviceIdentificationRequest(
                    readCode: readCode,
                    objectId: objectId,
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

    /// Performs a single read device identification attempt.
    private func performReadDeviceIdentificationRequest(
        readCode: ReadDeviceIdCode,
        objectId: UInt8,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        try await ensureConnected()

        guard let ch = channel, ch.isActive else {
            throw .notConnected
        }

        let transactionId = nextTransactionId()
        let pdu = buildReadDeviceIdentificationPDU(readCode: readCode, objectId: objectId)
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

        return try parseDeviceIdentificationResponse(
            responseBytes,
            transactionId: transactionId,
            unitId: unitId,
        )
    }

    /// Parses device identification response.
    private func parseDeviceIdentificationResponse(
        _ responseBytes: [UInt8],
        transactionId: UInt16,
        unitId: UInt8,
    ) throws(ModbusClientError) -> DeviceIdentificationResponse {
        do {
            let (_, pdu) = try parseModbusTCPADU(
                responseBytes,
                expectedTransactionId: transactionId,
                expectedUnitId: unitId,
            )
            return try parseDeviceIdentificationPDU(pdu)
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
