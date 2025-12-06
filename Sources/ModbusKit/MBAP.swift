// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - MBAPHeader

/// Modbus Application Protocol (MBAP) header for Modbus TCP.
///
/// MBAP header structure (7 bytes, all multi-byte fields Big Endian):
/// ```
/// ┌──────────────┬─────────────┬────────┬─────────┐
/// │ Transaction  │  Protocol   │ Length │ Unit ID │
/// │   ID (2)     │   ID (2)    │  (2)   │   (1)   │
/// └──────────────┴─────────────┴────────┴─────────┘
/// ```
///
/// Reference implementations:
/// - pymodbus: `framer/socket.py` - MIN_SIZE = 8
/// - libmodbus: `modbus-tcp.c` - _MODBUS_TCP_HEADER_LENGTH = 7
/// - goburrow/modbus: `tcpclient.go` - tcpHeaderSize = 7
public struct MBAPHeader: Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates an MBAP header.
    ///
    /// - Parameters:
    ///   - transactionId: Transaction identifier for request/response matching
    ///   - unitId: Unit identifier (slave address), defaults to 1
    ///   - pduLength: Length of the PDU (function code + data)
    public init(transactionId: UInt16, unitId: UInt8 = 1, pduLength: UInt16) {
        self.transactionId = transactionId
        protocolId = MBAPConstants.protocolId
        length = pduLength + 1 // +1 for Unit ID
        self.unitId = unitId
    }

    /// Internal initializer for parsing
    @usableFromInline
    init(transactionId: UInt16, protocolId: UInt16, length: UInt16, unitId: UInt8) {
        self.transactionId = transactionId
        self.protocolId = protocolId
        self.length = length
        self.unitId = unitId
    }

    // MARK: Public

    /// Transaction identifier for request/response matching
    public let transactionId: UInt16

    /// Protocol identifier (always 0x0000 for Modbus)
    public let protocolId: UInt16

    /// Length of following data (Unit ID + PDU)
    public let length: UInt16

    /// Unit identifier (slave address)
    public let unitId: UInt8
}

// MARK: - MBAPConstants

/// Constants for MBAP header.
///
/// Verified against:
/// - pymodbus: MIN_SIZE = 8 (header + 1 byte PDU minimum)
/// - libmodbus: _MODBUS_TCP_HEADER_LENGTH = 7
/// - goburrow/modbus: tcpHeaderSize = 7, tcpProtocolIdentifier = 0x0000
public enum MBAPConstants {
    /// MBAP header size in bytes
    public static let headerSize = 7

    /// Protocol identifier for Modbus (always 0x0000)
    public static let protocolId: UInt16 = 0x0000

    /// Minimum ADU size (header + function code)
    public static let minimumADUSize = 8

    /// Maximum ADU size (per goburrow: tcpMaxLength = 260)
    public static let maximumADUSize = 260

    /// Default Modbus TCP port
    public static let defaultPort = 502
}

// MARK: - MBAPOffset

/// Byte offsets within MBAP header.
public enum MBAPOffset {
    public static let transactionId = 0
    public static let protocolId = 2
    public static let length = 4
    public static let unitId = 6
    public static let pdu = 7
}

// MARK: - MBAPError

/// Errors for MBAP header parsing.
public enum MBAPError: Error, Equatable, Sendable {
    /// Frame is shorter than MBAP header size (7 bytes)
    case frameTooShort

    /// Protocol ID is not 0x0000
    case invalidProtocolId(UInt16)

    /// Length field doesn't match actual frame size
    case lengthMismatch(declared: UInt16, actual: Int)

    /// Transaction ID mismatch in response
    case transactionIdMismatch(expected: UInt16, got: UInt16)

    /// Unit ID mismatch in response
    case unitIdMismatch(expected: UInt8, got: UInt8)
}

// MARK: - MBAP Builder

/// Builds an MBAP header as bytes.
///
/// Output format (7 bytes, Big Endian):
/// ```
/// [0-1] Transaction ID
/// [2-3] Protocol ID (0x0000)
/// [4-5] Length (Unit ID + PDU length)
/// [6]   Unit ID
/// ```
///
/// - Parameter header: The MBAP header to encode
/// - Returns: 7-byte array containing the MBAP header
@inlinable
public func buildMBAPHeader(_ header: MBAPHeader) -> [UInt8] {
    var bytes = [UInt8]()
    bytes.reserveCapacity(MBAPConstants.headerSize)

    // Transaction ID (Big Endian)
    bytes.append(UInt8(truncatingIfNeeded: header.transactionId >> 8))
    bytes.append(UInt8(truncatingIfNeeded: header.transactionId))

    // Protocol ID (Big Endian) - always 0x0000
    bytes.append(UInt8(truncatingIfNeeded: header.protocolId >> 8))
    bytes.append(UInt8(truncatingIfNeeded: header.protocolId))

    // Length (Big Endian)
    bytes.append(UInt8(truncatingIfNeeded: header.length >> 8))
    bytes.append(UInt8(truncatingIfNeeded: header.length))

    // Unit ID
    bytes.append(header.unitId)

    return bytes
}

/// Builds a complete Modbus TCP ADU (MBAP header + PDU).
///
/// - Parameters:
///   - transactionId: Transaction identifier
///   - unitId: Unit identifier (slave address)
///   - pdu: Protocol Data Unit (function code + data)
/// - Returns: Complete ADU ready for transmission
@inlinable
public func buildModbusTCPADU(
    transactionId: UInt16,
    unitId: UInt8 = 1,
    pdu: [UInt8],
) -> [UInt8] {
    let header = MBAPHeader(
        transactionId: transactionId,
        unitId: unitId,
        pduLength: UInt16(pdu.count),
    )

    var adu = buildMBAPHeader(header)
    adu.append(contentsOf: pdu)
    return adu
}

// MARK: - MBAP Parser

/// Parses an MBAP header from raw bytes.
///
/// Validates:
/// 1. Minimum size (7 bytes)
/// 2. Protocol ID is 0x0000
///
/// - Parameter frame: Raw bytes starting with MBAP header
/// - Returns: Parsed MBAP header
/// - Throws: `MBAPError` if validation fails
@inlinable
public func parseMBAPHeader(_ frame: Span<UInt8>) throws(MBAPError) -> MBAPHeader {
    // Validate minimum size
    guard frame.count >= MBAPConstants.headerSize else {
        throw .frameTooShort
    }

    // Parse fields (Big Endian)
    let transactionId = (UInt16(frame[0]) << 8) | UInt16(frame[1])
    let protocolId = (UInt16(frame[2]) << 8) | UInt16(frame[3])
    let length = (UInt16(frame[4]) << 8) | UInt16(frame[5])
    let unitId = frame[6]

    // Validate protocol ID
    guard protocolId == MBAPConstants.protocolId else {
        throw .invalidProtocolId(protocolId)
    }

    return MBAPHeader(
        transactionId: transactionId,
        protocolId: protocolId,
        length: length,
        unitId: unitId,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseMBAPHeader(_ frame: [UInt8]) throws(MBAPError) -> MBAPHeader {
    try parseMBAPHeader(frame.span)
}

/// Parses and validates a complete Modbus TCP ADU.
///
/// Validates:
/// 1. MBAP header format
/// 2. Length field matches actual frame size
/// 3. Transaction ID matches expected (if provided)
/// 4. Unit ID matches expected (if provided)
///
/// Reference: goburrow/modbus tcpclient.go Verify() validates unit ID:
/// ```go
/// if aduResponse[6] != aduRequest[6] {
///     err = fmt.Errorf("modbus: response unit id '%v' does not match request '%v'", ...)
/// }
/// ```
///
/// - Parameters:
///   - frame: Complete Modbus TCP ADU
///   - expectedTransactionId: Expected transaction ID (optional)
///   - expectedUnitId: Expected unit ID (optional)
/// - Returns: Tuple of (header, PDU as array)
/// - Throws: `MBAPError` if validation fails
@inlinable
public func parseModbusTCPADU(
    _ frame: Span<UInt8>,
    expectedTransactionId: UInt16? = nil,
    expectedUnitId: UInt8? = nil,
) throws(MBAPError) -> (header: MBAPHeader, pdu: [UInt8]) {
    // Parse header
    let header = try parseMBAPHeader(frame)

    // Validate length field
    // Length field = Unit ID (1 byte) + PDU length
    // So: frame.count should be at least headerSize + (length - 1)
    let expectedFrameSize = MBAPConstants.headerSize + Int(header.length) - 1
    guard frame.count >= expectedFrameSize else {
        throw .lengthMismatch(declared: header.length, actual: frame.count - MBAPConstants.headerSize + 1)
    }

    // Validate transaction ID if expected
    if let expected = expectedTransactionId, header.transactionId != expected {
        throw .transactionIdMismatch(expected: expected, got: header.transactionId)
    }

    // Validate unit ID if expected (per goburrow/modbus)
    if let expected = expectedUnitId, header.unitId != expected {
        throw .unitIdMismatch(expected: expected, got: header.unitId)
    }

    // Extract PDU (everything after MBAP header, up to declared length)
    let pduStart = MBAPOffset.pdu
    let pduEnd = pduStart + Int(header.length) - 1 // -1 because length includes unitId
    var pdu = [UInt8]()
    pdu.reserveCapacity(pduEnd - pduStart)
    for i in pduStart ..< pduEnd {
        pdu.append(frame[i])
    }

    return (header, pdu)
}

/// Convenience overload for Array input.
@inlinable
public func parseModbusTCPADU(
    _ frame: [UInt8],
    expectedTransactionId: UInt16? = nil,
    expectedUnitId: UInt8? = nil,
) throws(MBAPError) -> (header: MBAPHeader, pdu: [UInt8]) {
    try parseModbusTCPADU(frame.span, expectedTransactionId: expectedTransactionId, expectedUnitId: expectedUnitId)
}
