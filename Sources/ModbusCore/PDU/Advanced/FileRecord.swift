// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - FileRecord

/// Represents a file record reference for Read/Write File Record operations.
///
/// Per Modbus spec V1.1b3:
/// - File numbers: 0x0000 to 0xFFFF (spec says 1-10 for some devices, but protocol allows full range)
/// - Record numbers: 0x0000 to 0x270F (0-9999 decimal)
/// - Record length: in 16-bit registers (words)
///
/// API based on pymodbus `FileRecord` dataclass.
public struct FileRecord: Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a file record reference for read operations.
    ///
    /// - Parameters:
    ///   - fileNumber: File number (0x0000 to 0xFFFF)
    ///   - recordNumber: Starting record number within file (0x0000 to 0x270F)
    ///   - recordLength: Number of 16-bit registers to read
    public init(fileNumber: UInt16, recordNumber: UInt16, recordLength: UInt16) {
        self.fileNumber = fileNumber
        self.recordNumber = recordNumber
        self.recordLength = recordLength
        recordData = []
    }

    /// Creates a file record with data for write operations or parsed responses.
    ///
    /// - Parameters:
    ///   - fileNumber: File number (0x0000 to 0xFFFF)
    ///   - recordNumber: Starting record number within file (0x0000 to 0x270F)
    ///   - recordData: Record data bytes (must be even length, 2 bytes per register)
    /// - Throws: `PDUError.oddRecordDataLength` if data length is odd
    public init(fileNumber: UInt16, recordNumber: UInt16, recordData: [UInt8]) throws(PDUError) {
        guard recordData.count % 2 == 0 else {
            throw .oddRecordDataLength(recordData.count)
        }
        self.fileNumber = fileNumber
        self.recordNumber = recordNumber
        self.recordData = recordData
        recordLength = UInt16(recordData.count / 2)
    }

    // MARK: Public

    /// File number (0x0000 to 0xFFFF)
    public let fileNumber: UInt16

    /// Starting record number within the file (0x0000 to 0x270F)
    public let recordNumber: UInt16

    /// Number of 16-bit registers
    public let recordLength: UInt16

    /// Record data bytes (empty for read requests, populated for write requests and responses)
    public let recordData: [UInt8]
}

// MARK: - Constants

/// Reference type for file records (per Modbus spec, must be 0x06)
public let FileRecordReferenceType: UInt8 = 0x06

/// Size of a sub-request in Read File Record request: refType(1) + fileNum(2) + recNum(2) + recLen(2) = 7
public let FileRecordSubRequestSize = 7
