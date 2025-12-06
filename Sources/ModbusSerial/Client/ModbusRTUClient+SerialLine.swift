// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore

// MARK: - Serial Line Only Operations

extension ModbusRTUClient {
    // MARK: - Read Exception Status (FC 0x07)

    /// Reads exception status (FC 0x07).
    ///
    /// Serial Line only function. Returns eight exception status bits
    /// packed into a single byte.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.7
    ///
    /// - Parameter unitId: Modbus unit ID (default: 1)
    /// - Returns: Exception status response with 8 coil values
    public func readExceptionStatus(
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadExceptionStatusResponse {
        let request = buildRTUReadExceptionStatusRequest(unitId: unitId)
        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUReadExceptionStatusResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    // MARK: - Diagnostics (FC 0x08)

    /// Performs diagnostics (FC 0x08).
    ///
    /// Serial Line only function. Provides tests for checking the
    /// communication system and serial line status.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.8
    ///
    /// - Parameters:
    ///   - subFunction: Diagnostics sub-function code
    ///   - data: Data value (interpretation depends on sub-function)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Diagnostics response (typically echoes request)
    public func diagnostics(
        subFunction: DiagnosticSubFunction,
        data: UInt16 = 0x0000,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> DiagnosticsResponse {
        let request = buildRTUDiagnosticsRequest(
            subFunction: subFunction,
            data: data,
            unitId: unitId,
        )
        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUDiagnosticsResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    /// Performs loopback test (FC 0x08, sub-function 0x0000).
    ///
    /// Convenience method for the most common diagnostics use case.
    /// Sends a test value that should be echoed back unchanged.
    ///
    /// - Parameters:
    ///   - data: Test data (default: 0x1234)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: True if echoed data matches sent data
    public func loopbackTest(
        data: UInt16 = 0x1234,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> Bool {
        let response = try await diagnostics(
            subFunction: .returnQueryData,
            data: data,
            unitId: unitId,
        )
        return response.data == data
    }

    // MARK: - Get Comm Event Counter (FC 0x0B)

    /// Gets communication event counter (FC 0x0B).
    ///
    /// Serial Line only function. Returns a status word and event count
    /// from the device's communication event counter.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.9
    ///
    /// - Parameter unitId: Modbus unit ID (default: 1)
    /// - Returns: Event counter response with status and count
    public func getCommEventCounter(
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> GetCommEventCounterResponse {
        let request = buildRTUGetCommEventCounterRequest(unitId: unitId)
        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUGetCommEventCounterResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    // MARK: - Get Comm Event Log (FC 0x0C)

    /// Gets communication event log (FC 0x0C).
    ///
    /// Serial Line only function. Returns a status word, event count,
    /// message count, and a field of event bytes from the device.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.10
    ///
    /// - Parameter unitId: Modbus unit ID (default: 1)
    /// - Returns: Event log response with status, counts, and events
    public func getCommEventLog(
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> GetCommEventLogResponse {
        let request = buildRTUGetCommEventLogRequest(unitId: unitId)
        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUGetCommEventLogResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    // MARK: - Report Server ID (FC 0x11)

    /// Reports server ID (FC 0x11).
    ///
    /// Serial Line only function. Returns device identification data
    /// including server ID, run indicator status, and additional data.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.13
    ///
    /// - Parameter unitId: Modbus unit ID (default: 1)
    /// - Returns: Server ID response with device identification
    public func reportServerId(
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReportServerIdResponse {
        let request = buildRTUReportServerIdRequest(unitId: unitId)
        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUReportServerIdResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }
}
