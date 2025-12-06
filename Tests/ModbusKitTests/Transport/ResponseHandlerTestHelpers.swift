// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// Shared test helpers for ResponseHandler tests.

/// Builds a minimal MBAP response frame for testing.
///
/// Format: [Transaction ID (2)] [Protocol ID (2)] [Length (2)] [Unit ID (1)] [PDU...]
func buildMBAPResponse(transactionId: UInt16, unitId: UInt8 = 1, pdu: [UInt8]) -> [UInt8] {
    var frame: [UInt8] = []
    frame.reserveCapacity(7 + pdu.count)

    // Transaction ID (Big Endian)
    frame.append(UInt8(transactionId >> 8))
    frame.append(UInt8(transactionId & 0xFF))

    // Protocol ID (always 0x0000)
    frame.append(0x00)
    frame.append(0x00)

    // Length (Unit ID + PDU)
    let length = UInt16(1 + pdu.count)
    frame.append(UInt8(length >> 8))
    frame.append(UInt8(length & 0xFF))

    // Unit ID
    frame.append(unitId)

    // PDU
    frame.append(contentsOf: pdu)

    return frame
}
