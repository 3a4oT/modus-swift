// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusCore
import Testing

/// Tests for Modbus RTU protocol constants.
///
/// Verifies function codes, frame sizes, and exception codes per Modbus spec.
@Suite("RTU Constants")
struct RTUConstantsTests {
    @Test("Function codes have correct values")
    func functionCodesCorrect() {
        #expect(ModbusFunctionCode.readHoldingRegisters == 0x03)
        #expect(ModbusFunctionCode.readInputRegisters == 0x04)
        #expect(ModbusFunctionCode.writeSingleRegister == 0x06)
        #expect(ModbusFunctionCode.writeMultipleRegisters == 0x10)
        #expect(ModbusFunctionCode.exceptionFlag == 0x80)
    }

    @Test("Frame sizes are correct")
    func frameSizesCorrect() {
        #expect(RTUFrameSize.minimumRequest == 6)
        #expect(RTUFrameSize.minimumResponse == 5)
        #expect(RTUFrameSize.exceptionResponse == 5)
        #expect(RTUFrameSize.crc == 2)
    }

    @Test("Exception codes have correct values")
    func exceptionCodesCorrect() {
        #expect(ModbusException.illegalFunction.rawValue == 0x01)
        #expect(ModbusException.illegalDataAddress.rawValue == 0x02)
        #expect(ModbusException.illegalDataValue.rawValue == 0x03)
        #expect(ModbusException.slaveDeviceFailure.rawValue == 0x04)
        #expect(ModbusException.slaveDeviceBusy.rawValue == 0x06)
    }
}
