// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - DeviceIdentificationTestData

/// Expected Device Identification values from reference server.
///
/// These values match `docker/pymodbus-server/reference_server.py`:
/// - VendorName: ModbusKit
/// - ProductCode: Petro-Rovenskyi
/// - VendorUrl: https://petro.rovenskyi.com
/// - ProductName: Reference Server
/// - ModelName: PyModbus Test Server
/// - MajorMinorRevision: 1.0.0
///
/// Reference: Modbus Application Protocol V1.1b3, Section 6.21
enum DeviceIdentificationTestData {
    /// Expected VendorName (Object ID 0x00)
    static let vendorName = "ModbusKit"

    /// Expected ProductCode (Object ID 0x01)
    static let productCode = "Petro-Rovenskyi"

    /// Expected MajorMinorRevision (Object ID 0x02)
    static let revision = "1.0.0"

    /// Expected VendorUrl (Object ID 0x03)
    static let vendorUrl = "https://petro.rovenskyi.com"

    /// Expected ProductName (Object ID 0x04)
    static let productName = "Reference Server"

    /// Expected ModelName (Object ID 0x05)
    static let modelName = "PyModbus Test Server"
}
