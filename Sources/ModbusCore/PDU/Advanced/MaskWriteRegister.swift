// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - Mask Write Register Builder

/// Builds a Mask Write Register request PDU (Function Code 0x16).
///
/// PDU format (7 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x16)
/// [1-2] Reference Address
/// [3-4] AND Mask
/// [5-6] OR Mask
/// ```
///
/// The formula applied: `Result = (Current_Value AND And_Mask) OR Or_Mask`
///
/// API based on pymodbus `mask_write_register(address, and_mask, or_mask)`.
///
/// - Parameters:
///   - address: Register address (0-65535)
///   - andMask: AND mask for bitwise operation
///   - orMask: OR mask for bitwise operation
/// - Returns: 7-byte PDU ready for MBAP wrapping
@inlinable
public func buildMaskWriteRegisterPDU(
    address: UInt16,
    andMask: UInt16,
    orMask: UInt16,
) -> [UInt8] {
    var pdu = [UInt8]()
    pdu.reserveCapacity(PDUSize.maskWriteRegister)

    // Function code
    pdu.append(ModbusFunctionCode.maskWriteRegister)

    // Reference address (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: address >> 8))
    pdu.append(UInt8(truncatingIfNeeded: address))

    // AND mask (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: andMask >> 8))
    pdu.append(UInt8(truncatingIfNeeded: andMask))

    // OR mask (Big Endian)
    pdu.append(UInt8(truncatingIfNeeded: orMask >> 8))
    pdu.append(UInt8(truncatingIfNeeded: orMask))

    return pdu
}

// MARK: - MaskWriteRegisterResponse

/// Parsed response for Mask Write Register (0x16).
///
/// Response is echo of request: address + masks.
/// API based on pymodbus `MaskWriteRegisterResponse`.
public struct MaskWriteRegisterResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(address: UInt16, andMask: UInt16, orMask: UInt16) {
        self.address = address
        self.andMask = andMask
        self.orMask = orMask
    }

    // MARK: Public

    /// Register address that was written
    public let address: UInt16

    /// AND mask that was applied
    public let andMask: UInt16

    /// OR mask that was applied
    public let orMask: UInt16
}

// MARK: - Mask Write Register Parser

/// Parses a Mask Write Register response PDU (0x16).
///
/// Response PDU format (7 bytes, Big Endian):
/// ```
/// [0]   Function Code (0x16)
/// [1-2] Reference Address (echo)
/// [3-4] AND Mask (echo)
/// [5-6] OR Mask (echo)
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with address and masks
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseMaskWriteRegisterPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> MaskWriteRegisterResponse {
    // Validate minimum size for exception check
    guard pdu.count >= PDUSize.exceptionResponse else {
        throw .pduTooShort
    }

    let functionCode = pdu[0]

    // Check for exception response FIRST
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        let exceptionCode = pdu[1]
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Validate full response size (7 bytes)
    guard pdu.count >= PDUSize.maskWriteRegister else {
        throw .pduTooShort
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.maskWriteRegister else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.maskWriteRegister,
            got: functionCode,
        )
    }

    // Parse address and masks (Big Endian)
    // Safety: guard above ensures pdu.count >= 7
    guard
        let address = readUInt16BE(pdu, at: 1),
        let andMask = readUInt16BE(pdu, at: 3),
        let orMask = readUInt16BE(pdu, at: 5) else
    {
        throw .pduTooShort
    }

    return MaskWriteRegisterResponse(address: address, andMask: andMask, orMask: orMask)
}

/// Convenience overload for Array input.
@inlinable
public func parseMaskWriteRegisterPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> MaskWriteRegisterResponse {
    try parseMaskWriteRegisterPDU(pdu.span)
}
