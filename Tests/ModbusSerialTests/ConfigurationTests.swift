// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusSerial
import Testing

// MARK: - SerialErrorRecoveryTests

/// Tests for SerialErrorRecovery enum.
///
/// Reference: libmodbus MODBUS_ERROR_RECOVERY_LINK, pymodbus reconnect_delay
@Suite("SerialErrorRecovery")
struct SerialErrorRecoveryTests {
    // MARK: - Equality Tests

    @Test("Disabled equals disabled")
    func disabledEquality() {
        #expect(SerialErrorRecovery.disabled == SerialErrorRecovery.disabled)
    }

    @Test("Link with same delay equals")
    func linkEquality() {
        let a = SerialErrorRecovery.link(delay: .seconds(1))
        let b = SerialErrorRecovery.link(delay: .seconds(1))
        #expect(a == b)
    }

    @Test("Link with different delay not equal")
    func linkNotEqual() {
        let a = SerialErrorRecovery.link(delay: .seconds(1))
        let b = SerialErrorRecovery.link(delay: .seconds(2))
        #expect(a != b)
    }

    @Test("Link with nil delay equals")
    func linkNilDelayEquality() {
        let a = SerialErrorRecovery.link(delay: nil)
        let b = SerialErrorRecovery.link()
        #expect(a == b)
    }

    @Test("Exponential backoff with same params equals")
    func exponentialBackoffEquality() {
        let a = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(100),
            maxDelay: .seconds(30),
        )
        let b = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(100),
            maxDelay: .seconds(30),
        )
        #expect(a == b)
    }

    @Test("Exponential backoff with different initial delay not equal")
    func exponentialBackoffInitialDelayNotEqual() {
        let a = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(100),
            maxDelay: .seconds(30),
        )
        let b = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(200),
            maxDelay: .seconds(30),
        )
        #expect(a != b)
    }

    @Test("Exponential backoff with different max delay not equal")
    func exponentialBackoffMaxDelayNotEqual() {
        let a = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(100),
            maxDelay: .seconds(30),
        )
        let b = SerialErrorRecovery.exponentialBackoff(
            initialDelay: .milliseconds(100),
            maxDelay: .seconds(60),
        )
        #expect(a != b)
    }

    @Test("Different modes not equal")
    func differentModesNotEqual() {
        let disabled = SerialErrorRecovery.disabled
        let link = SerialErrorRecovery.link(delay: .seconds(1))
        let backoff = SerialErrorRecovery.exponentialBackoff()

        #expect(disabled != link)
        #expect(disabled != backoff)
        #expect(link != backoff)
    }

    // MARK: - Default Values Tests

    @Test("Exponential backoff default initial delay is 100ms")
    func exponentialBackoffDefaultInitialDelay() {
        let recovery = SerialErrorRecovery.exponentialBackoff()
        if case let .exponentialBackoff(initialDelay, _) = recovery {
            #expect(initialDelay == .milliseconds(100))
        } else {
            Issue.record("Expected exponentialBackoff case")
        }
    }

    @Test("Exponential backoff default max delay is 30s")
    func exponentialBackoffDefaultMaxDelay() {
        let recovery = SerialErrorRecovery.exponentialBackoff()
        if case let .exponentialBackoff(_, maxDelay) = recovery {
            #expect(maxDelay == .seconds(30))
        } else {
            Issue.record("Expected exponentialBackoff case")
        }
    }

    @Test("Link default delay is nil")
    func linkDefaultDelayIsNil() {
        let recovery = SerialErrorRecovery.link()
        if case let .link(delay) = recovery {
            #expect(delay == nil)
        } else {
            Issue.record("Expected link case")
        }
    }
}

// MARK: - RTUClientConfigurationTests

@Suite("RTUClientConfiguration")
struct RTUClientConfigurationTests {
    @Test("Default error recovery is disabled")
    func defaultErrorRecoveryIsDisabled() {
        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
        )
        #expect(config.errorRecovery == .disabled)
    }

    @Test("Custom error recovery is preserved")
    func customErrorRecoveryPreserved() {
        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
            errorRecovery: .link(delay: .seconds(2)),
        )
        #expect(config.errorRecovery == .link(delay: .seconds(2)))
    }

    @Test("Default retries is 3")
    func defaultRetriesIs3() {
        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
        )
        #expect(config.retries == 3)
    }

    @Test("Default handleLocalEcho is false")
    func defaultHandleLocalEchoIsFalse() {
        let config = RTUClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
        )
        #expect(config.handleLocalEcho == false)
    }
}

// MARK: - ASCIIClientConfigurationTests

@Suite("ASCIIClientConfiguration")
struct ASCIIClientConfigurationTests {
    @Test("Default error recovery is disabled")
    func defaultErrorRecoveryIsDisabled() {
        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
        )
        #expect(config.errorRecovery == .disabled)
    }

    @Test("Custom error recovery is preserved")
    func customErrorRecoveryPreserved() {
        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
            errorRecovery: .exponentialBackoff(
                initialDelay: .milliseconds(50),
                maxDelay: .seconds(10),
            ),
        )
        #expect(config.errorRecovery == .exponentialBackoff(
            initialDelay: .milliseconds(50),
            maxDelay: .seconds(10),
        ))
    }

    @Test("Default handleLocalEcho is false")
    func defaultHandleLocalEchoIsFalse() {
        let config = ASCIIClientConfiguration(
            serialConfiguration: SerialConfiguration(
                port: "/dev/mock",
                baudRate: .b9600,
                parity: .none,
                stopBits: .one,
                dataBits: .eight,
                timeout: .seconds(1),
            ),
        )
        #expect(config.handleLocalEcho == false)
    }
}
