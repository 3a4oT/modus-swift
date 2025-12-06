// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ServiceLifecycle

// MARK: - Device Identification (FC 0x2B / MEI 0x0E)

/// Device Identification support for ModbusTCPClient.
///
/// Reads identification and description info from a remote device.
extension ModbusTCPClient {
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
        try await sendReadDeviceIdentificationRequest(
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
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        try await readDeviceIdentification(readCode: readCode, objectId: objectId, unitId: 1)
    }
}

/// Device Identification support for ModbusTLSClient.
///
/// Reads identification and description info from a remote device.
extension ModbusTLSClient {
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
        try await sendReadDeviceIdentificationRequest(
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
    ) async throws(ModbusClientError) -> DeviceIdentificationResponse {
        try await readDeviceIdentification(readCode: readCode, objectId: objectId, unitId: 1)
    }
}

// MARK: - ModbusTCPClient + Service

/// Service protocol conformance for ModbusTCPClient.
///
/// When used with `ServiceGroup`, the client will automatically close
/// its connection when receiving shutdown signals (SIGTERM, SIGINT).
///
/// ## Example
///
/// ```swift
/// let client = ModbusTCPClient(host: "192.168.1.100")
/// try await client.connect()
///
/// let group = ServiceGroup(
///     services: [client],
///     gracefulShutdownSignals: [.sigterm, .sigint],
///     logger: logger
/// )
/// try await group.run()
/// ```
///
/// ## Reference
///
/// - [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle)
extension ModbusTCPClient: Service {
    /// Runs the client as a service, waiting for graceful shutdown.
    ///
    /// When used with `ServiceGroup`, the client will:
    /// 1. Wait for graceful shutdown signal (SIGTERM, SIGINT)
    /// 2. Close the connection gracefully
    public func run() async throws {
        try await gracefulShutdown()
        await close()
    }
}

// MARK: - ModbusTLSClient + Service

/// Service protocol conformance for ModbusTLSClient.
///
/// When used with `ServiceGroup`, the client will automatically close
/// its connection when receiving shutdown signals (SIGTERM, SIGINT).
///
/// ## Example
///
/// ```swift
/// let client = ModbusTLSClient(host: "192.168.1.100")
/// try await client.connect()
///
/// let group = ServiceGroup(
///     services: [client],
///     gracefulShutdownSignals: [.sigterm, .sigint],
///     logger: logger
/// )
/// try await group.run()
/// ```
///
/// ## Reference
///
/// - [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle)
extension ModbusTLSClient: Service {
    /// Runs the client as a service, waiting for graceful shutdown.
    ///
    /// When used with `ServiceGroup`, the client will:
    /// 1. Wait for graceful shutdown signal (SIGTERM, SIGINT)
    /// 2. Close the connection gracefully
    public func run() async throws {
        try await gracefulShutdown()
        await close()
    }
}
