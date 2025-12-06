// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Device Identification (FC 0x2B / MEI 0x0E)

extension ModbusUDPClient {
    /// Read device identification (Function Code 0x2B / MEI 0x0E).
    ///
    /// Reads identification and description info from a remote device.
    /// API based on pymodbus `read_device_identification(read_code, object_id, unit)`.
    ///
    /// - Parameters:
    ///   - readCode: Read device ID code (.basic, .regular, .extended, .specific)
    ///   - objectId: Starting object ID (default 0x00) or specific object for .specific
    ///   - unitId: Unit identifier (1-247)
    /// - Returns: Response with device identification objects
    /// - Throws: `ModbusClientError` on any failure
    public func readDeviceIdentification(
        readCode: ReadDeviceIdCode = .basic,
        objectId: UInt8 = 0x00,
        unitId: UInt8,
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        let pdu = buildReadDeviceIdentificationPDU(readCode: readCode, objectId: objectId)
        let responsePDU = try await sendRequest(pdu: pdu, unitId: unitId)

        do {
            return try parseDeviceIdentificationPDU(responsePDU)
        } catch {
            throw mapPDUError(error)
        }
    }

    /// Read device identification with default unit ID (1).
    @inlinable
    public func readDeviceIdentification(
        readCode: ReadDeviceIdCode = .basic,
        objectId: UInt8 = 0x00,
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        try await readDeviceIdentification(readCode: readCode, objectId: objectId, unitId: 1)
    }
}
