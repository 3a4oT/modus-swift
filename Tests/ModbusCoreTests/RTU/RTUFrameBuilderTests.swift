// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus RTU request builders.
///
/// Test vectors verified with Python CRC-16/MODBUS calculation.
@Suite("RTU Frame Builders")
struct RTUFrameBuilderTests {
    // MARK: - Read Request Builder Tests

    @Test("Build read request for 3 registers from 0x006B")
    func buildReadRequest() {
        // Verified with Python: CRC = 0x1774
        let frame = buildRTUReadRequest(
            address: 0x006B,
            count: 0x0003,
            unitId: 0x01,
        )

        let expected: [UInt8] = [
            0x01, 0x03, 0x00, 0x6B, 0x00, 0x03, 0x74, 0x17,
        ]

        #expect(frame == expected)
    }

    @Test("Build read request with default unit ID")
    func buildReadRequestDefaultUnitId() {
        let frame = buildRTUReadRequest(
            address: 0x0000,
            count: 0x000A,
        )

        // Unit ID should default to 0x01
        #expect(frame[0] == 0x01)
        #expect(frame[1] == ModbusFunctionCode.readHoldingRegisters)

        // Verify CRC is valid
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build read request for battery SOC register")
    func buildReadRequestBatterySOC() {
        // Battery SOC is at register 0x024C per data-model.md
        let frame = buildRTUReadRequest(
            address: 0x024C,
            count: 1,
        )

        #expect(frame[0] == 0x01)
        #expect(frame[1] == 0x03)
        #expect(frame[2] == 0x02) // High byte of 0x024C
        #expect(frame[3] == 0x4C) // Low byte of 0x024C
        #expect(frame[4] == 0x00) // High byte of count
        #expect(frame[5] == 0x01) // Low byte of count
        #expect(verifyModbusCRC(frame))
    }

    // MARK: - All Function Codes

    @Test("Build read coils request (FC 0x01)")
    func buildReadCoilsRequest() {
        let frame = buildRTUReadCoilsRequest(address: 0x0013, count: 0x0013, unitId: 0x01)

        #expect(frame[0] == 0x01) // Unit ID
        #expect(frame[1] == 0x01) // FC
        #expect(frame[2] == 0x00) // Address high
        #expect(frame[3] == 0x13) // Address low
        #expect(frame[4] == 0x00) // Count high
        #expect(frame[5] == 0x13) // Count low
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build read discrete inputs request (FC 0x02)")
    func buildReadDiscreteInputsRequest() {
        let frame = buildRTUReadDiscreteInputsRequest(address: 0x00C4, count: 22, unitId: 0x01)

        #expect(frame[1] == 0x02) // FC
        #expect(frame[2] == 0x00)
        #expect(frame[3] == 0xC4)
        #expect(frame[4] == 0x00)
        #expect(frame[5] == 0x16) // 22
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build read input registers request (FC 0x04)")
    func buildReadInputRegistersRequest() {
        let frame = buildRTUReadInputRegistersRequest(address: 0x0000, count: 10, unitId: 0x01)

        #expect(frame[1] == 0x04) // FC
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build write single coil request (FC 0x05)")
    func buildWriteSingleCoilRequest() {
        let frameOn = buildRTUWriteSingleCoilRequest(address: 0x00AC, value: true, unitId: 0x01)
        let frameOff = buildRTUWriteSingleCoilRequest(address: 0x00AC, value: false, unitId: 0x01)

        #expect(frameOn[1] == 0x05) // FC
        #expect(frameOn[4] == 0xFF) // ON = 0xFF00
        #expect(frameOn[5] == 0x00)
        #expect(verifyModbusCRC(frameOn))

        #expect(frameOff[4] == 0x00) // OFF = 0x0000
        #expect(frameOff[5] == 0x00)
        #expect(verifyModbusCRC(frameOff))
    }

    @Test("Build write single register request (FC 0x06)")
    func buildWriteSingleRegisterRequest() {
        let frame = buildRTUWriteSingleRegisterRequest(address: 0x0001, value: 0x0003, unitId: 0x01)

        #expect(frame[1] == 0x06) // FC
        #expect(frame[2] == 0x00)
        #expect(frame[3] == 0x01)
        #expect(frame[4] == 0x00)
        #expect(frame[5] == 0x03)
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build write multiple coils request (FC 0x0F)")
    func buildWriteMultipleCoilsRequest() {
        // 10 coils: true,false,true,true,false,false,true,true,true,false = 0xCD 0x01
        let values: [Bool] = [true, false, true, true, false, false, true, true, true, false]
        let frame = buildRTUWriteMultipleCoilsRequest(address: 0x0013, values: values, unitId: 0x01)

        #expect(frame[1] == 0x0F) // FC
        #expect(frame[4] == 0x00) // Quantity high
        #expect(frame[5] == 0x0A) // Quantity low = 10
        #expect(frame[6] == 0x02) // Byte count = 2
        #expect(frame[7] == 0xCD) // Coils 0-7: 1100 1101
        #expect(frame[8] == 0x01) // Coils 8-9: 0000 0001
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build write multiple registers request (FC 0x10)")
    func buildWriteMultipleRegistersRequest() {
        let values: [UInt16] = [0x000A, 0x0102]
        let frame = buildRTUWriteMultipleRegistersRequest(address: 0x0001, values: values, unitId: 0x01)

        #expect(frame[1] == 0x10) // FC
        #expect(frame[4] == 0x00) // Quantity high
        #expect(frame[5] == 0x02) // Quantity low = 2
        #expect(frame[6] == 0x04) // Byte count = 4
        #expect(frame[7] == 0x00) // Value 1 high
        #expect(frame[8] == 0x0A) // Value 1 low
        #expect(frame[9] == 0x01) // Value 2 high
        #expect(frame[10] == 0x02) // Value 2 low
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build mask write register request (FC 0x16)")
    func buildMaskWriteRegisterRequest() {
        let frame = buildRTUMaskWriteRegisterRequest(
            address: 0x0004,
            andMask: 0x00F2,
            orMask: 0x0025,
            unitId: 0x01,
        )

        #expect(frame[1] == 0x16) // FC
        #expect(frame[2] == 0x00) // Address high
        #expect(frame[3] == 0x04) // Address low
        #expect(frame[4] == 0x00) // AND mask high
        #expect(frame[5] == 0xF2) // AND mask low
        #expect(frame[6] == 0x00) // OR mask high
        #expect(frame[7] == 0x25) // OR mask low
        #expect(verifyModbusCRC(frame))
    }

    // MARK: - Broadcast Address Tests (Unit ID 0)

    @Test("Build request with broadcast address (unit ID 0)")
    func buildRequestBroadcast() {
        // Unit ID 0 is broadcast - all slaves should execute but not respond
        let frame = buildRTUWriteSingleRegisterRequest(
            address: 0x0000,
            value: 0x1234,
            unitId: 0x00,
        )

        #expect(frame[0] == 0x00) // Broadcast unit ID
        #expect(verifyModbusCRC(frame))
    }

    @Test("Build coils request with broadcast address")
    func buildCoilsBroadcast() {
        let frame = buildRTUWriteSingleCoilRequest(
            address: 0x0010,
            value: true,
            unitId: 0x00,
        )

        #expect(frame[0] == 0x00)
        #expect(verifyModbusCRC(frame))
    }
}
