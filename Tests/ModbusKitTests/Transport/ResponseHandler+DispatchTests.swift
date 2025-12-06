// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ResponseHandler Transaction ID Dispatch Tests

/// Tests for Transaction ID-based response dispatch in pipelining mode.
///
/// Validates that responses are correctly matched to pending requests by Transaction ID,
/// including out-of-order delivery per Modbus TCP specification Section 4.2.
@Suite("Response Handler Dispatch")
struct ResponseHandlerDispatchTests {
    @Test("Pipelining handler dispatches response to correct Transaction ID")
    func pipeliningDispatchByTransactionId() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        // Register two requests with different Transaction IDs
        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
            try handler.registerRequest(transactionId: 0x0002, promise: promise2)
        }.get()

        // Build responses with Transaction IDs in MBAP header
        let response1 = buildMBAPResponse(transactionId: 0x0001, pdu: [0x03, 0x02, 0xAA, 0xBB])
        let response2 = buildMBAPResponse(transactionId: 0x0002, pdu: [0x03, 0x02, 0xCC, 0xDD])

        // Send response for Transaction ID 2 first (out of order)
        try await channel.writeInbound(response2)
        try await channel.writeInbound(response1)

        // Each promise should receive correct response
        let result1 = try await promise1.futureResult.get()
        let result2 = try await promise2.futureResult.get()

        #expect(result1 == response1)
        #expect(result2 == response2)

        try await channel.close()
    }

    @Test("Pipelining handler discards response with unknown Transaction ID")
    func pipeliningDiscardsUnknownTransactionId() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        // Register one request
        let promise = channel.eventLoop.makePromise(of: [UInt8].self)
        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise)
        }.get()

        // Send response with wrong Transaction ID (unsolicited)
        let unknownResponse = buildMBAPResponse(transactionId: 0x9999, pdu: [0x03, 0x02, 0x00, 0x00])
        try await channel.writeInbound(unknownResponse)

        // Original promise should still be pending
        // Send correct response
        let correctResponse = buildMBAPResponse(transactionId: 0x0001, pdu: [0x03, 0x02, 0x12, 0x34])
        try await channel.writeInbound(correctResponse)

        let result = try await promise.futureResult.get()
        #expect(result == correctResponse)

        try await channel.close()
    }

    @Test("Handler reports correct pending count")
    func handlerPendingCount() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        // Initially zero
        let count0 = try await channel.eventLoop.submit { handler.pendingCount }.get()
        #expect(count0 == 0)

        // Add requests
        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
        }.get()

        let count1 = try await channel.eventLoop.submit { handler.pendingCount }.get()
        #expect(count1 == 1)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0002, promise: promise2)
        }.get()

        let count2 = try await channel.eventLoop.submit { handler.pendingCount }.get()
        #expect(count2 == 2)

        // Complete one
        let response = buildMBAPResponse(transactionId: 0x0001, pdu: [0x03, 0x02, 0x00, 0x00])
        try await channel.writeInbound(response)
        _ = try await promise1.futureResult.get()

        let count3 = try await channel.eventLoop.submit { handler.pendingCount }.get()
        #expect(count3 == 1)

        promise2.fail(CancellationError())
        try await channel.close()
    }
}
