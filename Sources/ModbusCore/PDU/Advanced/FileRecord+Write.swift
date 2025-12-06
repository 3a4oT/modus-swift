// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Write File Record Request Builder

/// Builds a Write File Record request PDU (Function Code 0x15).
///
/// PDU format:
/// ```
/// [0]       Function Code (0x15)
/// [1]       Request Data Length
/// [2..N]    Sub-requests, each variable length:
///           [0]     Reference Type (0x06)
///           [1-2]   File Number (Big Endian)
///           [3-4]   Record Number (Big Endian)
///           [5-6]   Record Length in registers (Big Endian)
///           [7..M]  Record Data (Record Length × 2 bytes)
/// ```
///
/// API based on pymodbus `WriteFileRecordRequest`.
///
/// - Parameter records: Array of file records with data to write
/// - Returns: PDU bytes ready for MBAP/RTU wrapping
@inlinable
public func buildWriteFileRecordPDU(
    records: [FileRecord],
) -> [UInt8] {
    // Calculate total data length
    let dataLength = records.reduce(0) { sum, record in
        sum + FileRecordSubRequestSize + record.recordData.count
    }

    var pdu = [UInt8]()
    pdu.reserveCapacity(2 + dataLength)

    // Function code
    pdu.append(ModbusFunctionCode.writeFileRecord)

    // Request data length
    pdu.append(UInt8(truncatingIfNeeded: dataLength))

    // Sub-requests
    for record in records {
        // Reference type (always 0x06)
        pdu.append(FileRecordReferenceType)

        // File number (Big Endian)
        pdu.append(UInt8(truncatingIfNeeded: record.fileNumber >> 8))
        pdu.append(UInt8(truncatingIfNeeded: record.fileNumber))

        // Record number (Big Endian)
        pdu.append(UInt8(truncatingIfNeeded: record.recordNumber >> 8))
        pdu.append(UInt8(truncatingIfNeeded: record.recordNumber))

        // Record length (Big Endian)
        pdu.append(UInt8(truncatingIfNeeded: record.recordLength >> 8))
        pdu.append(UInt8(truncatingIfNeeded: record.recordLength))

        // Record data
        pdu.append(contentsOf: record.recordData)
    }

    return pdu
}

// MARK: - WriteFileRecordResponse

/// Parsed response for Write File Record (0x15).
///
/// The normal response is an echo of the request.
/// API based on pymodbus `WriteFileRecordResponse`.
public struct WriteFileRecordResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(records: [FileRecord]) {
        self.records = records
    }

    // MARK: Public

    /// File records echoed back (confirms write)
    public let records: [FileRecord]
}

// MARK: - Write File Record Response Parser

/// Parses a Write File Record response PDU (0x15).
///
/// Response PDU format (echo of request):
/// ```
/// [0]       Function Code (0x15)
/// [1]       Response Data Length
/// [2..N]    Sub-responses, each variable length:
///           [0]     Reference Type (0x06)
///           [1-2]   File Number (Big Endian)
///           [3-4]   Record Number (Big Endian)
///           [5-6]   Record Length in registers (Big Endian)
///           [7..M]  Record Data (Record Length × 2 bytes)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with file records
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseWriteFileRecordPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> WriteFileRecordResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        guard let exceptionCode = readUInt8(pdu, at: 1) else {
            throw .pduTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Minimum response: func(1) + dataLength(1) = 2
    guard pdu.count >= 2 else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.writeFileRecord else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.writeFileRecord,
            got: functionCode,
        )
    }

    guard let dataLength = readUInt8(pdu, at: 1) else {
        throw .pduTooShort
    }

    // Validate PDU has enough bytes
    guard pdu.count >= 2 + Int(dataLength) else {
        throw .pduTooShort
    }

    // Parse sub-responses
    var records = [FileRecord]()
    var offset = 2

    while offset < 2 + Int(dataLength) {
        // Read reference type
        guard let refType = readUInt8(pdu, at: offset) else {
            throw .pduTooShort
        }
        guard refType == FileRecordReferenceType else {
            throw .invalidFileReferenceType(refType)
        }
        offset += 1

        // Read file number (Big Endian)
        guard let fileNumber = readUInt16BE(pdu, at: offset) else {
            throw .pduTooShort
        }
        offset += 2

        // Read record number (Big Endian)
        guard let recordNumber = readUInt16BE(pdu, at: offset) else {
            throw .pduTooShort
        }
        offset += 2

        // Read record length (Big Endian)
        guard let recordLength = readUInt16BE(pdu, at: offset) else {
            throw .pduTooShort
        }
        offset += 2

        // Record data length = recordLength × 2 bytes
        let recordDataLength = Int(recordLength) * 2
        guard offset + recordDataLength <= pdu.count else {
            throw .pduTooShort
        }

        // Extract record data
        var recordData = [UInt8]()
        recordData.reserveCapacity(recordDataLength)
        for i in 0 ..< recordDataLength {
            guard let byte = readUInt8(pdu, at: offset + i) else {
                throw .pduTooShort
            }
            recordData.append(byte)
        }
        offset += recordDataLength

        // Create file record
        do {
            let record = try FileRecord(fileNumber: fileNumber, recordNumber: recordNumber, recordData: recordData)
            records.append(record)
        } catch {
            throw error
        }
    }

    return WriteFileRecordResponse(records: records)
}

/// Convenience overload for Array input.
@inlinable
public func parseWriteFileRecordPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> WriteFileRecordResponse {
    try parseWriteFileRecordPDU(pdu.span)
}
