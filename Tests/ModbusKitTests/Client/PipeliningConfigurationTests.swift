// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

@testable import ModbusKit
import Testing

// MARK: - PipeliningConfigurationTests

/// Unit tests for PipeliningConfiguration.
///
/// These tests validate configuration defaults, clamping behavior, and edge cases.
/// No server connection required.
@Suite("Pipelining Configuration")
struct PipeliningConfigurationTests {
    @Test("PipeliningConfiguration defaults")
    func pipeliningConfigurationDefaults() {
        // Disabled (serial mode)
        let disabled = PipeliningConfiguration.disabled
        #expect(disabled.maxInFlight == 1)
        #expect(disabled.isEnabled == false)

        // Enabled (4 concurrent requests)
        let enabledConfig = PipeliningConfiguration.enabled
        #expect(enabledConfig.maxInFlight == 4)
        #expect(enabledConfig.isEnabled == true)
        #expect(enabledConfig.requestTimeout == .seconds(3))

        // Custom
        let custom = PipeliningConfiguration(maxInFlight: 32, requestTimeout: .seconds(10))
        #expect(custom.maxInFlight == 32)
        #expect(custom.requestTimeout == .seconds(10))
    }

    @Test("PipeliningConfiguration clamps invalid values")
    func pipeliningConfigurationClamping() {
        // Too low — clamps to 1
        let tooLow = PipeliningConfiguration(maxInFlight: 0)
        #expect(tooLow.maxInFlight == 1)

        // Too high — clamps to 65535
        let tooHigh = PipeliningConfiguration(maxInFlight: 100_000)
        #expect(tooHigh.maxInFlight == 65535)

        // Valid range preserved
        let valid = PipeliningConfiguration(maxInFlight: 100)
        #expect(valid.maxInFlight == 100)
    }

    @Test("Client configuration includes pipelining")
    func clientConfigurationIncludesPipelining() {
        // Default config has pipelining disabled
        let defaultConfig = ModbusClientConfiguration(host: "localhost")
        #expect(defaultConfig.pipelining.isEnabled == false)
        #expect(defaultConfig.pipelining.maxInFlight == 1)

        // Custom config with pipelining enabled
        let pipeliningConfig = ModbusClientConfiguration(
            host: "localhost",
            pipelining: .enabled,
        )
        #expect(pipeliningConfig.pipelining.isEnabled == true)
        #expect(pipeliningConfig.pipelining.maxInFlight == 4)
    }
}
