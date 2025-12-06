// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import NIOCore
import NIOPosix
import Synchronization

// MARK: - NIOUDPTransport

/// SwiftNIO-based UDP transport implementation.
///
/// Uses DatagramBootstrap for UDP socket operations.
/// Thread-safe via Mutex synchronization.
///
/// Reference: SwiftNIO DatagramBootstrap patterns
public final class NIOUDPTransport: UDPTransport, @unchecked Sendable {
    // MARK: Lifecycle

    /// Creates NIO UDP transport.
    ///
    /// - Parameter configuration: Transport configuration
    public init(configuration: UDPTransportConfiguration) {
        self.configuration = configuration
        _channel = Mutex(nil)
        _handler = Mutex(nil)
        _remoteAddress = Mutex(nil)
        eventLoopGroup = MultiThreadedEventLoopGroup.singleton
    }

    deinit {
        _channel.withLock { ch in
            ch?.close(mode: .all, promise: nil)
        }
    }

    // MARK: Public

    /// Transport configuration.
    public let configuration: UDPTransportConfiguration

    /// Whether the transport is bound.
    public var isBound: Bool {
        _channel.withLock { $0?.isActive ?? false }
    }

    /// Binds the UDP socket.
    public func bind() async throws(UDPTransportError) {
        if _channel.withLock({ $0?.isActive ?? false }) {
            throw .alreadyBound
        }

        do {
            let remoteAddr = try SocketAddress(ipAddress: configuration.host, port: configuration.port)
            _remoteAddress.withLock { $0 = remoteAddr }

            let handler = NIOUDPResponseHandler()

            let bootstrap = DatagramBootstrap(group: eventLoopGroup)
                .channelOption(.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(handler)
                }

            // Bind to ephemeral port (0) on all interfaces
            let channel = try await bootstrap.bind(host: "0.0.0.0", port: 0).get()

            _channel.withLock { $0 = channel }
            _handler.withLock { $0 = handler }

        } catch {
            throw .bindFailed("UDP bind failed: \(error)")
        }
    }

    /// Closes the UDP socket.
    public func close() async {
        let ch = _channel.withLock { channel -> Channel? in
            let ch = channel
            channel = nil
            return ch
        }

        if let ch {
            try? await ch.close()
        }

        _handler.withLock { $0 = nil }
        _remoteAddress.withLock { $0 = nil }
    }

    /// Sends a datagram.
    public func send(_ data: [UInt8]) async throws(UDPTransportError) {
        // Auto-bind if needed
        if !_channel.withLock({ $0?.isActive ?? false }) {
            try await bind()
        }

        guard let ch = _channel.withLock({ $0 }), ch.isActive else {
            throw .notBound
        }

        guard let remoteAddr = _remoteAddress.withLock({ $0 }) else {
            throw .notBound
        }

        var buffer = ch.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let envelope = AddressedEnvelope(remoteAddress: remoteAddr, data: buffer)

        do {
            try await ch.writeAndFlush(envelope)
        } catch {
            throw .sendFailed("UDP send failed: \(error)")
        }
    }

    /// Receives a datagram with timeout.
    public func receive(timeout: Duration) async throws(UDPTransportError) -> [UInt8] {
        guard let ch = _channel.withLock({ $0 }), ch.isActive else {
            throw .notBound
        }

        guard let handler = _handler.withLock({ $0 }) else {
            throw .notBound
        }

        // Prepare handler for response
        handler.prepareForResponse(eventLoop: ch.eventLoop)

        // Wait for response with timeout
        do {
            return try await withThrowingTaskGroup(of: [UInt8].self) { group in
                group.addTask {
                    try await handler.waitForResponse()
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw UDPTransportError.timeout
                }

                guard let result = try await group.next() else {
                    throw UDPTransportError.timeout
                }
                group.cancelAll()
                return result
            }
        } catch let error as UDPTransportError {
            throw error
        } catch {
            throw .timeout
        }
    }

    // MARK: Private

    private let eventLoopGroup: EventLoopGroup
    private let _channel: Mutex<Channel?>
    private let _handler: Mutex<NIOUDPResponseHandler?>
    private let _remoteAddress: Mutex<SocketAddress?>
}
