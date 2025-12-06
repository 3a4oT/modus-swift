#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2025 Petro Rovenskyi
"""
ModbusKit TLS Reference Validation Server

A pymodbus-based Modbus/TCP Security server for validating ModbusTLSClient.
This server implements Modbus over TLS as specified in the Modbus/TCP Security
Protocol Specification.

Requirements:
    - TLS 1.2 minimum (per Modbus/TCP Security spec)
    - Port 802 default (standard Modbus/TCP Security port)
    - Server certificate with proper SAN for localhost/127.0.0.1

Usage:
    python3 tls_reference_server.py [--port PORT] [--host HOST]

The server outputs the assigned port to stdout in the format:
    MODBUS_TLS_PORT=<port>

Reference:
    - https://pymodbus.readthedocs.io/
    - Modbus/TCP Security Protocol Specification
"""

import argparse
import asyncio
import json
import signal
import ssl
import sys
from pathlib import Path

try:
    from pymodbus.datastore import (
        ModbusSequentialDataBlock,
        ModbusServerContext,
    )
    # pymodbus 3.7+ renamed ModbusSlaveContext to ModbusDeviceContext
    try:
        from pymodbus.datastore import ModbusDeviceContext
    except ImportError:
        from pymodbus.datastore import ModbusSlaveContext as ModbusDeviceContext
    from pymodbus.server import ModbusTlsServer
    # pymodbus 3.11+ moved ModbusDeviceIdentification to top-level
    try:
        from pymodbus import ModbusDeviceIdentification
    except ImportError:
        from pymodbus.device import ModbusDeviceIdentification
    from pymodbus import __version__ as pymodbus_version
except ImportError:
    print("ERROR: pymodbus not installed. Run: pip3 install pymodbus>=3.5.0", file=sys.stderr)
    sys.exit(1)


class TLSReferenceServer:
    """
    Reference Modbus/TCP Security server for validation testing.

    Features:
    - TLS 1.2+ encryption (per Modbus/TCP Security spec)
    - Self-signed certificate support
    - Pre-configured test data patterns (same as TCP server)
    - All standard Modbus data types
    - Device Identification (FC 0x2B/0x0E)
    - Clean shutdown handling
    """

    # Address space configuration (same as TCP reference server)
    COIL_COUNT = 1000
    DISCRETE_INPUT_COUNT = 1000
    HOLDING_REGISTER_COUNT = 1000
    INPUT_REGISTER_COUNT = 1000

    # Device Identification values
    VENDOR_NAME = "ModbusKit"
    PRODUCT_CODE = "Petro-Rovenskyi"
    VENDOR_URL = "https://petro.rovenskyi.com"
    PRODUCT_NAME = "TLS Reference Server"
    MODEL_NAME = "PyModbus TLS Test Server"
    MAJOR_MINOR_REVISION = "1.0.0"

    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 802,
        certfile: str = "certs/server.crt",
        keyfile: str = "certs/server.key",
        cafile: str | None = None,
    ):
        self.host = host
        self.port = port
        self.certfile = certfile
        self.keyfile = keyfile
        self.cafile = cafile
        self.actual_port: int | None = None
        self.server: ModbusTlsServer | None = None

    def _create_ssl_context(self) -> ssl.SSLContext:
        """
        Create SSL context for TLS server.

        Per Modbus/TCP Security spec:
        - Minimum TLS 1.2
        - Server authentication required
        - Client authentication optional (for mTLS)
        """
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)

        # Minimum TLS 1.2 per Modbus/TCP Security spec
        context.minimum_version = ssl.TLSVersion.TLSv1_2

        # Load server certificate and key
        context.load_cert_chain(
            certfile=self.certfile,
            keyfile=self.keyfile,
        )

        # Optional: Load CA for client certificate verification (mTLS)
        if self.cafile:
            context.load_verify_locations(cafile=self.cafile)
            context.verify_mode = ssl.CERT_OPTIONAL
        else:
            context.verify_mode = ssl.CERT_NONE

        return context

    def _create_datastore(self) -> ModbusServerContext:
        """
        Create datastore with test data patterns.

        Data patterns match TCP reference server for consistency:
        - Coils: alternating True/False pattern
        - Discrete Inputs: all True for first 100, then False
        - Holding Registers: sequential values 0, 1, 2, ...
        - Input Registers: values = address * 10
        """
        # Coils (FC 0x01, 0x05, 0x0F) - alternating pattern
        coils = [i % 2 == 0 for i in range(self.COIL_COUNT)]

        # Discrete Inputs (FC 0x02) - first 100 True
        discrete_inputs = [i < 100 for i in range(self.DISCRETE_INPUT_COUNT)]

        # Holding Registers (FC 0x03, 0x06, 0x10) - sequential
        holding_registers = list(range(self.HOLDING_REGISTER_COUNT))

        # Input Registers (FC 0x04) - address * 10
        input_registers = [i * 10 for i in range(self.INPUT_REGISTER_COUNT)]

        store = ModbusDeviceContext(
            co=ModbusSequentialDataBlock(0, coils),
            di=ModbusSequentialDataBlock(0, discrete_inputs),
            hr=ModbusSequentialDataBlock(0, holding_registers),
            ir=ModbusSequentialDataBlock(0, input_registers),
        )

        return ModbusServerContext(devices=store, single=True)

    def _create_identity(self) -> ModbusDeviceIdentification:
        """Create device identification for FC 0x2B/0x0E testing."""
        identity = ModbusDeviceIdentification(
            info={
                0x00: self.VENDOR_NAME,
                0x01: self.PRODUCT_CODE,
                0x02: self.MAJOR_MINOR_REVISION,
                0x03: self.VENDOR_URL,
                0x04: self.PRODUCT_NAME,
                0x05: self.MODEL_NAME,
            }
        )
        return identity

    async def start(self) -> int:
        """
        Start the TLS server and return the assigned port.

        Returns:
            The actual port number
        """
        context = self._create_datastore()
        identity = self._create_identity()
        sslctx = self._create_ssl_context()

        self.server = ModbusTlsServer(
            context=context,
            identity=identity,
            address=(self.host, self.port),
            sslctx=sslctx,
        )

        # Start server in background mode
        await self.server.serve_forever(background=True)

        # Get actual port from server transport
        if self.server.transport and hasattr(self.server.transport, 'sockets'):
            sockets = self.server.transport.sockets
            if sockets:
                self.actual_port = sockets[0].getsockname()[1]

        if self.actual_port is None:
            self.actual_port = self.port

        return self.actual_port

    async def stop(self):
        """Stop the server gracefully."""
        if self.server:
            await self.server.shutdown()
            self.server = None


async def main(host: str, port: int, certfile: str, keyfile: str, cafile: str | None, verbose: bool = False):
    """Main entry point."""
    server = TLSReferenceServer(
        host=host,
        port=port,
        certfile=certfile,
        keyfile=keyfile,
        cafile=cafile,
    )
    shutdown_event = asyncio.Event()

    loop = asyncio.get_running_loop()

    def signal_handler():
        shutdown_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler)

    try:
        actual_port = await server.start()

        # Output port for parent process discovery
        print(f"MODBUS_TLS_PORT={actual_port}", flush=True)

        if verbose:
            print(f"pymodbus version: {pymodbus_version}", file=sys.stderr)
            print(f"TLS Server listening on {host}:{actual_port}", file=sys.stderr)
            print(f"Certificate: {certfile}", file=sys.stderr)
            print("Press Ctrl+C to stop", file=sys.stderr)

        await shutdown_event.wait()

    finally:
        if verbose:
            print("Shutting down...", file=sys.stderr)
        await server.stop()


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="ModbusKit TLS Reference Validation Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Data Patterns (same as TCP server):
  Coils (FC 0x01):           Alternating True/False
  Discrete Inputs (FC 0x02): First 100 True, rest False
  Holding Registers (FC 0x03): Sequential 0, 1, 2, ...
  Input Registers (FC 0x04):  Value = Address * 10

TLS Configuration:
  - Minimum TLS 1.2 (per Modbus/TCP Security spec)
  - Server authentication required
  - Client authentication optional (--cafile for mTLS)

Examples:
  # Start with default certificates
  python3 tls_reference_server.py --port 5021

  # Start with custom certificates
  python3 tls_reference_server.py --certfile /path/to/cert.crt --keyfile /path/to/key.key

  # Enable mTLS (client certificate verification)
  python3 tls_reference_server.py --cafile /path/to/ca.crt
        """,
    )

    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Host to bind to (default: 0.0.0.0)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=802,
        help="Port to bind to (default: 802, standard Modbus/TCP Security port)",
    )
    parser.add_argument(
        "--certfile",
        default="certs/server.crt",
        help="Path to server certificate (default: certs/server.crt)",
    )
    parser.add_argument(
        "--keyfile",
        default="certs/server.key",
        help="Path to server private key (default: certs/server.key)",
    )
    parser.add_argument(
        "--cafile",
        default=None,
        help="Path to CA certificate for client verification (mTLS)",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output server info as JSON",
    )

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    if args.json:
        async def json_main():
            server = TLSReferenceServer(
                host=args.host,
                port=args.port,
                certfile=args.certfile,
                keyfile=args.keyfile,
                cafile=args.cafile,
            )
            shutdown_event = asyncio.Event()

            loop = asyncio.get_running_loop()
            for sig in (signal.SIGTERM, signal.SIGINT):
                loop.add_signal_handler(sig, lambda: shutdown_event.set())

            port = await server.start()
            print(json.dumps({
                "host": args.host,
                "port": port,
                "tls": True,
                "certfile": args.certfile,
                "pymodbus_version": pymodbus_version,
                "status": "running",
            }), flush=True)
            await shutdown_event.wait()
            await server.stop()

        asyncio.run(json_main())
    else:
        asyncio.run(main(
            args.host,
            args.port,
            args.certfile,
            args.keyfile,
            args.cafile,
            args.verbose,
        ))
