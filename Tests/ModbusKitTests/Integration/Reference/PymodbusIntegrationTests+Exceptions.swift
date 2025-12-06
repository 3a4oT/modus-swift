// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - Exceptions Tests

/// Exception response and boundary validation tests.
///
/// Tests Modbus exception responses (Illegal Data Address - 0x02) and
/// client-side parameter validation against pymodbus server.
///
/// Reference: Modbus Application Protocol V1.1b3, Section 7
extension PymodbusIntegrationTests {
    // MARK: - Exception Response Tests (Illegal Data Address - 0x02)

    @Test("Read holding registers beyond address space returns Illegal Data Address")
    func readHoldingRegistersBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readHoldingRegisters(address: 1000, count: 1, unitId: 1)
                }
            }
        }
    }

    @Test("Read holding registers spanning beyond address space returns exception")
    func readHoldingRegistersSpanningBeyond() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readHoldingRegisters(address: 995, count: 10, unitId: 1)
                }
            }
        }
    }

    @Test("Read input registers beyond address space returns Illegal Data Address")
    func readInputRegistersBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readInputRegisters(address: 1000, count: 1, unitId: 1)
                }
            }
        }
    }

    @Test("Read coils beyond address space returns Illegal Data Address")
    func readCoilsBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readCoils(address: 1000, count: 1, unitId: 1)
                }
            }
        }
    }

    @Test("Read discrete inputs beyond address space returns Illegal Data Address")
    func readDiscreteInputsBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.readDiscreteInputs(address: 1000, count: 1, unitId: 1)
                }
            }
        }
    }

    @Test("Write single register beyond address space returns Illegal Data Address")
    func writeSingleRegisterBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.writeSingleRegister(address: 1000, value: 0x1234, unitId: 1)
                }
            }
        }
    }

    @Test("Write multiple registers beyond address space returns Illegal Data Address")
    func writeMultipleRegistersBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.writeMultipleRegisters(address: 1000, values: [0x1111], unitId: 1)
                }
            }
        }
    }

    @Test("Write single coil beyond address space returns Illegal Data Address")
    func writeSingleCoilBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.writeSingleCoil(address: 1000, value: true, unitId: 1)
                }
            }
        }
    }

    @Test("Write multiple coils beyond address space returns Illegal Data Address")
    func writeMultipleCoilsBeyondAddressSpace() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.modbusException(.illegalDataAddress)) {
                    try await client.writeMultipleCoils(address: 1000, values: [true], unitId: 1)
                }
            }
        }
    }

    // MARK: - Boundary Condition Tests (Client-Side Validation)

    @Test("Read register count zero rejected by client")
    func readRegisterCountZeroRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("count must be >= 1")) {
                    try await client.readHoldingRegisters(address: 0, count: 0, unitId: 1)
                }
            }
        }
    }

    @Test("Read register count exceeds max rejected by client")
    func readRegisterCountExceedsMaxRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("count must be <= 125")) {
                    try await client.readHoldingRegisters(address: 0, count: 126, unitId: 1)
                }
            }
        }
    }

    @Test("Write register empty values rejected by client")
    func writeRegisterEmptyValuesRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("values must not be empty")) {
                    try await client.writeMultipleRegisters(address: 0, values: [], unitId: 1)
                }
            }
        }
    }

    @Test("Write register count exceeds max rejected by client")
    func writeRegisterCountExceedsMaxRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let values = [UInt16](repeating: 0x1234, count: 124)
                await #expect(throws: ModbusClientError.invalidParameter("values count must be <= 123")) {
                    try await client.writeMultipleRegisters(address: 0, values: values, unitId: 1)
                }
            }
        }
    }

    @Test("Read coils count zero rejected by client")
    func readCoilsCountZeroRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("count must be >= 1")) {
                    try await client.readCoils(address: 0, count: 0, unitId: 1)
                }
            }
        }
    }

    @Test("Read coils count exceeds max rejected by client")
    func readCoilsCountExceedsMaxRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("count must be <= 2000")) {
                    try await client.readCoils(address: 0, count: 2001, unitId: 1)
                }
            }
        }
    }

    @Test("Write coils empty values rejected by client")
    func writeCoilsEmptyValuesRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                await #expect(throws: ModbusClientError.invalidParameter("values must not be empty")) {
                    try await client.writeMultipleCoils(address: 0, values: [], unitId: 1)
                }
            }
        }
    }

    @Test("Write coils count exceeds max rejected by client")
    func writeCoilsCountExceedsMaxRejected() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let values = [Bool](repeating: true, count: 1969)
                await #expect(throws: ModbusClientError.invalidParameter("values count must be <= 1968")) {
                    try await client.writeMultipleCoils(address: 0, values: values, unitId: 1)
                }
            }
        }
    }

    // MARK: - Maximum Valid Operations (Server-Side)

    @Test("Read maximum registers (125) at valid address")
    func readMaxRegistersAtValidAddress() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 0, count: 125, unitId: 1)
                #expect(response.count == 125)
                #expect(response.registers[0] == 1)
            }
        }
    }

    @Test("Read at last valid address")
    func readAtLastValidAddress() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let response = try await client.readHoldingRegisters(address: 997, count: 1, unitId: 1)
                #expect(response.count == 1)
                #expect(response.registers[0] == 998)
            }
        }
    }

    @Test("Write at last valid address")
    func writeAtLastValidAddress() async throws {
        try await ReferenceServerManager.withServer { host, port in
            try await withModbusTCPClient(host: host, port: port, timeout: .milliseconds(1000)) { client in
                let writeResponse = try await client.writeSingleRegister(address: 998, value: 0xBEEF, unitId: 1)
                #expect(writeResponse.address == 998)

                let readResponse = try await client.readHoldingRegisters(address: 998, count: 1, unitId: 1)
                #expect(readResponse.registers[0] == 0xBEEF)
            }
        }
    }
}
