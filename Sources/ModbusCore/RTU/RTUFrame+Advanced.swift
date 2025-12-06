// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Read/Write Multiple Registers (FC 0x17)

/// Builds a Modbus RTU Read/Write Multiple Registers request (FC 0x17).
///
/// Performs a combined read and write operation in a single transaction.
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x17)
/// [2-3]   Read Starting Address (Big Endian)
/// [4-5]   Quantity to Read (Big Endian)
/// [6-7]   Write Starting Address (Big Endian)
/// [8-9]   Quantity to Write (Big Endian)
/// [10]    Write Byte Count
/// [11..]  Write Values (Big Endian)
/// [N-1,N] CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.17
///
/// - Parameters:
///   - readAddress: Starting address for read operation
///   - readCount: Number of registers to read (1-125)
///   - writeAddress: Starting address for write operation
///   - writeValues: Values to write (1-121 registers)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC
@inlinable
public func buildRTUReadWriteMultipleRegistersRequest(
    readAddress: UInt16,
    readCount: UInt16,
    writeAddress: UInt16,
    writeValues: [UInt16],
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    let writeQuantity = UInt16(writeValues.count)
    let writeByteCount = UInt8(writeValues.count * 2)

    var frame: [UInt8] = []
    frame.reserveCapacity(11 + Int(writeByteCount) + 2) // header + data + CRC
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readWriteMultipleRegisters)

    // Read starting address
    frame.append(UInt8(truncatingIfNeeded: readAddress >> 8))
    frame.append(UInt8(truncatingIfNeeded: readAddress))

    // Quantity to read
    frame.append(UInt8(truncatingIfNeeded: readCount >> 8))
    frame.append(UInt8(truncatingIfNeeded: readCount))

    // Write starting address
    frame.append(UInt8(truncatingIfNeeded: writeAddress >> 8))
    frame.append(UInt8(truncatingIfNeeded: writeAddress))

    // Quantity to write
    frame.append(UInt8(truncatingIfNeeded: writeQuantity >> 8))
    frame.append(UInt8(truncatingIfNeeded: writeQuantity))

    // Write byte count
    frame.append(writeByteCount)

    // Write values
    for value in writeValues {
        frame.append(UInt8(truncatingIfNeeded: value >> 8))
        frame.append(UInt8(truncatingIfNeeded: value))
    }

    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Read/Write Multiple Registers response (FC 0x17).
///
/// Response frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x17)
/// [2]     Byte Count
/// [3..]   Read Register Data (Big Endian)
/// [N-1,N] CRC-16
/// ```
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed response with read registers
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUReadWriteMultipleRegistersResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadWriteMultipleRegistersResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.readWriteMultipleRegisters else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readWriteMultipleRegisters,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseReadWriteMultipleRegistersPDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            throw .byteCountMismatch(expected: expected, got: got)
        case .unknownException,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUReadWriteMultipleRegistersResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadWriteMultipleRegistersResponse {
    try parseRTUReadWriteMultipleRegistersResponse(frame.span, expectedUnitId: expectedUnitId)
}

// MARK: - RTU Read FIFO Queue (FC 0x18)

/// Builds a Modbus RTU Read FIFO Queue request (FC 0x18).
///
/// Reads the contents of a First-In-First-Out (FIFO) queue of registers.
///
/// Request frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x18)
/// [2-3]   FIFO Pointer Address (Big Endian)
/// [4-5]   CRC-16
/// ```
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.18
///
/// - Parameters:
///   - address: FIFO pointer address (0-65535)
///   - unitId: Unit identifier (default: 0x01)
/// - Returns: Complete Modbus RTU frame with CRC (6 bytes total)
@inlinable
public func buildRTUReadFIFOQueueRequest(
    address: UInt16,
    unitId: UInt8 = 0x01,
) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(6)
    frame.append(unitId)
    frame.append(ModbusFunctionCode.readFIFOQueue)
    frame.append(UInt8(truncatingIfNeeded: address >> 8))
    frame.append(UInt8(truncatingIfNeeded: address))
    return appendModbusCRC(frame)
}

/// Parses a Modbus RTU Read FIFO Queue response (FC 0x18).
///
/// Response frame format:
/// ```
/// [0]     Unit ID
/// [1]     Function Code (0x18)
/// [2-3]   Byte Count (Big Endian)
/// [4-5]   FIFO Count (Big Endian)
/// [6..]   FIFO Register Data (Big Endian)
/// [N-1,N] CRC-16
/// ```
///
/// - Parameters:
///   - frame: Raw Modbus RTU response frame (including CRC)
///   - expectedUnitId: Expected unit ID (for validation)
/// - Returns: Parsed response with FIFO count and registers
/// - Throws: `RTUError` if validation fails
@inlinable
public func parseRTUReadFIFOQueueResponse(
    _ frame: Span<UInt8>,
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadFIFOQueueResponse {
    try validateRTUMinimumSize(frame)
    try validateRTUCRC(frame)

    if isRTUExceptionResponse(frame) {
        guard let exceptionCode = readUInt8(frame, at: 2) else {
            throw .frameTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .exceptionResponse(.illegalFunction)
    }

    guard let unitId = readUInt8(frame, at: 0) else {
        throw .frameTooShort
    }
    guard unitId == expectedUnitId else {
        throw .unitIdMismatch(expected: expectedUnitId, got: unitId)
    }

    guard let functionCode = readUInt8(frame, at: 1) else {
        throw .frameTooShort
    }
    guard functionCode == ModbusFunctionCode.readFIFOQueue else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readFIFOQueue,
            got: functionCode,
        )
    }

    // Extract PDU (skip unitId, remove CRC)
    let pduLength = frame.count - 3
    var pdu: [UInt8] = []
    pdu.reserveCapacity(pduLength)
    for i in 1 ..< (frame.count - 2) {
        guard let byte = readUInt8(frame, at: i) else {
            throw .frameTooShort
        }
        pdu.append(byte)
    }

    do {
        return try parseReadFIFOQueuePDU(pdu)
    } catch {
        switch error {
        case .pduTooShort:
            throw .frameTooShort
        case let .exceptionResponse(exception):
            throw .exceptionResponse(exception)
        case let .unexpectedFunctionCode(expected, got):
            throw .unexpectedFunctionCode(expected: expected, got: got)
        case let .byteCountMismatch(expected, got):
            throw .byteCountMismatch(expected: expected, got: got)
        case .unknownException,
             .invalidMEIType,
             .invalidFileReferenceType,
             .oddRecordDataLength:
            throw .exceptionResponse(.illegalFunction)
        }
    }
}

/// Convenience overload for Array input.
@inlinable
public func parseRTUReadFIFOQueueResponse(
    _ frame: [UInt8],
    expectedUnitId: UInt8 = 0x01,
) throws(RTUError) -> ReadFIFOQueueResponse {
    try parseRTUReadFIFOQueueResponse(frame.span, expectedUnitId: expectedUnitId)
}
