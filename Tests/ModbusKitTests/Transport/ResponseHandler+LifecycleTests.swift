// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ResponseHandler Channel Lifecycle Tests

/// Tests for channel lifecycle handling in pipelining mode.
///
/// Validates that all pending requests are properly failed when channel
/// becomes inactive or encounters an error.
@Suite("Response Handler Lifecycle")
struct ResponseHandlerLifecycleTests {
    @Test("Pipelining handler fails all pending on channelInactive")
    func pipeliningFailsAllOnInactive() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        // Register multiple requests
        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
            try handler.registerRequest(transactionId: 0x0002, promise: promise2)
        }.get()

        // Fire channel inactive
        channel.pipeline.fireChannelInactive()
        await channel.testingEventLoop.run()

        // Both promises should fail with channelClosed
        do {
            _ = try await promise1.futureResult.get()
            Issue.record("Expected error")
        } catch let error as ModbusClientError {
            #expect(error == .channelClosed)
        }

        do {
            _ = try await promise2.futureResult.get()
            Issue.record("Expected error")
        } catch let error as ModbusClientError {
            #expect(error == .channelClosed)
        }
    }

    @Test("Pipelining handler fails all pending on error")
    func pipeliningFailsAllOnError() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
            try handler.registerRequest(transactionId: 0x0002, promise: promise2)
        }.get()

        // Fire error
        struct TestError: Error {}
        channel.pipeline.fireErrorCaught(TestError())
        await channel.testingEventLoop.run()

        // Both promises should fail
        do {
            _ = try await promise1.futureResult.get()
            Issue.record("Expected error")
        } catch {
            // Error propagated
        }

        do {
            _ = try await promise2.futureResult.get()
            Issue.record("Expected error")
        } catch {
            // Error propagated
        }
    }
}
