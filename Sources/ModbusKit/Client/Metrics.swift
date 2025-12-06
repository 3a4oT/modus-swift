// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

import Metrics

// MARK: - ModbusMetrics

/// Metrics container for Modbus client observability.
///
/// Provides Prometheus-compatible metrics for monitoring Modbus TCP clients.
/// All metrics are optional — if no backend is configured, they are no-ops.
///
/// **Usage:**
/// ```swift
/// let metrics = ModbusMetrics()
/// let client = ModbusTCPClient(configuration: config, metrics: metrics)
/// ```
///
/// **Metric Names:**
/// - `modbus_requests_total` — Counter with dimensions: `function_code`, `status`
/// - `modbus_request_duration_seconds` — Timer with dimension: `function_code`
/// - `modbus_connections_active` — Gauge (no dimensions)
/// - `modbus_retries_total` — Counter with dimension: `function_code`
/// - `modbus_reconnections_total` — Counter (no dimensions)
/// - `modbus_pipelining_pending_requests` — Gauge for in-flight requests (pipelining mode)
/// - `modbus_pipelining_timeouts_total` — Counter for pipelining timeouts
/// - `modbus_pipelining_backpressure_total` — Counter for maxInFlight limit hits
///
/// Reference: [apple/swift-metrics](https://github.com/apple/swift-metrics)
public struct ModbusMetrics: Sendable {
    // MARK: Lifecycle

    /// Creates a new metrics container with default label prefix.
    ///
    /// - Parameter prefix: Label prefix for all metrics (default: "modbus")
    public init(prefix: String = "modbus") {
        self.prefix = prefix
    }

    // MARK: Public

    /// Label prefix for all metrics.
    public let prefix: String

    // MARK: - Request Metrics

    /// Records a successful request.
    ///
    /// - Parameters:
    ///   - functionCode: Modbus function code (e.g., 0x03, 0x04)
    ///   - duration: Request duration
    public func recordRequest(functionCode: UInt8, duration: Duration) {
        let fcLabel = functionCodeLabel(functionCode)

        Counter(
            label: "\(prefix)_requests_total",
            dimensions: [("function_code", fcLabel), ("status", "success")],
        ).increment()

        Timer(
            label: "\(prefix)_request_duration_seconds",
            dimensions: [("function_code", fcLabel)],
        ).recordNanoseconds(duration.nanoseconds)
    }

    /// Records a failed request.
    ///
    /// - Parameters:
    ///   - functionCode: Modbus function code
    ///   - error: Error type for dimension
    public func recordRequestError(functionCode: UInt8, error: String) {
        let fcLabel = functionCodeLabel(functionCode)

        Counter(
            label: "\(prefix)_requests_total",
            dimensions: [("function_code", fcLabel), ("status", "error"), ("error", error)],
        ).increment()
    }

    // MARK: - Connection Metrics

    /// Records a new connection.
    public func recordConnect() {
        Gauge(label: "\(prefix)_connections_active").record(1)
    }

    /// Records a disconnection.
    public func recordDisconnect() {
        Gauge(label: "\(prefix)_connections_active").record(0)
    }

    /// Records a reconnection attempt.
    public func recordReconnection() {
        Counter(label: "\(prefix)_reconnections_total").increment()
    }

    // MARK: - Retry Metrics

    /// Records a retry attempt.
    ///
    /// - Parameter functionCode: Modbus function code being retried
    public func recordRetry(functionCode: UInt8) {
        let fcLabel = functionCodeLabel(functionCode)

        Counter(
            label: "\(prefix)_retries_total",
            dimensions: [("function_code", fcLabel)],
        ).increment()
    }

    // MARK: - Pipelining Metrics

    /// Records the current number of pending pipelined requests.
    ///
    /// Call this after registering or completing a request in pipelining mode.
    ///
    /// - Parameter count: Current number of in-flight requests
    public func recordPipeliningPendingRequests(_ count: Int) {
        Gauge(label: "\(prefix)_pipelining_pending_requests").record(count)
    }

    /// Records a pipelining timeout (request didn't receive response in time).
    public func recordPipeliningTimeout() {
        Counter(label: "\(prefix)_pipelining_timeouts_total").increment()
    }

    /// Records a backpressure event (maxInFlight limit reached).
    ///
    /// This indicates the client is sending requests faster than the server
    /// can respond. Consider reducing request rate or increasing maxInFlight.
    public func recordPipeliningBackpressure() {
        Counter(label: "\(prefix)_pipelining_backpressure_total").increment()
    }

    // MARK: Private

    /// Converts function code to human-readable label.
    private func functionCodeLabel(_ fc: UInt8) -> String {
        switch fc {
        case 0x01: "read_coils"
        case 0x02: "read_discrete_inputs"
        case 0x03: "read_holding_registers"
        case 0x04: "read_input_registers"
        case 0x05: "write_single_coil"
        case 0x06: "write_single_register"
        case 0x0F: "write_multiple_coils"
        case 0x10: "write_multiple_registers"
        case 0x16: "mask_write_register"
        case 0x17: "read_write_multiple_registers"
        case 0x18: "read_fifo_queue"
        default: formatFunctionCode(fc)
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Converts Duration to nanoseconds for Timer recording.
    var nanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
