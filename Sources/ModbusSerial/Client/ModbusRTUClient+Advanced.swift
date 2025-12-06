// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import ModbusCore

// MARK: - Advanced Operations

extension ModbusRTUClient {
    // MARK: - Read/Write Multiple Registers (FC 0x17)

    /// Reads and writes multiple registers in a single transaction (FC 0x17).
    ///
    /// Performs a combined read and write operation atomically.
    /// The write operation is performed before the read operation.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.17
    ///
    /// - Parameters:
    ///   - readAddress: Starting address for read operation
    ///   - readCount: Number of registers to read (1-125)
    ///   - writeAddress: Starting address for write operation
    ///   - writeValues: Values to write (1-121 registers)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Response containing read register values
    public func readWriteMultipleRegisters(
        readAddress: UInt16,
        readCount: UInt16,
        writeAddress: UInt16,
        writeValues: [UInt16],
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadWriteMultipleRegistersResponse {
        guard readCount >= 1, readCount <= 125 else {
            throw .invalidParameter("readCount must be 1-125")
        }
        guard writeValues.count >= 1, writeValues.count <= 121 else {
            throw .invalidParameter("writeValues count must be 1-121")
        }

        let request = buildRTUReadWriteMultipleRegistersRequest(
            readAddress: readAddress,
            readCount: readCount,
            writeAddress: writeAddress,
            writeValues: writeValues,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUReadWriteMultipleRegistersResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }

    // MARK: - Read FIFO Queue (FC 0x18)

    /// Reads FIFO queue contents (FC 0x18).
    ///
    /// Reads the contents of a First-In-First-Out (FIFO) queue of registers.
    /// The FIFO can contain up to 31 registers.
    ///
    /// Reference: Modbus Application Protocol V1.1b3, Section 6.18
    ///
    /// - Parameters:
    ///   - address: FIFO pointer address (0-65535)
    ///   - unitId: Modbus unit ID (default: 1)
    /// - Returns: Response containing FIFO count and register values
    public func readFIFOQueue(
        address: UInt16,
        unitId: UInt8 = 1,
    ) async throws(RTUClientError) -> ReadFIFOQueueResponse {
        let request = buildRTUReadFIFOQueueRequest(
            address: address,
            unitId: unitId,
        )

        let response = try await sendRequest(request: request)

        do throws(RTUError) {
            return try parseRTUReadFIFOQueueResponse(
                response,
                expectedUnitId: unitId,
            )
        } catch {
            throw mapRTUError(error)
        }
    }
}
