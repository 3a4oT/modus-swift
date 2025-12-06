// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOConcurrencyHelpers
import NIOCore

// MARK: - ModbusResponseHandler

/// Handler that accumulates Modbus responses for async retrieval.
///
/// Supports two modes:
/// - **Serial mode** (default): One request at a time, compatible with all devices
/// - **Pipelining mode**: Multiple concurrent requests matched by Transaction ID
///
/// ## Thread Safety
///
/// Uses `EventLoopPromise` instead of raw `CheckedContinuation` to prevent race conditions.
/// This pattern is recommended by SwiftNIO developers for bridging channel handlers to async/await.
///
/// ## Security Considerations
///
/// - Promise can only be completed once (prevents double-resume crashes)
/// - No buffering of unsolicited responses (prevents memory exhaustion)
/// - `maxInFlight` limit prevents resource exhaustion in pipelining mode
/// - All state access protected by NIOLock
///
/// ## Reference
///
/// - SwiftNIO: https://forums.swift.org/t/writing-a-checkedcontinuation-to-a-channel-without-leaking/68745
/// - RediStack: CircularBuffer pattern for Redis pipelining
/// - Modbus TCP: Section 4.2 for Transaction ID matching
final class ModbusResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates a response handler.
    ///
    /// - Parameter mode: Operating mode (default: `.serial`)
    init(mode: Mode = .serial) {
        self.mode = mode

        switch mode {
        case .serial:
            pendingRequests = nil
        case .pipelining:
            pendingRequests = [:]
        }
    }

    // MARK: Internal

    /// Operating mode for the handler.
    enum Mode: Equatable, Sendable {
        /// Serial mode: one request at a time.
        ///
        /// Uses a single promise for the next response. This is the default
        /// and most compatible mode for industrial Modbus devices.
        case serial

        /// Pipelining mode: multiple concurrent requests.
        ///
        /// Requests are matched by Transaction ID from MBAP header.
        /// Responses may arrive out of order.
        ///
        /// - Parameter maxInFlight: Maximum concurrent pending requests
        case pipelining(maxInFlight: Int)
    }

    typealias InboundIn = [UInt8]
    typealias InboundOut = Never

    /// Handler operating mode.
    let mode: Mode

    /// Number of pending requests (pipelining mode only).
    ///
    /// Returns 0 in serial mode, or current pending count in pipelining mode.
    /// Call from EventLoop only.
    var pendingCount: Int {
        lock.withLock {
            pendingRequests?.count ?? (serialPromise != nil ? 1 : 0)
        }
    }

    // MARK: - ChannelInboundHandler

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch mode {
        case .serial:
            handleSerialResponse(frame)
        case .pipelining:
            handlePipeliningResponse(frame)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        failAll(error: error)
        context.close(promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        failAll(error: ModbusClientError.channelClosed)
    }

    // MARK: - Serial Mode API

    /// Waits for the next response using EventLoopPromise (serial mode).
    ///
    /// Safe against race conditions because EventLoopPromise:
    /// - Is created synchronously before any async suspension
    /// - Can only be completed once (NIO enforces this)
    /// - Handles the case where response arrives before await
    ///
    /// **Cancellation Support:**
    /// Uses `withTaskCancellationHandler` to fail the promise when the Task is cancelled.
    /// This prevents promise leaks when timeout occurs in the calling code.
    ///
    /// - Parameter eventLoop: The channel's event loop
    /// - Returns: Raw response bytes
    /// - Throws: Error if response fails, channel closes, or task is cancelled
    func waitForResponse(on eventLoop: EventLoop) async throws -> [UInt8] {
        let promise = eventLoop.makePromise(of: [UInt8].self)

        lock.lock()
        serialPromise = promise
        lock.unlock()

        return try await withTaskCancellationHandler {
            try await promise.futureResult.get()
        } onCancel: {
            // Fail promise on cancellation to prevent leaks
            // This runs synchronously on cancellation, safe because promise.fail is thread-safe
            lock.lock()
            serialPromise = nil
            lock.unlock()
            // Always fail the promise we created - it's safe to call fail multiple times
            // (NIO will ignore subsequent calls)
            promise.fail(CancellationError())
        }
    }

    // MARK: - Pipelining Mode API

    /// Registers a pending request for a specific Transaction ID (pipelining mode).
    ///
    /// Must be called on the EventLoop.
    ///
    /// - Parameters:
    ///   - transactionId: Transaction ID from MBAP header
    ///   - promise: Promise to complete when response arrives
    /// - Throws: `ModbusClientError.tooManyPendingRequests` if maxInFlight reached
    /// - Throws: `ModbusClientError.transactionIdInUse` if ID already registered
    func registerRequest(
        transactionId: UInt16,
        promise: EventLoopPromise<[UInt8]>,
    ) throws(ModbusClientError) {
        guard case let .pipelining(maxInFlight) = mode else {
            preconditionFailure("registerRequest called in serial mode")
        }

        lock.lock()
        defer { lock.unlock() }

        guard var pending = pendingRequests else {
            preconditionFailure("pendingRequests is nil in pipelining mode")
        }

        // Check maxInFlight limit
        guard pending.count < maxInFlight else {
            throw .tooManyPendingRequests
        }

        // Check for duplicate Transaction ID
        guard pending[transactionId] == nil else {
            throw .transactionIdInUse(transactionId)
        }

        pending[transactionId] = promise
        pendingRequests = pending
    }

    /// Cancels a pending request by Transaction ID.
    ///
    /// Used when write fails after registration.
    func cancelRequest(transactionId: UInt16) {
        lock.lock()
        let removed = pendingRequests?.removeValue(forKey: transactionId)
        lock.unlock()

        removed?.fail(CancellationError())
    }

    // MARK: Private

    // MARK: - State

    /// Serial mode: single pending promise
    private var serialPromise: EventLoopPromise<[UInt8]>?

    /// Pipelining mode: Transaction ID → Promise mapping
    private var pendingRequests: [UInt16: EventLoopPromise<[UInt8]>]?

    /// Lock protecting state access
    private let lock = NIOLock()

    // MARK: - Serial Mode Implementation

    private func handleSerialResponse(_ frame: [UInt8]) {
        lock.lock()
        if let promise = serialPromise {
            serialPromise = nil
            lock.unlock()
            promise.succeed(frame)
        } else {
            lock.unlock()
            // No pending request — discard unsolicited response
        }
    }

    // MARK: - Pipelining Mode Implementation

    private func handlePipeliningResponse(_ frame: [UInt8]) {
        // Parse Transaction ID from MBAP header (bytes 0-1, Big Endian)
        guard frame.count >= MBAPConstants.headerSize else {
            // Frame too short to contain Transaction ID — discard
            return
        }

        let transactionId = (UInt16(frame[0]) << 8) | UInt16(frame[1])

        lock.lock()
        let promise = pendingRequests?.removeValue(forKey: transactionId)
        lock.unlock()

        if let promise {
            promise.succeed(frame)
        }
        // Unknown Transaction ID — discard (security: don't buffer unsolicited data)
    }

    // MARK: - Cleanup

    private func failAll(error: Error) {
        lock.lock()

        // Serial mode
        if let promise = serialPromise {
            serialPromise = nil
            lock.unlock()
            promise.fail(error)
            return
        }

        // Pipelining mode
        if let pending = pendingRequests {
            pendingRequests = [:]
            lock.unlock()
            for (_, promise) in pending {
                promise.fail(error)
            }
            return
        }

        lock.unlock()
    }
}
