// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTU Response Validation (Internal)

/// Minimum valid response size
@usableFromInline
let minRTUResponseSize = RTUFrameSize.minimumResponse

/// Validates minimum frame size
@inlinable
func validateRTUMinimumSize(_ frame: Span<UInt8>) throws(RTUError) {
    guard frame.count >= minRTUResponseSize else {
        throw .frameTooShort
    }
}

/// Validates CRC
@inlinable
func validateRTUCRC(_ frame: Span<UInt8>) throws(RTUError) {
    guard verifyModbusCRC(frame) else {
        throw .invalidCRC
    }
}

/// Checks if response is an exception
@inlinable
func isRTUExceptionResponse(_ frame: Span<UInt8>) -> Bool {
    frame.count >= 3 && (frame[1] & ModbusFunctionCode.exceptionFlag) != 0
}

// MARK: - RTUReadResponse

/// Parsed Modbus RTU Read Holding Registers response.
///
/// Similar to ModbusKit's `ReadRegistersResponse`, but includes raw data bytes
/// for RTU-specific processing (e.g., V5 frame extraction).
public struct RTUReadResponse: Equatable, Sendable {
    // MARK: Lifecycle

    /// Internal initializer for parser
    @usableFromInline
    init(unitId: UInt8, functionCode: UInt8, data: [UInt8]) {
        self.unitId = unitId
        self.functionCode = functionCode
        self.data = data
    }

    // MARK: Public

    /// Unit ID from response
    public let unitId: UInt8
    /// Function code (0x03 or 0x04)
    public let functionCode: UInt8
    /// Register data as raw bytes (Big Endian, 2 bytes per register)
    public let data: [UInt8]

    /// Number of registers in response
    public var count: Int {
        data.count / 2
    }

    /// Register values as UInt16 array.
    ///
    /// Parses raw bytes into register values. Matches `ReadRegistersResponse.registers`.
    public var registers: [UInt16] {
        var result = [UInt16]()
        result.reserveCapacity(count)
        for i in 0 ..< count {
            if let value = value(at: i) {
                result.append(value)
            }
        }
        return result
    }

    /// Converts to ReadRegistersResponse for API compatibility.
    ///
    /// Use when you need response type matching ModbusClient protocol.
    public func toReadRegistersResponse() -> ReadRegistersResponse {
        ReadRegistersResponse(functionCode: functionCode, registers: registers)
    }

    /// Converts to ReadBitsResponse for coil/discrete input operations.
    ///
    /// - Parameter requestedCount: Number of coils/inputs requested (for proper truncation)
    /// - Returns: ReadBitsResponse with unpacked bits
    public func toReadBitsResponse(requestedCount: UInt16) -> ReadBitsResponse {
        var bits = [Bool]()
        bits.reserveCapacity(Int(requestedCount))

        for i in 0 ..< Int(requestedCount) {
            let byteIndex = i / 8
            let bitIndex = i % 8
            // Defense in depth: use safe access
            guard let byte = readUInt8(data, at: byteIndex) else {
                break
            }
            let bit = (byte >> bitIndex) & 0x01
            bits.append(bit != 0)
        }

        let byteCount = UInt8((requestedCount + 7) / 8)
        return ReadBitsResponse(functionCode: functionCode, bits: bits, byteCount: byteCount)
    }

    /// Reads a UInt16 register value at the given index (0-based)
    ///
    /// - Parameter index: Register index (0 = first register)
    /// - Returns: Register value, or nil if index out of bounds
    public func value(at index: Int) -> UInt16? {
        let byteOffset = index * 2
        // Defense in depth: use safe access
        return readUInt16BE(data, at: byteOffset)
    }

    /// Reads a signed Int16 register value at the given index (0-based)
    ///
    /// - Parameter index: Register index (0 = first register)
    /// - Returns: Register value as signed integer, or nil if index out of bounds
    public func signedValue(at index: Int) -> Int16? {
        guard let unsigned = value(at: index) else {
            return nil
        }
        return Int16(bitPattern: unsigned)
    }

    /// Reads a UInt32 value from two consecutive registers (Big Endian)
    ///
    /// - Parameter index: Starting register index
    /// - Returns: 32-bit value (high word at index, low word at index+1)
    public func uint32Value(at index: Int) -> UInt32? {
        guard
            let high = value(at: index),
            let low = value(at: index + 1) else
        {
            return nil
        }
        return (UInt32(high) << 16) | UInt32(low)
    }

    /// Reads a signed Int32 value from two consecutive registers
    ///
    /// - Parameter index: Starting register index
    /// - Returns: 32-bit signed value
    public func int32Value(at index: Int) -> Int32? {
        guard let unsigned = uint32Value(at: index) else {
            return nil
        }
        return Int32(bitPattern: unsigned)
    }
}

// MARK: - RTUWriteResponse

/// Parsed Modbus RTU write response (for FC 0x05, 0x06, 0x0F, 0x10, 0x16).
///
/// Contains the raw response data without interpretation specific to function code.
/// API pattern similar to RTUReadResponse.
public struct RTUWriteResponse: Equatable, Sendable {
    // MARK: Lifecycle

    /// Internal initializer for parser
    @usableFromInline
    init(unitId: UInt8, functionCode: UInt8, data: [UInt8]) {
        self.unitId = unitId
        self.functionCode = functionCode
        self.data = data
    }

    // MARK: Public

    /// Unit ID from response
    public let unitId: UInt8
    /// Function code
    public let functionCode: UInt8
    /// Response data (varies by function code)
    public let data: [UInt8]

    /// For FC 0x05/0x06: First field is address
    public var address: UInt16? {
        guard data.count >= 2 else {
            return nil
        }
        return (UInt16(data[0]) << 8) | UInt16(data[1])
    }

    /// For FC 0x0F/0x10: Second field is quantity
    public var quantity: UInt16? {
        guard data.count >= 4 else {
            return nil
        }
        return (UInt16(data[2]) << 8) | UInt16(data[3])
    }

    /// For FC 0x05/0x06: Second field is value
    public var value: UInt16? {
        guard data.count >= 4 else {
            return nil
        }
        return (UInt16(data[2]) << 8) | UInt16(data[3])
    }

    // MARK: - Conversion Methods

    /// Converts to WriteSingleRegisterResponse (FC 0x06).
    public func toWriteSingleRegisterResponse() -> WriteSingleRegisterResponse {
        WriteSingleRegisterResponse(address: address ?? 0, value: value ?? 0)
    }

    /// Converts to WriteMultipleRegistersResponse (FC 0x10).
    public func toWriteMultipleRegistersResponse() -> WriteMultipleRegistersResponse {
        WriteMultipleRegistersResponse(address: address ?? 0, quantity: quantity ?? 0)
    }

    /// Converts to WriteSingleCoilResponse (FC 0x05).
    public func toWriteSingleCoilResponse() -> WriteSingleCoilResponse {
        let coilValue = value == CoilOn
        return WriteSingleCoilResponse(address: address ?? 0, value: coilValue)
    }

    /// Converts to WriteMultipleCoilsResponse (FC 0x0F).
    public func toWriteMultipleCoilsResponse() -> WriteMultipleCoilsResponse {
        WriteMultipleCoilsResponse(address: address ?? 0, quantity: quantity ?? 0)
    }

    /// Converts to MaskWriteRegisterResponse (FC 0x16).
    public func toMaskWriteRegisterResponse() -> MaskWriteRegisterResponse {
        let andMask = value ?? 0
        let orMask: UInt16 = data.count >= 6
            ? (UInt16(data[4]) << 8) | UInt16(data[5])
            : 0
        return MaskWriteRegisterResponse(address: address ?? 0, andMask: andMask, orMask: orMask)
    }
}
