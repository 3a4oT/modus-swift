// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus ASCII frame encoding/decoding.
///
/// Frame format: `:` + hex(address + function + data) + hex(LRC) + CR + LF
///
/// References:
/// - Modbus Serial Line Protocol V1.02, Section 2.5
/// - libmodbus modbus-ascii.c
/// - https://www.modbustools.com/modbus.html
@Suite("Modbus ASCII Frame")
struct ASCIIFrameTests {
    // MARK: - Nibble Conversion

    @Test("Nibble to hex ASCII - digits")
    func nibbleToHexDigits() {
        #expect(nibbleToHexASCII(0) == 0x30) // '0'
        #expect(nibbleToHexASCII(1) == 0x31) // '1'
        #expect(nibbleToHexASCII(9) == 0x39) // '9'
    }

    @Test("Nibble to hex ASCII - letters")
    func nibbleToHexLetters() {
        #expect(nibbleToHexASCII(10) == 0x41) // 'A'
        #expect(nibbleToHexASCII(11) == 0x42) // 'B'
        #expect(nibbleToHexASCII(15) == 0x46) // 'F'
    }

    @Test("Hex ASCII to nibble - digits")
    func hexToNibbleDigits() {
        #expect(hexASCIIToNibble(0x30) == 0) // '0'
        #expect(hexASCIIToNibble(0x31) == 1) // '1'
        #expect(hexASCIIToNibble(0x39) == 9) // '9'
    }

    @Test("Hex ASCII to nibble - uppercase letters")
    func hexToNibbleUppercase() {
        #expect(hexASCIIToNibble(0x41) == 10) // 'A'
        #expect(hexASCIIToNibble(0x42) == 11) // 'B'
        #expect(hexASCIIToNibble(0x46) == 15) // 'F'
    }

    @Test("Hex ASCII to nibble - lowercase letters")
    func hexToNibbleLowercase() {
        #expect(hexASCIIToNibble(0x61) == 10) // 'a'
        #expect(hexASCIIToNibble(0x62) == 11) // 'b'
        #expect(hexASCIIToNibble(0x66) == 15) // 'f'
    }

    @Test("Hex ASCII to nibble - invalid")
    func hexToNibbleInvalid() {
        #expect(hexASCIIToNibble(0x47) == nil) // 'G'
        #expect(hexASCIIToNibble(0x2F) == nil) // '/'
        #expect(hexASCIIToNibble(0x3A) == nil) // ':'
        #expect(hexASCIIToNibble(0x67) == nil) // 'g'
    }

    // MARK: - Byte Encoding/Decoding

    @Test("Byte to hex ASCII")
    func byteToHex() {
        let (h1, l1) = byteToHexASCII(0x00)
        #expect(h1 == 0x30 && l1 == 0x30) // "00"

        let (h2, l2) = byteToHexASCII(0xAB)
        #expect(h2 == 0x41 && l2 == 0x42) // "AB"

        let (h3, l3) = byteToHexASCII(0xFF)
        #expect(h3 == 0x46 && l3 == 0x46) // "FF"

        let (h4, l4) = byteToHexASCII(0x3C)
        #expect(h4 == 0x33 && l4 == 0x43) // "3C"
    }

    @Test("Hex ASCII to byte")
    func hexToByte() {
        #expect(hexASCIIToByte(high: 0x30, low: 0x30) == 0x00) // "00"
        #expect(hexASCIIToByte(high: 0x41, low: 0x42) == 0xAB) // "AB"
        #expect(hexASCIIToByte(high: 0x46, low: 0x46) == 0xFF) // "FF"
        #expect(hexASCIIToByte(high: 0x33, low: 0x43) == 0x3C) // "3C"
    }

    @Test("Hex ASCII to byte - lowercase")
    func hexToByteLowercase() {
        #expect(hexASCIIToByte(high: 0x61, low: 0x62) == 0xAB) // "ab"
        #expect(hexASCIIToByte(high: 0x66, low: 0x66) == 0xFF) // "ff"
    }

    @Test("Hex ASCII to byte - mixed case")
    func hexToByteMixedCase() {
        #expect(hexASCIIToByte(high: 0x41, low: 0x62) == 0xAB) // "Ab"
        #expect(hexASCIIToByte(high: 0x61, low: 0x42) == 0xAB) // "aB"
    }

    @Test("Hex ASCII to byte - invalid")
    func hexToByteInvalid() {
        #expect(hexASCIIToByte(high: 0x47, low: 0x30) == nil) // "G0"
        #expect(hexASCIIToByte(high: 0x30, low: 0x47) == nil) // "0G"
    }

    // MARK: - Frame Encoding

    @Test("Encode modbustools.com example")
    func encodeModbustoolsExample() throws {
        // Read 13 coils from address 10, slave 4
        // Expected: :040100 0A00 0DE4 CR LF
        let message: [UInt8] = [0x04, 0x01, 0x00, 0x0A, 0x00, 0x0D]
        let frame = try encodeASCIIFrame(message)

        // Expected ASCII bytes
        let expected: [UInt8] = [
            0x3A, // ':'
            0x30, 0x34, // "04" - slave
            0x30, 0x31, // "01" - function
            0x30, 0x30, // "00" - address high
            0x30, 0x41, // "0A" - address low
            0x30, 0x30, // "00" - count high
            0x30, 0x44, // "0D" - count low
            0x45, 0x34, // "E4" - LRC
            0x0D, 0x0A, // CR LF
        ]

        #expect(frame == expected)
    }

    @Test("Encode spec example")
    func encodeSpecExample() throws {
        // F7 03 13 89 00 0A → LRC 60
        let message: [UInt8] = [0xF7, 0x03, 0x13, 0x89, 0x00, 0x0A]
        let frame = try encodeASCIIFrame(message)

        // Frame should start with ':' and end with CR LF
        #expect(frame.first == 0x3A)
        #expect(frame[frame.count - 2] == 0x0D)
        #expect(frame[frame.count - 1] == 0x0A)

        // LRC should be "60" (0x36, 0x30)
        #expect(frame[frame.count - 4] == 0x36) // '6'
        #expect(frame[frame.count - 3] == 0x30) // '0'
    }

    @Test("Encode read holding registers")
    func encodeReadHoldingRegisters() throws {
        // Slave 1, Function 3, Start 0, Count 10
        let message: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]
        let frame = try encodeASCIIFrame(message)

        // LRC = 0xF2
        // Expected: :010300 00000AF2 CR LF
        let expected: [UInt8] = [
            0x3A, // ':'
            0x30, 0x31, // "01"
            0x30, 0x33, // "03"
            0x30, 0x30, // "00"
            0x30, 0x30, // "00"
            0x30, 0x30, // "00"
            0x30, 0x41, // "0A"
            0x46, 0x32, // "F2" - LRC
            0x0D, 0x0A, // CR LF
        ]

        #expect(frame == expected)
    }

    // MARK: - Frame Decoding

    @Test("Decode modbustools.com example")
    func decodeModbustoolsExample() throws {
        let frame: [UInt8] = [
            0x3A, // ':'
            0x30, 0x34, // "04"
            0x30, 0x31, // "01"
            0x30, 0x30, // "00"
            0x30, 0x41, // "0A"
            0x30, 0x30, // "00"
            0x30, 0x44, // "0D"
            0x45, 0x34, // "E4" - LRC
            0x0D, 0x0A, // CR LF
        ]

        let message = try decodeASCIIFrame(frame)

        #expect(message == [0x04, 0x01, 0x00, 0x0A, 0x00, 0x0D])
    }

    @Test("Decode with lowercase hex")
    func decodeLowercase() throws {
        // Same as above but lowercase
        let frame: [UInt8] = [
            0x3A, // ':'
            0x30, 0x34, // "04"
            0x30, 0x31, // "01"
            0x30, 0x30, // "00"
            0x30, 0x61, // "0a" - lowercase
            0x30, 0x30, // "00"
            0x30, 0x64, // "0d" - lowercase
            0x65, 0x34, // "e4" - LRC lowercase
            0x0D, 0x0A, // CR LF
        ]

        let message = try decodeASCIIFrame(frame)

        #expect(message == [0x04, 0x01, 0x00, 0x0A, 0x00, 0x0D])
    }

    // MARK: - Frame Decoding Errors

    @Test("Decode error - frame too short")
    func decodeFrameTooShort() {
        let shortFrame: [UInt8] = [0x3A, 0x30, 0x31, 0x0D, 0x0A]

        #expect(throws: ASCIIFrameError.frameTooShort) {
            try decodeASCIIFrame(shortFrame)
        }
    }

    @Test("Decode error - missing start marker")
    func decodeMissingStartMarker() {
        let frame: [UInt8] = [
            0x30, 0x34, // Missing ':'
            0x30, 0x31,
            0x30, 0x30,
            0x30, 0x41,
            0x30, 0x30,
            0x30, 0x44,
            0x45, 0x34,
            0x0D, 0x0A,
        ]

        #expect(throws: ASCIIFrameError.missingStartMarker) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Decode error - missing end markers")
    func decodeMissingEndMarkers() {
        let frame: [UInt8] = [
            0x3A,
            0x30, 0x34,
            0x30, 0x31,
            0x30, 0x30,
            0x30, 0x41,
            0x30, 0x30,
            0x30, 0x44,
            0x45, 0x34,
            0x00, 0x00, // Wrong end markers
        ]

        #expect(throws: ASCIIFrameError.missingEndMarkers) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Decode error - invalid hex character")
    func decodeInvalidHexCharacter() {
        let frame: [UInt8] = [
            0x3A,
            0x30, 0x47, // "0G" - invalid
            0x30, 0x31,
            0x46, 0x32, // LRC (dummy)
            0x0D, 0x0A,
        ]

        #expect(throws: ASCIIFrameError.invalidHexCharacter) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Decode error - invalid LRC")
    func decodeInvalidLRC() {
        let frame: [UInt8] = [
            0x3A,
            0x30, 0x31, // "01"
            0x30, 0x33, // "03"
            0x30, 0x30, // "00" - wrong LRC
            0x0D, 0x0A,
        ]

        #expect(throws: ASCIIFrameError.invalidLRC) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Decode error - odd hex character count")
    func decodeOddHexCount() {
        // 7 hex chars between ':' and CRLF (odd number)
        let frame: [UInt8] = [
            0x3A,
            0x30, 0x31, 0x30, // "010" - 3 chars
            0x33, 0x46, 0x32, // "3F2" - 3 more = 6 total, need LRC
            0x30, // 1 more = 7 (odd)
            0x0D, 0x0A,
        ]

        #expect(throws: ASCIIFrameError.oddHexCharacterCount) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Decode error - frame too long")
    func decodeFrameTooLong() {
        // Create frame exceeding 513 chars
        var frame: [UInt8] = [0x3A]
        // Add 520 hex chars (260 bytes worth)
        for _ in 0 ..< 520 {
            frame.append(0x30) // '0'
        }
        frame.append(0x0D)
        frame.append(0x0A)

        #expect(frame.count > ASCIIFrameConstants.maximumFrameSize)
        #expect(throws: ASCIIFrameError.frameTooLong) {
            try decodeASCIIFrame(frame)
        }
    }

    @Test("Encode error - frame too long")
    func encodeFrameTooLong() {
        // Create message that would exceed max frame size
        // Max frame = 513, overhead = 5 (: + LRC hex + CRLF)
        // Max hex content = 508 chars = 254 bytes
        // So 255 bytes should fail
        let message = [UInt8](repeating: 0xFF, count: 255)

        #expect(throws: ASCIIFrameError.frameTooLong) {
            try encodeASCIIFrame(message)
        }
    }

    // MARK: - Round Trip

    @Test("Encode then decode returns original message")
    func roundTrip() throws {
        let testMessages: [[UInt8]] = [
            [0x01, 0x03, 0x00, 0x00, 0x00, 0x0A],
            [0xF7, 0x03, 0x13, 0x89, 0x00, 0x0A],
            [0x04, 0x01, 0x00, 0x0A, 0x00, 0x0D],
            [0xFF, 0xFF, 0xFF, 0xFF],
            [0x00, 0x00],
        ]

        for original in testMessages {
            let encoded = try encodeASCIIFrame(original)
            let decoded = try decodeASCIIFrame(encoded)
            #expect(decoded == original, "Round trip failed for: \(original)")
        }
    }

    // MARK: - Build Frame

    @Test("Build ASCII frame from unit ID and PDU")
    func buildFrame() throws {
        let unitId: UInt8 = 0x01
        let pdu: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x0A] // Read holding registers

        let frame = try buildASCIIFrame(unitId: unitId, pdu: pdu)

        // Decode and verify
        let (decodedUnitId, decodedPDU) = try parseASCIIFrame(frame)
        #expect(decodedUnitId == unitId)
        #expect(decodedPDU == pdu)
    }

    // MARK: - Parse Frame

    @Test("Parse ASCII frame extracts unit ID and PDU")
    func parseFrame() throws {
        let frame: [UInt8] = [
            0x3A,
            0x30, 0x34, // Unit ID: 04
            0x30, 0x31, // Function: 01
            0x30, 0x30, 0x30, 0x41, // Address: 00 0A
            0x30, 0x30, 0x30, 0x44, // Count: 00 0D
            0x45, 0x34, // LRC
            0x0D, 0x0A,
        ]

        let (unitId, pdu) = try parseASCIIFrame(frame)

        #expect(unitId == 0x04)
        #expect(pdu == [0x01, 0x00, 0x0A, 0x00, 0x0D])
    }

    // MARK: - Constants

    @Test("Frame constants are correct")
    func frameConstants() {
        #expect(ASCIIFrameConstants.startMarker == 0x3A)
        #expect(ASCIIFrameConstants.carriageReturn == 0x0D)
        #expect(ASCIIFrameConstants.lineFeed == 0x0A)
        #expect(ASCIIFrameConstants.minimumFrameSize == 9)
        #expect(ASCIIFrameConstants.maximumFrameSize == 513)
    }
}
