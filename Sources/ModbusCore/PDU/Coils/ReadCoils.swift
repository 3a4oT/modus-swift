// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Read Coils Builder

/// Builds a Read Coils request PDU (Function Code 0x01).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x01)
/// [1-2] Starting Address
/// [3-4] Quantity of Coils (1-2000)
/// ```
///
/// API based on pymodbus `read_coils(address, count)`.
///
/// - Parameters:
///   - address: Starting coil address (0-65535)
///   - count: Number of coils to read (1-2000)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadCoilsPDU(
    address: UInt16,
    count: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.readRequest)

    // Function code
    pdu.append(ModbusFunctionCode.readCoils)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: count >> 8))
    pdu.append(UInt8(truncatingIfNeeded: count))

    return pdu
}

// MARK: - Read Discrete Inputs Builder

/// Builds a Read Discrete Inputs request PDU (Function Code 0x02).
///
/// PDU format (5 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x02)
/// [1-2] Starting Address
/// [3-4] Quantity of Inputs (1-2000)
/// ```
///
/// API based on pymodbus `read_discrete_inputs(address, count)`.
///
/// - Parameters:
///   - address: Starting input address (0-65535)
///   - count: Number of inputs to read (1-2000)
/// - Returns: 5-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadDiscreteInputsPDU(
    address: UInt16,
    count: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.readRequest)

    // Function code
    pdu.append(ModbusFunctionCode.readDiscreteInputs)

    // Starting address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // Quantity (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: count >> 8))
    pdu.append(UInt8(truncatingIfNeeded: count))

    return pdu
}

// MARK: - ReadBitsResponse

/// Parsed response for Read Coils (0x01) or Read Discrete Inputs (0x02).
///
/// Coil/discrete input values are packed as bits, LSB first per byte.
/// API based on pymodbus `ReadCoilsResponse.bits`.
public struct ReadBitsResponse: Equatable, Sendable {
    // MARK: Lifecycle

    /// Internal initializer for parser
    @usableFromInline
    init(functionCode: UInt8, bits: [Bool], byteCount: UInt8) {
        self.functionCode = functionCode
        self.bits = bits
        self.byteCount = byteCount
    }

    // MARK: Public

    /// Function code from response (0x01 or 0x02)
    public let functionCode: UInt8

    /// Coil/input values as booleans (unpacked from bytes).
    ///
    /// Matches pymodbus `response.bits` property.
    /// Note: Length equals requested count (padded bits excluded).
    public let bits: [Bool]

    /// Byte count from response (raw, before unpacking)
    public let byteCount: UInt8

    /// Number of coils/inputs in response
    public var count: Int {
        bits.count
    }

    /// Get value at specific index.
    ///
    /// - Parameter index: Coil/input index (0-based)
    /// - Returns: Boolean value, or nil if out of bounds
    public func value(at index: Int) -> Bool? {
        guard index >= 0, index < bits.count else {
            return nil
        }
        return bits[index]
    }
}

// MARK: - Read Coils/Discrete Inputs Parser

/// Parses a Read Coils/Discrete Inputs response PDU.
///
/// Response PDU format:
/// ```
/// [0]   Function Code (0x01 or 0x02)
/// [1]   Byte Count (N = ceil(quantity/8))
/// [2..] Coil/Input Data (N bytes, LSB first per byte)
/// ```
///
/// Bit packing (per Modbus spec):
/// - LSB of first byte = first coil
/// - Remaining bits padded with zeros
///
/// - Parameters:
///   - pdu: PDU bytes (without MBAP header)
///   - expectedFunction: Expected function code (0x01 or 0x02)
///   - requestedCount: Number of coils/inputs requested (for proper truncation)
/// - Returns: Parsed response with bits
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseReadBitsPDU(
    _ pdu: Span<UInt8>,
    expectedFunction: UInt8 = ModbusFunctionCode.readCoils,
    requestedCount: UInt16,
) throws(PDUError) -> ReadBitsResponse {
    // Validate minimum size
    guard pdu.count >= PDUSize.minimumReadResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        guard pdu.count >= PDUSize.exceptionResponse else {
            throw .pduTooShort
        }
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Validate function code
    guard functionCode == expectedFunction else {
        throw .unexpectedFunctionCode(expected: expectedFunction, got: functionCode)
    }

    // Get byte count
    let byteCount = pdu[1]

    // Validate byte count matches requested coils
    // Expected bytes = ceil(requestedCount / 8)
    let expectedByteCount = UInt8((requestedCount + 7) / 8)
    guard byteCount == expectedByteCount else {
        throw .byteCountMismatch(expected: expectedByteCount, got: byteCount)
    }

    // Validate PDU has enough bytes
    let expectedPDUSize = 2 + Int(byteCount)
    guard pdu.count >= expectedPDUSize else {
        throw .pduTooShort
    }

    // Unpack bits (LSB first per byte)
    var bits = [Bool]()
    bits.reserveCapacity(Int(requestedCount))

    for i in 0 ..< Int(requestedCount) {
        let byteIndex = 2 + (i / 8)
        let bitIndex = i % 8
        // Defense in depth: use safe access even though bounds were validated above
        guard let byte = readUInt8(pdu, at: byteIndex) else {
            throw .pduTooShort
        }
        let bit = (byte >> bitIndex) & 0x01
        bits.append(bit != 0)
    }

    return ReadBitsResponse(
        functionCode: functionCode,
        bits: bits,
        byteCount: byteCount,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseReadBitsPDU(
    _ pdu: [UInt8],
    expectedFunction: UInt8 = ModbusFunctionCode.readCoils,
    requestedCount: UInt16,
) throws(PDUError) -> ReadBitsResponse {
    try parseReadBitsPDU(pdu.span, expectedFunction: expectedFunction, requestedCount: requestedCount)
}
