// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read File Record Request Builder

/// Builds a Read File Record request PDU (Function Code 0x14).
///
/// PDU format:
/// ```
/// [0]       Function Code (0x14)
/// [1]       Request Data Length (7 × number of sub-requests)
/// [2..N]    Sub-requests, each 7 bytes:
///           [0]   Reference Type (0x06)
///           [1-2] File Number (Big Endian)
///           [3-4] Record Number (Big Endian)
///           [5-6] Record Length in registers (Big Endian)
/// ```
///
/// API based on pymodbus `ReadFileRecordRequest`.
///
/// - Parameter records: Array of file records to read
/// - Returns: PDU bytes ready for MBAP/RTU wrapping
@inlinable
public func buildReadFileRecordPDU(
    records: [FileRecord],
) -> [UInt8] {
    let dataLength = records.count * FileRecordSubRequestSize

    var pdu = [UInt8]()
    pdu.reserveCapacity(2 + dataLength)

    // Function code
    pdu.append(ModbusFunctionCode.readFileRecord)

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
    }

    return pdu
}

// MARK: - ReadFileRecordResponse

/// Parsed response for Read File Record (0x14).
///
/// Response contains file records with their data.
/// API based on pymodbus `ReadFileRecordResponse`.
public struct ReadFileRecordResponse: Equatable, Sendable {
    // MARK: Lifecycle

    @usableFromInline
    init(records: [FileRecord]) {
        self.records = records
    }

    // MARK: Public

    /// File records with data
    public let records: [FileRecord]
}

// MARK: - Read File Record Response Parser

/// Parses a Read File Record response PDU (0x14).
///
/// Response PDU format:
/// ```
/// [0]       Function Code (0x14)
/// [1]       Response Data Length
/// [2..N]    Sub-responses, each variable length:
///           [0]     File Response Length (includes ref type byte)
///           [1]     Reference Type (0x06)
///           [2..M]  Record Data (File Response Length - 1 bytes)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with file records
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadFileRecordPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> ReadFileRecordResponse {
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
    guard functionCode == ModbusFunctionCode.readFileRecord else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.readFileRecord,
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
        // Read file response length
        guard let fileResponseLength = readUInt8(pdu, at: offset) else {
            throw .pduTooShort
        }
        offset += 1

        // Read reference type
        guard let refType = readUInt8(pdu, at: offset) else {
            throw .pduTooShort
        }
        guard refType == FileRecordReferenceType else {
            throw .invalidFileReferenceType(refType)
        }
        offset += 1

        // Record data length = fileResponseLength - 1 (for refType byte)
        let recordDataLength = Int(fileResponseLength) - 1
        guard recordDataLength >= 0, offset + recordDataLength <= pdu.count else {
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

        // Create file record (response doesn't include file/record numbers)
        // Using 0 for fileNumber and recordNumber since they're not in response
        do {
            let record = try FileRecord(fileNumber: 0, recordNumber: 0, recordData: recordData)
            records.append(record)
        } catch {
            throw error
        }
    }

    return ReadFileRecordResponse(records: records)
}

/// Convenience overload for Array input.
@inlinable
public func parseReadFileRecordPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> ReadFileRecordResponse {
    try parseReadFileRecordPDU(pdu.span)
}
