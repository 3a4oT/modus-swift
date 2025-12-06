// MARK: - MEIType

// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

/// MEI (Modbus Encapsulated Interface) type codes.
///
/// Reference: Modbus Application Protocol Specification V1.1b3, Section 6.21
public enum MEIType: Sendable {
    /// Read Device Identification (0x0E)
    public static let readDeviceIdentification: UInt8 = 0x0E
}

// MARK: - ReadDeviceIdCode

/// Read Device ID codes for FC 0x2B/0x0E.
///
/// Determines which objects to read from the device.
///
/// Reference: Modbus spec Table 5-1
public enum ReadDeviceIdCode: UInt8, Sendable {
    /// Basic device identification (Objects 0x00-0x02)
    /// VendorName, ProductCode, MajorMinorRevision
    case basic = 0x01

    /// Regular device identification (Objects 0x00-0x06)
    /// Basic + VendorUrl, ProductName, ModelName, UserApplicationName
    case regular = 0x02

    /// Extended device identification (Objects 0x00-0x06 + 0x80-0xFF)
    /// Regular + vendor-specific objects
    case extended = 0x03

    /// Specific identification object
    /// Read a single specific object by ID
    case specific = 0x04
}

// MARK: - DeviceObjectId

/// Standard Device Object IDs for Read Device Identification.
///
/// Reference: Modbus spec Table 5-2
public enum DeviceObjectId: UInt8, Sendable, CaseIterable {
    /// Vendor Name (mandatory for Basic)
    case vendorName = 0x00
    /// Product Code (mandatory for Basic)
    case productCode = 0x01
    /// Major Minor Revision (mandatory for Basic)
    case majorMinorRevision = 0x02
    /// Vendor URL (optional, Regular)
    case vendorUrl = 0x03
    /// Product Name (optional, Regular)
    case productName = 0x04
    /// Model Name (optional, Regular)
    case modelName = 0x05
    /// User Application Name (optional, Regular)
    case userApplicationName = 0x06
}

// MARK: - DeviceConformityLevel

/// Device conformity level for Read Device Identification.
///
/// Indicates which identification level the device supports.
///
/// Reference: Modbus spec Section 6.21
public enum DeviceConformityLevel: UInt8, Sendable {
    /// Basic identification only (mandatory objects 0x00-0x02)
    case basic = 0x01
    /// Regular identification (objects 0x00-0x06)
    case regular = 0x02
    /// Extended identification (objects 0x00-0xFF)
    case extended = 0x03
    /// Basic + individual access supported
    case basicIndividual = 0x81
    /// Regular + individual access supported
    case regularIndividual = 0x82
    /// Extended + individual access supported
    case extendedIndividual = 0x83
}

// MARK: - Device Identification Request Builder

/// Builds a Read Device Identification request PDU (Function Code 0x2B, MEI 0x0E).
///
/// PDU format (4 bytes):
/// ```
/// [0]   Function Code (0x2B)
/// [1]   MEI Type (0x0E)
/// [2]   Read Device ID Code (0x01-0x04)
/// [3]   Object ID (starting object or specific object)
/// ```
///
/// API based on pymodbus `ReadDeviceInformationRequest`.
///
/// - Parameters:
///   - readCode: Read device ID code (.basic, .regular, .extended, .specific)
///   - objectId: Starting object ID (default 0x00) or specific object for .specific
/// - Returns: 4-byte PDU ready for MBAP wrapping
@inlinable
public func buildReadDeviceIdentificationPDU(
    readCode: ReadDeviceIdCode,
    objectId: UInt8 = 0x00,
) -> [UInt8] {
    [
        ModbusFunctionCode.encapsulatedInterface,
        MEIType.readDeviceIdentification,
        readCode.rawValue,
        objectId,
    ]
}

// MARK: - DeviceIdentificationResponse

/// Parsed response for Read Device Identification (0x2B/0x0E).
///
/// Contains device information objects as key-value pairs.
/// API based on pymodbus `ReadDeviceInformationResponse`.
public struct DeviceIdentificationResponse: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        conformityLevel: UInt8,
        moreFollows: Bool,
        nextObjectId: UInt8,
        objects: [UInt8: String],
    ) {
        self.conformityLevel = conformityLevel
        self.moreFollows = moreFollows
        self.nextObjectId = nextObjectId
        self.objects = objects
    }

    // MARK: Public

    /// Device conformity level
    public let conformityLevel: UInt8

    /// True if more objects available (requires another request)
    public let moreFollows: Bool

    /// Next object ID to request if moreFollows is true
    public let nextObjectId: UInt8

    /// Device objects as [ObjectID: Value] dictionary
    public let objects: [UInt8: String]

    // MARK: - Convenience Accessors

    /// Vendor Name (Object 0x00)
    public var vendorName: String? {
        objects[DeviceObjectId.vendorName.rawValue]
    }

    /// Product Code (Object 0x01)
    public var productCode: String? {
        objects[DeviceObjectId.productCode.rawValue]
    }

    /// Major/Minor Revision (Object 0x02)
    public var revision: String? {
        objects[DeviceObjectId.majorMinorRevision.rawValue]
    }

    /// Vendor URL (Object 0x03)
    public var vendorUrl: String? {
        objects[DeviceObjectId.vendorUrl.rawValue]
    }

    /// Product Name (Object 0x04)
    public var productName: String? {
        objects[DeviceObjectId.productName.rawValue]
    }

    /// Model Name (Object 0x05)
    public var modelName: String? {
        objects[DeviceObjectId.modelName.rawValue]
    }

    /// User Application Name (Object 0x06)
    public var userApplicationName: String? {
        objects[DeviceObjectId.userApplicationName.rawValue]
    }
}

// MARK: - Device Identification Parser

/// Parses a Read Device Identification response PDU (0x2B/0x0E).
///
/// Response PDU format:
/// ```
/// [0]   Function Code (0x2B)
/// [1]   MEI Type (0x0E)
/// [2]   Read Device ID Code (echo)
/// [3]   Conformity Level
/// [4]   More Follows (0x00 or 0xFF)
/// [5]   Next Object ID
/// [6]   Number of Objects
/// [7..] Object list: [ObjectID(1), Length(1), Value(N)]...
/// ```
///
/// - Parameter pdu: PDU bytes (without MBAP header)
/// - Returns: Parsed response with device objects
/// - Throws: `PDUError` if validation fails
@inlinable
public func parseDeviceIdentificationPDU(
    _ pdu: Span<UInt8>,
) throws(PDUError) -> DeviceIdentificationResponse {
    // Defense in depth: use safe access for all header fields
    guard let functionCode = readUInt8(pdu, at: 0) else {
        throw .pduTooShort
    }

    // Check for exception response FIRST
    if (functionCode & ModbusFunctionCode.exceptionFlag) != 0 {
        guard let exceptionCode = readUInt8(pdu, at: 1) else {
            throw .pduTooShort
        }
        if let exception = ModbusException(rawValue: exceptionCode) {
            throw .exceptionResponse(exception)
        }
        throw .unknownException(exceptionCode)
    }

    // Validate function code
    guard functionCode == ModbusFunctionCode.encapsulatedInterface else {
        throw .unexpectedFunctionCode(
            expected: ModbusFunctionCode.encapsulatedInterface,
            got: functionCode,
        )
    }

    // Validate MEI type
    guard let meiType = readUInt8(pdu, at: 1) else {
        throw .pduTooShort
    }
    guard meiType == MEIType.readDeviceIdentification else {
        throw .invalidMEIType(meiType)
    }

    // Parse header fields with safe access
    // [2] = Read Device ID Code (echo, we don't validate)
    guard
        let conformityLevel = readUInt8(pdu, at: 3),
        let moreFollowsByte = readUInt8(pdu, at: 4),
        let nextObjectId = readUInt8(pdu, at: 5),
        let numberOfObjects = readUInt8(pdu, at: 6) else
    {
        throw .pduTooShort
    }
    let moreFollows = moreFollowsByte == 0xFF

    // Parse object list
    var objects: [UInt8: String] = [:]
    var offset = 7

    for _ in 0 ..< numberOfObjects {
        // Defense in depth: use safe access for object header
        guard
            let objectId = readUInt8(pdu, at: offset),
            let objectLengthByte = readUInt8(pdu, at: offset + 1) else
        {
            throw .pduTooShort
        }
        let objectLength = Int(objectLengthByte)
        offset += 2

        // Validate object data is available
        guard offset + objectLength <= pdu.count else {
            throw .pduTooShort
        }

        // Extract object value as UTF-8 string
        var valueBytes: [UInt8] = []
        valueBytes.reserveCapacity(objectLength)
        for i in 0 ..< objectLength {
            // Defense in depth: use safe access even though bounds were validated above
            guard let byte = readUInt8(pdu, at: offset + i) else {
                throw .pduTooShort
            }
            valueBytes.append(byte)
        }
        offset += objectLength

        // Convert to string (replace invalid UTF-8 with replacement char)
        let value = String(decoding: valueBytes, as: UTF8.self)
        objects[objectId] = value
    }

    return DeviceIdentificationResponse(
        conformityLevel: conformityLevel,
        moreFollows: moreFollows,
        nextObjectId: nextObjectId,
        objects: objects,
    )
}

/// Convenience overload for Array input.
@inlinable
public func parseDeviceIdentificationPDU(
    _ pdu: [UInt8],
) throws(PDUError) -> DeviceIdentificationResponse {
    try parseDeviceIdentificationPDU(pdu.span)
}
