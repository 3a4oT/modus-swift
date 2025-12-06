// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTUError

/// Errors that can occur when parsing Modbus RTU frames.
public enum RTUError: Error, Equatable, Sendable {
    /// Frame is shorter than minimum valid size
    case frameTooShort
    /// CRC does not match calculated value
    case invalidCRC
    /// Unexpected function code in response
    case unexpectedFunctionCode(expected: UInt8, got: UInt8)
    /// Unit ID mismatch in response
    case unitIdMismatch(expected: UInt8, got: UInt8)
    /// Byte count doesn't match expected for register count
    case byteCountMismatch(expected: UInt8, got: UInt8)
    /// Modbus exception response received
    case exceptionResponse(ModbusException)
}

// MARK: - RTUFrameSize

/// Fixed sizes for Modbus RTU frame components.
public enum RTUFrameSize {
    /// Minimum request frame: unitId(1) + func(1) + data(2+) + crc(2) = 6
    public static let minimumRequest = 6
    /// Minimum response frame: unitId(1) + func(1) + count(1) + crc(2) = 5
    public static let minimumResponse = 5
    /// Exception response size: unitId(1) + func(1) + code(1) + crc(2) = 5
    public static let exceptionResponse = 5
    /// Report Server ID request: unitId(1) + func(1) + crc(2) = 4
    /// Note: FC 0x11 has no data payload in request
    public static let reportServerIdRequest = 4
    /// Read Exception Status request: unitId(1) + func(1) + crc(2) = 4
    /// Note: FC 0x07 has no data payload in request
    public static let readExceptionStatusRequest = 4
    /// Diagnostics request: unitId(1) + func(1) + subFunc(2) + data(2) + crc(2) = 8
    public static let diagnosticsRequest = 8
    /// Get Comm Event Counter request: unitId(1) + func(1) + crc(2) = 4
    /// Note: FC 0x0B has no data payload in request
    public static let getCommEventCounterRequest = 4
    /// Get Comm Event Log request: unitId(1) + func(1) + crc(2) = 4
    /// Note: FC 0x0C has no data payload in request
    public static let getCommEventLogRequest = 4
    /// CRC size: 2 bytes
    public static let crc = 2
}
