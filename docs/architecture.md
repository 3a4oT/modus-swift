# Architecture

ModbusKit follows a modular architecture with clear separation of concerns.

## Package Structure

```
Sources/
├── ModbusCore/              # Zero dependencies, Foundation-free
│   ├── PDU/                 # PDU builders/parsers for ALL function codes
│   │   ├── Registers/       # FC 0x03, 0x04, 0x06, 0x10
│   │   ├── Coils/           # FC 0x01, 0x02, 0x05, 0x0F
│   │   ├── Advanced/        # FC 0x14-0x18, 0x2B (File, FIFO, MEI)
│   │   └── Diagnostics/     # FC 0x07, 0x08, 0x0B, 0x0C, 0x11
│   ├── RTU/                 # RTU framing (Address + PDU + CRC)
│   ├── Checksum/            # CRC-16/MODBUS
│   ├── Decoding/            # Word order, multi-register values
│   ├── Binary/              # Safe byte access utilities
│   └── Utilities/           # Shared helpers
│
├── ModbusKit/               # SwiftNIO-based clients
│   ├── Client/
│   │   ├── MBAP/            # Shared MBAP transport logic
│   │   ├── TCP/             # ModbusTCPClient (port 502)
│   │   ├── TLS/             # ModbusTLSClient (port 802)
│   │   └── UDP/             # ModbusUDPClient
│   └── Transport/           # NIO frame decoder/encoder
│
└── ModbusSerial/            # Serial RTU (no SwiftNIO dependency)
    ├── Port/                # SerialPort protocol, POSIX termios
    ├── Client/              # ModbusRTUClient
    └── Transport/           # Serial transport abstraction
```

## Dependency Graph

```
ModbusCore (zero dependencies)
     │
     ├───────────────────────┐
     │                       │
ModbusKit (SwiftNIO)    ModbusSerial (POSIX termios)
```

## Module Responsibilities

### ModbusCore

- **No external dependencies** - can be used in embedded contexts
- **Foundation-free** - works on any Swift platform
- PDU (Protocol Data Unit) builders and parsers
- CRC-16/MODBUS checksum
- RTU framing primitives
- Word order conversion for multi-register values

### ModbusKit

- SwiftNIO-based network clients
- TCP, TLS, and UDP transports
- MBAP (Modbus Application Protocol) framing
- Connection management (auto-reconnect, idle timeout)
- Request serialization (prevents concurrent requests)

### ModbusSerial

- Native serial port communication
- POSIX termios for cross-platform support
- T1.5/T3.5 inter-frame timing
- **No SwiftNIO dependency** - minimal footprint

## Code Sharing

### MBAPTransport Protocol

TCP and TLS clients share ~90% of their implementation via the internal `MBAPTransport` protocol:

- MBAP framing (7-byte header)
- All function code implementations
- Retry logic and error mapping
- Connection state management

UDP uses the same MBAP framing but has a separate implementation due to its connectionless nature.

### RTU Frame Builders

ModbusCore provides RTU frame builders that ModbusSerial wraps with timing and serial port I/O:

```
ModbusCore: buildRTUReadHoldingRegistersRequest() → [UInt8]
                      ↓
ModbusSerial: readHoldingRegisters() → writes to serial, reads response
```

## Design Principles

1. **Typed Throws** - All errors are typed (`throws(ModbusClientError)`)
2. **Span-Based Parsing** - Zero-copy parsing with `Span<UInt8>`
3. **Protocol Compliance** - Validated against pymodbus reference
4. **Request Serialization** - Prevents device malfunction from concurrent requests
5. **Timeout Everything** - No unbounded waits

## References

- [Modbus Application Protocol V1.1b3](https://www.modbus.org/file/secure/modbusprotocolspecification.pdf)
- [Modbus/TCP Implementation Guide](https://www.modbus.org/file/secure/messagingimplementationguide.pdf)
- [Modbus/TCP Security Protocol](https://www.modbus.org/file/secure/modbussecurityprotocol.pdf)
