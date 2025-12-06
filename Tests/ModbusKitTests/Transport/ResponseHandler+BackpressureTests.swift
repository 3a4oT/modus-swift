// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ResponseHandler Backpressure Tests

/// Tests for backpressure handling in pipelining mode.
///
/// Validates that handler correctly enforces maxInFlight limit and rejects
/// duplicate Transaction IDs to prevent resource exhaustion.
@Suite("Response Handler Backpressure")
struct ResponseHandlerBackpressureTests {
    @Test("Pipelining handler rejects request when maxInFlight reached")
    func pipeliningRejectsWhenFull() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 2))
        try await channel.pipeline.addHandler(handler)

        // Fill up to maxInFlight
        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)

        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
            try handler.registerRequest(transactionId: 0x0002, promise: promise2)
        }.get()

        // Third request should fail
        let promise3 = channel.eventLoop.makePromise(of: [UInt8].self)
        do {
            try await channel.eventLoop.submit {
                try handler.registerRequest(transactionId: 0x0003, promise: promise3)
            }.get()
            Issue.record("Expected tooManyPendingRequests error")
        } catch let error as ModbusClientError {
            #expect(error == .tooManyPendingRequests)
        }

        // Complete one request to free a slot
        let response1 = buildMBAPResponse(transactionId: 0x0001, pdu: [0x03, 0x02, 0x00, 0x00])
        try await channel.writeInbound(response1)
        _ = try await promise1.futureResult.get()

        // Now third request should succeed
        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0003, promise: promise3)
        }.get()

        // Cleanup
        promise2.fail(CancellationError())
        promise3.fail(CancellationError())
        try await channel.close()
    }

    @Test("Pipelining handler rejects duplicate Transaction ID")
    func pipeliningRejectsDuplicateTransactionId() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler(mode: .pipelining(maxInFlight: 16))
        try await channel.pipeline.addHandler(handler)

        let promise1 = channel.eventLoop.makePromise(of: [UInt8].self)
        try await channel.eventLoop.submit {
            try handler.registerRequest(transactionId: 0x0001, promise: promise1)
        }.get()

        // Try to register same Transaction ID
        let promise2 = channel.eventLoop.makePromise(of: [UInt8].self)
        do {
            try await channel.eventLoop.submit {
                try handler.registerRequest(transactionId: 0x0001, promise: promise2)
            }.get()
            Issue.record("Expected transactionIdInUse error")
        } catch let error as ModbusClientError {
            #expect(error == .transactionIdInUse(0x0001))
        }

        // Cleanup: fail unused promises to prevent leak warnings
        promise1.fail(CancellationError())
        promise2.fail(CancellationError())
        try await channel.close()
    }
}
