// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ResponseHandler Mode Configuration Tests

/// Tests for ModbusResponseHandler mode configuration.
///
/// Validates that handler correctly initializes in serial vs pipelining mode.
@Suite("Response Handler Mode")
struct ResponseHandlerModeTests {
    @Test("Handler in serial mode has single promise state")
    func handlerSerialModeState() throws {
        let handler = ModbusResponseHandler(mode: .serial)

        #expect(handler.mode == .serial)
    }

    @Test("Handler in pipelining mode accepts maxInFlight parameter")
    func handlerPipeliningModeState() throws {
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 8))

        if case let .pipelining(maxInFlight) = handler.mode {
            #expect(maxInFlight == 8)
        } else {
            Issue.record("Expected pipelining mode")
        }
    }

    @Test("Default handler is serial mode")
    func defaultHandlerIsSerial() throws {
        let handler = ModbusResponseHandler()
        #expect(handler.mode == .serial)
    }

    @Test("Serial mode works with existing waitForResponse API")
    func serialModeCompatibility() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .serial)
        try await channel.pipeline.addHandler(handler)

        let expectedResponse: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]

        async let responseTask = handler.waitForResponse(on: channel.eventLoop)
        await channel.testingEventLoop.run()

        try await channel.writeInbound(expectedResponse)

        let response = try await responseTask
        #expect(response == expectedResponse)

        try await channel.close()
    }
}
