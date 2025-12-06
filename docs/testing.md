# Testing Guide

ModbusKit uses a multi-layered testing approach to ensure protocol compliance and reliability.

## Test Categories

| Category | Docker | Description |
|----------|--------|-------------|
| Unit Tests | No | PDU parsing, CRC, client state |
| Mock Server | No | In-process NIO server tests |
| Integration | Yes | pymodbus reference server (TCP + TLS) |

## Quick Start

```bash
# Unit tests only (fastest)
swift test --skip PymodbusIntegrationTests

# All tests with Docker
docker compose up -d && swift test && docker compose down
```

## Unit Tests

Test PDU builders/parsers, CRC calculations, and client configuration without any network dependencies.

```bash
swift test --filter ModbusCoreTests
swift test --filter ModbusKitTests --skip Integration
```

## Integration Tests (pymodbus)

Validates ModbusTCPClient and ModbusTLSClient against pymodbus reference servers.

```bash
# Start all reference servers
docker compose up -d

# Run integration tests
swift test --filter PymodbusIntegrationTests

# Stop servers
docker compose down
```

### Running Specific Tests

```bash
# TCP tests only
swift test --filter PymodbusIntegrationTests/readHoldingRegisters

# TLS tests only
swift test --filter PymodbusIntegrationTests/tls
```

## Test Data Patterns

Reference servers use consistent data patterns for validation:

| Data Type | Pattern |
|-----------|---------|
| Coils | Alternating true/false (address % 2 == 0) |
| Discrete Inputs | First 100 true, rest false |
| Holding Registers | Sequential: address + 1 (pymodbus 1-based) |
| Input Registers | address × 10 |

## Docker Services

| Service | Port | Description |
|---------|------|-------------|
| `pymodbus-server` | 5020 | TCP reference server |
| `pymodbus-tls-server` | 5021 | TLS reference server |

### Docker Commands

```bash
# Start specific server
docker compose up -d pymodbus-server
docker compose up -d pymodbus-tls-server

# Start all servers
docker compose up -d

# View logs
docker compose logs -f pymodbus-server
docker compose logs -f pymodbus-tls-server

# Stop all
docker compose down

# Rebuild after changes
docker compose build --no-cache
```

## TLS Certificate Management

TLS tests use self-signed certificates located in `docker/pymodbus-tls-server/certs/`.

### Regenerate Certificates

```bash
cd docker/pymodbus-tls-server
./generate_certs.sh certs
```

### Certificate Files

| File | Purpose |
|------|---------|
| `ca.crt` | CA certificate (for client trust) |
| `ca.key` | CA private key |
| `server.crt` | Server certificate |
| `server.key` | Server private key |
| `client.crt` | Client certificate (for mTLS) |
| `client.key` | Client private key |

## CI Integration

For CI environments:

```bash
# Start servers and wait for health checks
docker compose up -d --wait

# Run tests
swift test

# Cleanup
docker compose down
```

## Troubleshooting

### Server not running

```
Reference server not running at 127.0.0.1:5020
```

Start the server:
```bash
docker compose up -d
```

### Certificate errors

Regenerate certificates:
```bash
cd docker/pymodbus-tls-server
./generate_certs.sh certs
docker compose build pymodbus-tls-server
```

### Port conflicts

Check if ports are in use:
```bash
lsof -i :5020
lsof -i :5021
```
