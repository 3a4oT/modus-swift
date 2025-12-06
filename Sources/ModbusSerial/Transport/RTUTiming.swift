// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 Petro Rovenskyi

// MARK: - RTUTiming

/// Modbus RTU timing parameters per specification.
///
/// Modbus RTU uses character-based timing for frame detection:
/// - **T1.5**: Maximum time between characters within a frame (1.5 character times)
/// - **T3.5**: Minimum silence between frames (3.5 character times)
///
/// ## Timing Calculation
///
/// For baud rates ≤ 19200:
/// ```
/// Character time = 11 bits / baud_rate
/// T1.5 = 1.5 × character_time
/// T3.5 = 3.5 × character_time
/// ```
///
/// For baud rates > 19200 (fixed values per spec):
/// ```
/// T1.5 = 750 µs
/// T3.5 = 1.75 ms
/// ```
///
/// ## Reference
///
/// - Modbus Serial Line Protocol and Implementation Guide V1.02
/// - Section 2.5.1.1: Modbus RTU Transmission Mode
public struct RTUTiming: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates timing parameters for a given baud rate.
    ///
    /// - Parameter baudRate: Baud rate to calculate timing for
    public init(baudRate: BaudRate) {
        if baudRate.usesFixedTiming {
            // Fixed values for baud > 19200 (per Modbus spec)
            interCharacter = .microseconds(750)
            interFrame = .microseconds(1750)
        } else {
            // Calculate based on character time (11 bits per character)
            // 11 bits = 1 start + 8 data + 1 parity + 1 stop (worst case)
            let baud = Double(baudRate.rawValue)
            let characterTimeMicros = (11.0 / baud) * 1_000_000

            interCharacter = .microseconds(Int(characterTimeMicros * 1.5))
            interFrame = .microseconds(Int(characterTimeMicros * 3.5))
        }
        self.baudRate = baudRate
    }

    // MARK: Public

    /// Baud rate this timing was calculated for.
    public let baudRate: BaudRate

    /// T1.5: Maximum inter-character time within a frame.
    ///
    /// If silence exceeds this during frame reception, the frame is incomplete.
    public let interCharacter: Duration

    /// T3.5: Minimum inter-frame silence.
    ///
    /// A new frame can only begin after this silence period.
    /// Used to detect frame boundaries.
    public let interFrame: Duration
}

// MARK: - RTUTiming Constants

extension RTUTiming {
    // Common timing presets.

    /// 9600 baud timing (most common for Modbus RTU).
    ///
    /// T1.5 ≈ 1.72 ms, T3.5 ≈ 4.01 ms
    public static let baud9600 = RTUTiming(baudRate: .b9600)

    /// 19200 baud timing.
    ///
    /// T1.5 ≈ 0.86 ms, T3.5 ≈ 2.00 ms
    public static let baud19200 = RTUTiming(baudRate: .b19200)

    /// 115200 baud timing (uses fixed values).
    ///
    /// T1.5 = 750 µs, T3.5 = 1.75 ms
    public static let baud115200 = RTUTiming(baudRate: .b115200)
}

// MARK: - RTUFrameLimits

/// Modbus RTU frame size limits per specification.
public enum RTUFrameLimits {
    /// Maximum RTU ADU size (256 bytes).
    ///
    /// = 1 (address) + 253 (PDU max) + 2 (CRC)
    public static let maxFrameSize = 256

    /// Minimum valid RTU response size (5 bytes).
    ///
    /// = 1 (address) + 1 (function) + 1 (byte count) + 2 (CRC)
    public static let minResponseSize = 5

    /// Minimum valid RTU request size (8 bytes for read requests).
    ///
    /// = 1 (address) + 1 (function) + 2 (start) + 2 (quantity) + 2 (CRC)
    public static let minRequestSize = 8
}

// MARK: - ASCIIFrameLimits

/// Modbus ASCII frame size limits per specification.
public enum ASCIIFrameLimits: Sendable {
    /// Maximum ASCII frame size (513 characters per spec).
    ///
    /// = 1 (':') + 2*(1 + 253 + 1) (hex-encoded address + PDU + LRC) + 2 (CR LF)
    public static let maxFrameSize = 513

    /// Minimum valid ASCII frame size (9 characters).
    ///
    /// = 1 (':') + 2 (address) + 2 (function) + 2 (LRC) + 2 (CR LF)
    public static let minFrameSize = 9
}
