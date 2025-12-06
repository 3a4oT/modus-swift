// MARK: - ASCIIFrameConstants

// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

/// ASCII frame markers and limits per Modbus Serial Line spec V1.02.
public enum ASCIIFrameConstants: Sendable {
    /// Start of frame marker: colon `:` (0x3A)
    public static let startMarker: UInt8 = 0x3A // ':'

    /// End of frame: Carriage Return (0x0D)
    public static let carriageReturn: UInt8 = 0x0D // '\r'

    /// End of frame: Line Feed (0x0A)
    public static let lineFeed: UInt8 = 0x0A // '\n'

    /// Minimum ASCII frame size: `:` + 2 addr + 2 func + 2 LRC + CR + LF = 9 chars
    public static let minimumFrameSize = 9

    /// Maximum ASCII frame size per spec: 513 characters
    public static let maximumFrameSize = 513

    /// Maximum inter-character timeout: 1 second per spec
    public static let interCharacterTimeout = 1.0
}

// MARK: - Hex Encoding (Nibble to ASCII)

/// Converts a nibble (0-15) to its ASCII hex character.
///
/// Reference: libmodbus `nibble_to_hex_ascii()`
///
/// - Precondition: nibble must be 0-15
/// - Parameter nibble: Value 0-15
/// - Returns: ASCII character '0'-'9' or 'A'-'F'
@inlinable
public func nibbleToHexASCII(_ nibble: UInt8) -> UInt8 {
    assert(nibble <= 15, "nibble must be 0-15, got \(nibble)")
    if nibble < 10 {
        return nibble + 0x30 // '0' = 0x30
    } else {
        return nibble - 10 + 0x41 // 'A' = 0x41
    }
}

/// Converts an ASCII hex character to its nibble value.
///
/// - Parameter ascii: ASCII character '0'-'9', 'A'-'F', or 'a'-'f'
/// - Returns: Value 0-15, or nil if invalid
@inlinable
public func hexASCIIToNibble(_ ascii: UInt8) -> UInt8? {
    switch ascii {
    case 0x30 ... 0x39: // '0'-'9'
        ascii - 0x30
    case 0x41 ... 0x46: // 'A'-'F'
        ascii - 0x41 + 10
    case 0x61 ... 0x66: // 'a'-'f'
        ascii - 0x61 + 10
    default:
        nil
    }
}

// MARK: - Byte Encoding/Decoding

/// Encodes a single byte as two ASCII hex characters.
///
/// - Parameter byte: Byte to encode
/// - Returns: Tuple of (high nibble char, low nibble char)
@inlinable
public func byteToHexASCII(_ byte: UInt8) -> (UInt8, UInt8) {
    let highNibble = (byte >> 4) & 0x0F
    let lowNibble = byte & 0x0F
    return (nibbleToHexASCII(highNibble), nibbleToHexASCII(lowNibble))
}

/// Decodes two ASCII hex characters to a single byte.
///
/// - Parameters:
///   - high: High nibble ASCII character
///   - low: Low nibble ASCII character
/// - Returns: Decoded byte, or nil if invalid characters
@inlinable
public func hexASCIIToByte(high: UInt8, low: UInt8) -> UInt8? {
    guard
        let highNibble = hexASCIIToNibble(high),
        let lowNibble = hexASCIIToNibble(low) else
    {
        return nil
    }
    return (highNibble << 4) | lowNibble
}

// MARK: - ASCIIFrameError

/// Errors that can occur during ASCII frame encoding/decoding.
public enum ASCIIFrameError: Error, Equatable, Sendable {
    /// Frame is too short to be valid
    case frameTooShort

    /// Frame is too long (exceeds 513 characters)
    case frameTooLong

    /// Missing start marker (colon)
    case missingStartMarker

    /// Missing end markers (CR LF)
    case missingEndMarkers

    /// Invalid hex character in frame
    case invalidHexCharacter

    /// Odd number of hex characters (must be pairs)
    case oddHexCharacterCount

    /// LRC checksum mismatch
    case invalidLRC
}

// MARK: - ASCII Frame Encoding

/// Encodes a binary Modbus message to ASCII frame format.
///
/// Frame structure: `:` + hex(address + function + data) + hex(LRC) + CR + LF
///
/// Reference: Modbus Serial Line Protocol V1.02, Section 2.5
///
/// - Parameter message: Binary message (address + function + data, NO LRC)
/// - Returns: Complete ASCII frame as bytes
/// - Throws: `ASCIIFrameError.frameTooLong` if result exceeds max size
public func encodeASCIIFrame(_ message: [UInt8]) throws(ASCIIFrameError) -> [UInt8] {
    // Calculate LRC over message
    let lrc = calculateModbusLRC(message)

    // Calculate output size: 1 (colon) + 2*message + 2 (LRC) + 2 (CRLF)
    let outputSize = 1 + (message.count * 2) + 2 + 2

    guard outputSize <= ASCIIFrameConstants.maximumFrameSize else {
        throw .frameTooLong
    }

    var frame = [UInt8]()
    frame.reserveCapacity(outputSize)

    // Start marker
    frame.append(ASCIIFrameConstants.startMarker)

    // Encode message bytes as hex
    for byte in message {
        let (high, low) = byteToHexASCII(byte)
        frame.append(high)
        frame.append(low)
    }

    // Encode LRC as hex
    let (lrcHigh, lrcLow) = byteToHexASCII(lrc)
    frame.append(lrcHigh)
    frame.append(lrcLow)

    // End markers
    frame.append(ASCIIFrameConstants.carriageReturn)
    frame.append(ASCIIFrameConstants.lineFeed)

    return frame
}

// MARK: - ASCII Frame Decoding

/// Decodes an ASCII frame to binary message format.
///
/// Validates frame structure, decodes hex, and verifies LRC.
///
/// - Parameter frame: Complete ASCII frame (including `:` and CR LF)
/// - Returns: Binary message (address + function + data, NO LRC)
/// - Throws: `ASCIIFrameError` if frame is invalid
public func decodeASCIIFrame(_ frame: Span<UInt8>) throws(ASCIIFrameError) -> [UInt8] {
    // Validate minimum size
    guard frame.count >= ASCIIFrameConstants.minimumFrameSize else {
        throw .frameTooShort
    }

    // Validate maximum size
    guard frame.count <= ASCIIFrameConstants.maximumFrameSize else {
        throw .frameTooLong
    }

    // Validate start marker
    guard
        let startByte = readUInt8(frame, at: 0),
        startByte == ASCIIFrameConstants.startMarker else
    {
        throw .missingStartMarker
    }

    // Validate end markers
    guard
        let crByte = readUInt8(frame, at: frame.count - 2),
        let lfByte = readUInt8(frame, at: frame.count - 1),
        crByte == ASCIIFrameConstants.carriageReturn,
        lfByte == ASCIIFrameConstants.lineFeed else
    {
        throw .missingEndMarkers
    }

    // Extract hex portion (between ':' and CR LF)
    let hexStart = 1
    let hexEnd = frame.count - 2
    let hexLength = hexEnd - hexStart

    // Must have even number of hex characters
    guard hexLength >= 4, hexLength % 2 == 0 else {
        throw .oddHexCharacterCount
    }

    // Decode hex pairs to bytes
    let byteCount = hexLength / 2
    var bytes = [UInt8]()
    bytes.reserveCapacity(byteCount)

    for i in 0 ..< byteCount {
        let hexOffset = hexStart + (i * 2)
        guard
            let highChar = readUInt8(frame, at: hexOffset),
            let lowChar = readUInt8(frame, at: hexOffset + 1),
            let byte = hexASCIIToByte(high: highChar, low: lowChar) else
        {
            throw .invalidHexCharacter
        }
        bytes.append(byte)
    }

    // Verify LRC (last byte is LRC, rest is message)
    guard verifyModbusLRC(bytes) else {
        throw .invalidLRC
    }

    // Return message without LRC
    return Array(bytes.dropLast())
}

/// Decodes an ASCII frame (convenience overload for Array).
///
/// - Parameter frame: Complete ASCII frame
/// - Returns: Binary message (address + function + data, NO LRC)
/// - Throws: `ASCIIFrameError` if frame is invalid
@inlinable
public func decodeASCIIFrame(_ frame: [UInt8]) throws(ASCIIFrameError) -> [UInt8] {
    try decodeASCIIFrame(frame.span)
}

// MARK: - ASCII Frame Builder (RTU to ASCII)

/// Builds a complete ASCII frame from RTU-style components.
///
/// This is a convenience function that takes the same parameters as RTU frame builders
/// and produces an ASCII frame.
///
/// - Parameters:
///   - unitId: Slave/unit address
///   - pdu: Protocol Data Unit (function code + data)
/// - Returns: Complete ASCII frame
/// - Throws: `ASCIIFrameError.frameTooLong` if result exceeds max size
public func buildASCIIFrame(unitId: UInt8, pdu: [UInt8]) throws(ASCIIFrameError) -> [UInt8] {
    var message = [UInt8]()
    message.reserveCapacity(1 + pdu.count)
    message.append(unitId)
    message.append(contentsOf: pdu)
    return try encodeASCIIFrame(message)
}

// MARK: - ASCII Response Parsing

/// Parses an ASCII frame and extracts unit ID and PDU.
///
/// - Parameter frame: Complete ASCII frame
/// - Returns: Tuple of (unitId, pdu)
/// - Throws: `ASCIIFrameError` if frame is invalid
public func parseASCIIFrame(_ frame: [UInt8]) throws(ASCIIFrameError) -> (unitId: UInt8, pdu: [UInt8]) {
    let message = try decodeASCIIFrame(frame)

    guard message.count >= 2 else {
        throw .frameTooShort
    }

    let unitId = message[0]
    let pdu = Array(message.dropFirst())

    return (unitId, pdu)
}
