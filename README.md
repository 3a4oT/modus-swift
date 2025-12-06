# modbus-swift

Production-ready Modbus implementation in pure Swift, built on [SwiftNIO](https://github.com/apple/swift-nio).

[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%20|%20iOS%20|%20Linux-lightgrey.svg)](https://swift.org)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Features

- **Pure Swift** — No C dependencies
- **Complete Modbus Protocol** — All 19 function codes (CANopen excluded), TCP/TLS/UDP (SwiftNIO), Serial RTU/ASCII (POSIX)
- **Swift 6.2** — Typed throws, `Span<UInt8>` parsing, `Mutex` request serialization
- **Protocol Compliant** — Validated against pymodbus reference server
- **Observability** — swift-log, swift-metrics, ServiceLifecycle integration

## Modules

| Module | Description |
|--------|-------------|
| **ModbusCore** | Zero-dependency PDU builders/parsers and CRC-16 |
| **ModbusKit** | SwiftNIO-based TCP, TLS, UDP clients |
| **ModbusSerial** | POSIX termios-based Serial RTU and ASCII clients |

## Transports

| Transport | Client | Port | Use Case |
|-----------|--------|:----:|----------|
| TCP | `ModbusTCPClient` | 502 | Standard industrial networks |
| TLS | `ModbusTLSClient` | 802 | Secure connections (TLS 1.2+) |
| UDP | `ModbusUDPClient` | 502 | Connectionless, broadcast |
| Serial RTU | `ModbusRTUClient` | — | RS-485/RS-232 binary mode |
| Serial ASCII | `ModbusASCIIClient` | — | RS-485/RS-232 ASCII mode |

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/3a4oT/modbus-swift.git", from: "1.0.0")
]
```

Then add to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "ModbusKit", package: "modbus-swift"),
        // For Serial RTU/ASCII:
        .product(name: "ModbusSerial", package: "modbus-swift"),
        // For PDU builders/parsers only (zero dependencies):
        .product(name: "ModbusCore", package: "modbus-swift"),
    ]
)
```

## Quick Start

### Scoped Client (CLI / Scripts / Tests)

Auto-closes connection when scope exits. Best for one-off operations:

```swift
import ModbusKit

// TCP
let registers = try await withModbusTCPClient(host: "192.168.1.100") { client in
    try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1).registers
}

// TLS
let registers = try await withModbusTLSClient(host: "secure.example.com") { client in
    try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1).registers
}

// UDP
let registers = try await withModbusUDPClient(host: "192.168.1.100") { client in
    try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1).registers
}
```

### Long-Lived Client (Services / Daemons)

For persistent connections with logging, metrics, and ServiceLifecycle integration:

```swift
import Logging
import Metrics
import ModbusKit
import ServiceLifecycle

let logger = Logger(label: "modbus")
let metrics = ModbusMetrics()

let config = ModbusClientConfiguration(
    host: "192.168.1.100",
    port: 502,
    timeout: .seconds(5),
    retries: 3,
    reconnectionStrategy: .exponentialBackoff(
        initialDelay: .seconds(1),
        maxDelay: .seconds(30)
    )
)

let client = ModbusTCPClient(
    configuration: config,
    logger: logger,
    metrics: metrics
)

try await client.connect()
let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
print(response.registers)

// Graceful shutdown with ServiceLifecycle
let group = ServiceGroup(
    services: [client],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)
try await group.run()
```

### Serial RTU

```swift
import ModbusSerial

let client = ModbusRTUClient(
    port: "/dev/ttyUSB0",
    baudRate: .b9600,
    parity: .none
)
try await client.connect()
let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
await client.close()
```

### Serial RTU with Error Recovery

For USB-to-serial adapters that may disconnect, enable automatic reconnection:

```swift
import ModbusSerial

let config = RTUClientConfiguration(
    serialConfiguration: SerialConfiguration(
        port: "/dev/ttyUSB0",
        baudRate: .b9600,
        parity: .none,
        stopBits: .one,
        dataBits: .eight,
        timeout: .seconds(1)
    ),
    retries: 3,
    errorRecovery: .exponentialBackoff(
        initialDelay: .milliseconds(100),
        maxDelay: .seconds(30)
    ),
    handleLocalEcho: true  // For RS-485 half-duplex adapters
)

let client = ModbusRTUClient(path: "/dev/ttyUSB0", configuration: config)
try await client.connect()
let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
await client.close()
```

**Error Recovery Modes:**

| Mode | Description |
|------|-------------|
| `.disabled` | No auto-reconnect (default) |
| `.link(delay:)` | Reconnect after fixed delay (libmodbus style) |
| `.exponentialBackoff(initialDelay:maxDelay:)` | Reconnect with increasing delays |

**`handleLocalEcho`:** Some RS-485 half-duplex adapters echo transmitted bytes back.
Enable this to strip echoed request from response. Symptoms: CRC errors with response
containing your request bytes.

### Serial ASCII

ASCII mode uses hex-encoded frames with LRC checksum. Useful for devices that require
human-readable communication or have noisy serial lines (better error detection per character).

```swift
import ModbusSerial

let client = ModbusASCIIClient(
    port: "/dev/ttyUSB0",
    baudRate: .b9600,
    parity: .even,      // ASCII default per spec
    dataBits: .seven    // ASCII default per spec
)
try await client.connect()
let response = try await client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
await client.close()
```

## Supported Function Codes

| Code | Function | TCP | TLS | UDP | RTU | ASCII |
|------|----------|:---:|:---:|:---:|:---:|:-----:|
| 0x01 | Read Coils | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x02 | Read Discrete Inputs | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x03 | Read Holding Registers | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x04 | Read Input Registers | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x05 | Write Single Coil | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x06 | Write Single Register | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x07 | Read Exception Status | — | — | — | ✓ | — |
| 0x08 | Diagnostics | — | — | — | ✓ | — |
| 0x0B | Get Comm Event Counter | — | — | — | ✓ | — |
| 0x0C | Get Comm Event Log | — | — | — | ✓ | — |
| 0x0F | Write Multiple Coils | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x10 | Write Multiple Registers | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x11 | Report Server ID | — | — | — | ✓ | — |
| 0x14 | Read File Record | ✓ | ✓ | ✓ | — | — |
| 0x15 | Write File Record | ✓ | ✓ | ✓ | — | — |
| 0x16 | Mask Write Register | ✓ | ✓ | ✓ | ✓ | ✓ |
| 0x17 | Read/Write Multiple Registers | ✓ | ✓ | ✓ | ✓ | — |
| 0x18 | Read FIFO Queue | ✓ | ✓ | ✓ | ✓ | — |
| 0x2B/0x0E | Device Identification | ✓ | ✓ | ✓ | ✓ | — |

**Notes:**
- FC 0x07, 0x08, 0x0B, 0x0C, 0x11 are Serial Line only per Modbus specification
- FC 0x2B/0x0D (CANopen General Reference) is not implemented — requires proprietary CiA 309-2 spec

## Advanced: Transaction ID Pipelining

> **For 99% of use cases, use serial mode (default).** Pipelining is an advanced
> feature for high-throughput scenarios with devices that explicitly support it.

TCP/TLS clients support Transaction ID pipelining per Modbus TCP spec Section 4.2:

```swift
import ModbusKit

let config = ModbusClientConfiguration(
    host: "192.168.1.100",
    pipelining: .enabled  // maxInFlight: 4
)
let client = ModbusTCPClient(configuration: config)
try await client.connect()

// Concurrent requests
async let r1 = client.readHoldingRegisters(address: 0, count: 10, unitId: 1)
async let r2 = client.readHoldingRegisters(address: 100, count: 10, unitId: 1)
let (result1, result2) = try await (r1, r2)

await client.close()
```

**Caution:** Many industrial devices only support 1 outstanding request per connection.
Test thoroughly with your specific hardware before enabling in production.

## Requirements

- Swift 6.2+
- macOS 26+, iOS 26+, or Linux (Ubuntu 24.04+)

## Documentation

- [Architecture](docs/architecture.md) — Module structure and design
- [Testing Guide](docs/testing.md) — Running tests with Docker

## Testing

See [Testing Guide](docs/testing.md) for detailed instructions.

## Development

### Setup

```bash
# Install SwiftFormat
brew install swiftformat

# Install pre-commit hook (runs SwiftFormat on staged files)
./Scripts/install-hooks.sh
```

### Code Style

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) with configuration in `.swiftformat`.

```bash
# Format all files
swiftformat .

# Check without modifying
swiftformat . --lint
```

## References

- [Modbus Application Protocol V1.1b3](https://www.modbus.org/file/secure/modbusprotocolspecification.pdf)
- [Modbus/TCP Implementation Guide](https://www.modbus.org/file/secure/messagingimplementationguide.pdf)
- [Modbus Serial Line Protocol V1.02](https://www.modbus.org/file/secure/modbusoverserial.pdf) — RTU/ASCII framing
- [Modbus/TCP Security Protocol](https://www.modbus.org/file/secure/modbussecurityprotocol.pdf)

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
