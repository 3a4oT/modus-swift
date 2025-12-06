// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOConcurrencyHelpers
import NIOCore

// MARK: - NIOUDPResponseHandler

/// Channel handler for UDP response handling.
///
/// Receives AddressedEnvelope<ByteBuffer> from UDP socket
/// and provides response to waiting caller via EventLoopPromise.
final class NIOUDPResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    // MARK: Internal

    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    /// Prepares handler for expected response.
    func prepareForResponse(eventLoop: EventLoop) {
        lock.withLock {
            pendingPromise = eventLoop.makePromise(of: [UInt8].self)
        }
    }

    /// Waits for response.
    func waitForResponse() async throws -> [UInt8] {
        guard let promise = lock.withLock({ pendingPromise }) else {
            throw UDPTransportError.notBound
        }
        return try await promise.futureResult.get()
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        var buffer = envelope.data

        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            return
        }

        lock.withLock {
            pendingPromise?.succeed(bytes)
            pendingPromise = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        lock.withLock {
            pendingPromise?.fail(error)
            pendingPromise = nil
        }
        context.close(promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        lock.withLock {
            pendingPromise?.fail(UDPTransportError.notBound)
            pendingPromise = nil
        }
    }

    // MARK: Private

    private var pendingPromise: EventLoopPromise<[UInt8]>?
    private let lock = NIOLock()
}
