// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore

// MARK: - Device Identification (FC 0x2B / MEI 0x0E)

extension ModbusRTUClient {
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
    /// - Throws: `RTUClientError` on any failure
    public func readDeviceIdentification(
        readCode: ReadDeviceIdCode = .basic,
        objectId: UInt8 = 0x00,
        unitId: UInt8,
    ) async throws(RTUClientError) -> DeviceIdentificationResponse {
        try await sendDeviceIdentificationRequest(
            readCode: readCode,
            objectId: objectId,
            unitId: unitId,
        )
    }

    /// Read device identification with default unit ID (1).
    @inlinable
    public func readDeviceIdentification(
        readCode: ReadDeviceIdCode = .basic,
        objectId: UInt8 = 0x00,
    ) async throws(RTUClientError) -> DeviceIdentificationResponse {
        try await readDeviceIdentification(readCode: readCode, objectId: objectId, unitId: 1)
    }
}

// MARK: - Internal Implementation

extension ModbusRTUClient {
    // MARK: Internal

    /// Sends device identification request with retry and error recovery.
    func sendDeviceIdentificationRequest(
        readCode: ReadDeviceIdCode,
        objectId: UInt8,
        unitId: UInt8,
    ) async throws(RTUClientError) -> DeviceIdentificationResponse {
        let request = buildRTUReadDeviceIdentificationRequest(
            readCode: readCode,
            objectId: objectId,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)
        return try parseDeviceIdentificationResponse(
            response: response,
            unitId: unitId,
        )
    }

    // MARK: Private

    /// Parses device identification response.
    private func parseDeviceIdentificationResponse(
        response: [UInt8],
        unitId: UInt8,
    ) throws(RTUClientError) -> DeviceIdentificationResponse {
        do throws(RTUError) {
            return try parseRTUDeviceIdentificationResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }
}
