// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - PDUError

/// Errors for PDU parsing.
public enum PDUError: Error, Equatable, Sendable {
    /// PDU is shorter than minimum size
    case pduTooShort
    /// Unexpected function code in response
    case unexpectedFunctionCode(expected: UInt8, got: UInt8)
    /// Byte count doesn't match expected for register count
    case byteCountMismatch(expected: UInt8, got: UInt8)
    /// Modbus exception response received
    case exceptionResponse(ModbusException)
    /// Unknown exception code
    case unknownException(UInt8)
    /// Invalid MEI type in response
    case invalidMEIType(UInt8)
    /// Invalid reference type in file record (must be 0x06)
    case invalidFileReferenceType(UInt8)
    /// Record data length must be even (multiple of 2 bytes per word)
    case oddRecordDataLength(Int)
}
