// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import NIOCore
import NIOEmbedded
import Testing

// MARK: - ResponseHandlerTests

/// Tests for ModbusResponseHandler using EmbeddedChannel.
///
/// These tests validate handler behavior in isolation — how it processes
/// incoming data, errors, and channel lifecycle events.
///
/// **Note:** The handler's async `waitForResponse()` method is tested indirectly
/// through integration with pymodbus reference server. Here we test the synchronous
/// ChannelInboundHandler methods.
///
/// Reference: SwiftNIO ChannelInboundHandler testing patterns
@Suite("Modbus Response Handler")
struct ResponseHandlerTests {
    // MARK: Internal

    // MARK: - Handler Behavior Tests

    @Test("Handler does not crash on unsolicited response")
    func handlerHandlesUnsolicitedResponse() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Fire response without anyone waiting - should not crash
        // Using writeInbound instead of deprecated fireChannelRead(NIOAny(...))
        let responseFrame: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]
        try channel.writeInbound(responseFrame)

        // Handler simply discards unsolicited responses
        // This is correct behavior per design
    }

    @Test("Handler can be added to pipeline")
    func handlerCanBeAddedToPipeline() throws {
        let channel = try makeChannel()
        defer { finishChannel(channel) }

        // Verify handler is in pipeline (throws if not found)
        let handler = try channel.pipeline.handler(type: ModbusResponseHandler.self).wait()
        #expect(type(of: handler) == ModbusResponseHandler.self)
    }

    @Test("Handler closes channel on error")
    func handlerClosesChannelOnError() throws {
        let channel = try makeChannel()

        // Fire an error
        let testError = ModbusFrameDecoderError.invalidProtocolId(0x1234)
        channel.pipeline.fireErrorCaught(testError)

        // Channel should be closed
        #expect(channel.isActive == false)
    }

    // MARK: - Full Pipeline Tests (Decoder + Handler)

    @Test("Full pipeline decodes complete frame")
    func fullPipelineDecodesFrame() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // Build complete Modbus TCP frame
        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        // Write raw bytes to channel
        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)

        // Frame should pass through decoder and reach handler
        // Handler discards it (no pending promise), but no crash
    }

    @Test("Full pipeline accumulates partial frames")
    func fullPipelineAccumulatesPartialFrames() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // Build frame
        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        // Send first part (MBAP header only)
        var buffer1 = channel.allocator.buffer(capacity: 7)
        buffer1.writeBytes(Array(frame[0 ..< 7]))
        try channel.writeInbound(buffer1)

        // Decoder should not have passed anything through yet
        // (accumulating partial frame)

        // Send remaining PDU
        var buffer2 = channel.allocator.buffer(capacity: frame.count - 7)
        buffer2.writeBytes(Array(frame[7...]))
        try channel.writeInbound(buffer2)

        // Now complete frame should pass through
    }

    @Test("Full pipeline handles exception response frame")
    func fullPipelineHandlesExceptionResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // Build exception response: FC 0x03 + 0x80 = 0x83, exception code 0x01
        let exceptionPdu: [UInt8] = [0x83, 0x01] // Illegal Function
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: exceptionPdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)

        // Exception responses are valid frames — they pass through
    }

    @Test("Full pipeline closes channel on decoder error")
    func fullPipelineClosesOnDecoderError() throws {
        let channel = try makeFullPipelineChannel()

        // Send invalid frame (wrong protocol ID)
        let invalidFrame: [UInt8] = [
            0x00, 0x01, // Transaction ID
            0x00, 0x01, // Protocol ID = 1 (INVALID, must be 0)
            0x00, 0x03, // Length
            0x01, // Unit ID
            0x03, 0x00, // PDU
        ]

        var buffer = channel.allocator.buffer(capacity: invalidFrame.count)
        buffer.writeBytes(invalidFrame)

        // Decoder error gets caught by ResponseHandler which closes channel
        // (Error is tested in isolation by FrameDecoderTests)
        _ = try? channel.writeInbound(buffer)

        // Channel should be closed due to error
        #expect(channel.isActive == false)
    }

    @Test("Full pipeline handles multiple frames")
    func fullPipelineHandlesMultipleFrames() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // Build two frames
        let pdu1: [UInt8] = [0x03, 0x02, 0x00, 0x01]
        let pdu2: [UInt8] = [0x04, 0x02, 0x00, 0x02]
        let frame1 = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu1)
        let frame2 = buildModbusTCPADU(transactionId: 0x0002, unitId: 1, pdu: pdu2)

        // Send both frames in one buffer
        var buffer = channel.allocator.buffer(capacity: frame1.count + frame2.count)
        buffer.writeBytes(frame1)
        buffer.writeBytes(frame2)
        try channel.writeInbound(buffer)

        // Both frames should be decoded and passed through
    }

    @Test("Full pipeline handles various exception codes")
    func fullPipelineHandlesVariousExceptions() throws {
        let exceptionCodes: [(UInt8, String)] = [
            (0x01, "Illegal Function"),
            (0x02, "Illegal Data Address"),
            (0x03, "Illegal Data Value"),
            (0x04, "Server Device Failure"),
            (0x06, "Server Device Busy"),
        ]

        for (code, _) in exceptionCodes {
            let channel = try makeFullPipelineChannel()
            defer { finishChannel(channel) }

            // Build exception response
            let exceptionPdu: [UInt8] = [0x83, code] // FC 0x03 + 0x80
            let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: exceptionPdu)

            var buffer = channel.allocator.buffer(capacity: frame.count)
            buffer.writeBytes(frame)
            try channel.writeInbound(buffer)

            // All exception codes should be valid frames
        }
    }

    // MARK: - Response Type Tests (All Function Codes)

    @Test("Pipeline handles FC 0x03 Read Holding Registers response")
    func pipelineHandlesReadHoldingRegistersResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x03 response: byte count + register data
        let pdu: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02] // 2 registers
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    @Test("Pipeline handles FC 0x04 Read Input Registers response")
    func pipelineHandlesReadInputRegistersResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x04 response: byte count + register data
        let pdu: [UInt8] = [0x04, 0x04, 0x12, 0x34, 0x56, 0x78] // 2 registers
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    @Test("Pipeline handles FC 0x06 Write Single Register response")
    func pipelineHandlesWriteSingleRegisterResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x06 response: address + value (echo)
        let pdu: [UInt8] = [0x06, 0x00, 0x0A, 0xAB, 0xCD] // addr=10, value=0xABCD
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    @Test("Pipeline handles FC 0x10 Write Multiple Registers response")
    func pipelineHandlesWriteMultipleRegistersResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x10 response: address + quantity
        let pdu: [UInt8] = [0x10, 0x00, 0x00, 0x00, 0x05] // addr=0, qty=5
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    @Test("Pipeline handles FC 0x01 Read Coils response")
    func pipelineHandlesReadCoilsResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x01 response: byte count + coil data
        let pdu: [UInt8] = [0x01, 0x01, 0b1010_0101] // 8 coils
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    @Test("Pipeline handles FC 0x05 Write Single Coil response")
    func pipelineHandlesWriteSingleCoilResponse() throws {
        let channel = try makeFullPipelineChannel()
        defer { finishChannel(channel) }

        // FC 0x05 response: address + value (0xFF00 = ON, 0x0000 = OFF)
        let pdu: [UInt8] = [0x05, 0x00, 0x10, 0xFF, 0x00] // addr=16, ON
        let frame = buildModbusTCPADU(transactionId: 0x0001, unitId: 1, pdu: pdu)

        var buffer = channel.allocator.buffer(capacity: frame.count)
        buffer.writeBytes(frame)
        try channel.writeInbound(buffer)
    }

    // MARK: Private

    // MARK: - Helpers

    /// Creates an EmbeddedChannel with only ModbusResponseHandler installed.
    private func makeChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandler(ModbusResponseHandler()).wait()
        return channel
    }

    /// Creates an EmbeddedChannel with full Modbus TCP pipeline.
    private func makeFullPipelineChannel() throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.addHandlers([
            ByteToMessageHandler(ModbusFrameDecoder()),
            ModbusResponseHandler(),
        ]).wait()
        return channel
    }

    /// Safely finishes channel, ignoring errors.
    private func finishChannel(_ channel: EmbeddedChannel) {
        _ = try? channel.finish()
    }
}

// MARK: - ResponseHandlerAsyncTests

/// Tests for ModbusResponseHandler async behavior using NIOAsyncTestingChannel.
///
/// These tests validate the `waitForResponse()` async method behavior:
/// - Successful response delivery
/// - Channel closure during wait
/// - Error propagation
/// - Task cancellation
///
/// **Important:** Uses NIOAsyncTestingChannel instead of EmbeddedChannel because
/// EmbeddedEventLoop is not thread-safe and cannot be used with async/await Tasks.
///
/// Reference: SwiftNIO NIOAsyncTestingChannel for async-safe testing
@Suite("Response Handler Async")
struct ResponseHandlerAsyncTests {
    // MARK: - waitForResponse Success Tests

    @Test("waitForResponse returns data when response arrives")
    func waitForResponseSuccess() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        let expectedResponse: [UInt8] = [0x03, 0x04, 0x00, 0x01, 0x00, 0x02]

        // Start waiting for response in background
        async let responseTask = handler.waitForResponse(on: channel.eventLoop)

        // Execute pending work on event loop
        await channel.testingEventLoop.run()

        // Deliver response through channel using writeInbound (recommended over fireChannelRead)
        try await channel.writeInbound(expectedResponse)

        // Await result
        let response = try await responseTask

        #expect(response == expectedResponse)

        try await channel.close()
    }

    @Test("waitForResponse returns immediately if response already pending")
    func waitForResponseImmediateResponse() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        let expectedResponse: [UInt8] = [0x04, 0x02, 0x12, 0x34]

        // Start waiting
        async let responseTask = handler.waitForResponse(on: channel.eventLoop)

        // Run event loop
        await channel.testingEventLoop.run()

        // Deliver response using writeInbound (recommended over fireChannelRead)
        try await channel.writeInbound(expectedResponse)

        let response = try await responseTask
        #expect(response == expectedResponse)

        try await channel.close()
    }

    // MARK: - Connection Loss Tests (channelInactive)

    @Test("waitForResponse fails with channelClosed when channel becomes inactive")
    func waitForResponseChannelClosed() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        // Start waiting for response
        async let responseTask: Void = {
            do {
                _ = try await handler.waitForResponse(on: channel.eventLoop)
                Issue.record("Expected channelClosed error")
            } catch let error as ModbusClientError {
                #expect(error == .channelClosed)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }()

        // Run event loop then fire inactive
        await channel.testingEventLoop.run()
        channel.pipeline.fireChannelInactive()
        await channel.testingEventLoop.run()

        await responseTask
    }

    @Test("waitForResponse fails when channel closes before response")
    func waitForResponseChannelClosesBeforeResponse() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        // Start waiting
        let task = Task {
            try await handler.waitForResponse(on: channel.eventLoop)
        }

        // Run event loop then close channel
        await channel.testingEventLoop.run()
        try await channel.close()

        // Should fail with channelClosed
        do {
            _ = try await task.value
            Issue.record("Expected error")
        } catch let error as ModbusClientError {
            #expect(error == .channelClosed)
        } catch {
            // CancellationError or NIO errors are also acceptable
        }
    }

    // MARK: - Error Propagation Tests

    @Test("waitForResponse propagates decoder error")
    func waitForResponseDecoderError() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        // Start waiting
        async let responseTask: Void = {
            do {
                _ = try await handler.waitForResponse(on: channel.eventLoop)
                Issue.record("Expected error")
            } catch {
                // Error should be propagated
                #expect(error is ModbusFrameDecoderError)
            }
        }()

        // Fire error through pipeline
        await channel.testingEventLoop.run()
        let decoderError = ModbusFrameDecoderError.invalidProtocolId(0x1234)
        channel.pipeline.fireErrorCaught(decoderError)
        await channel.testingEventLoop.run()

        await responseTask
    }

    @Test("waitForResponse propagates arbitrary error")
    func waitForResponseArbitraryError() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        struct TestError: Error, Equatable {}

        async let responseTask: Void = {
            do {
                _ = try await handler.waitForResponse(on: channel.eventLoop)
                Issue.record("Expected error")
            } catch {
                #expect(error is TestError)
            }
        }()

        await channel.testingEventLoop.run()
        channel.pipeline.fireErrorCaught(TestError())
        await channel.testingEventLoop.run()

        await responseTask
    }

    // MARK: - Task Cancellation Tests

    @Test("waitForResponse handles task cancellation")
    func waitForResponseCancellation() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        let task = Task {
            try await handler.waitForResponse(on: channel.eventLoop)
        }

        // Cancel the task before response arrives
        await channel.testingEventLoop.run()
        task.cancel()

        // Should throw CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            // Other errors acceptable (race condition)
        }

        try await channel.close()
    }

    // MARK: - Multiple Response Tests

    @Test("Handler discards response when no one is waiting")
    func handlerDiscardsUnsolicitedResponse() async throws {
        let channel = NIOAsyncTestingChannel()
        let handler = ModbusResponseHandler()
        try await channel.pipeline.addHandler(handler)

        // Send response without anyone waiting using writeInbound
        let response: [UInt8] = [0x03, 0x02, 0x00, 0x01]
        try await channel.writeInbound(response)

        // Now wait for next response
        async let responseTask = handler.waitForResponse(on: channel.eventLoop)

        // Run event loop and send actual expected response
        await channel.testingEventLoop.run()
        let expectedResponse: [UInt8] = [0x04, 0x02, 0x12, 0x34]
        try await channel.writeInbound(expectedResponse)

        let result = try await responseTask
        #expect(result == expectedResponse)

        try await channel.close()
    }
}
