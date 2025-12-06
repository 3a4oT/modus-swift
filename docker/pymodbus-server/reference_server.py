#!/usr/bin/env python3
"""
ModbusKit Reference Validation Server

A pymodbus-based Modbus TCP server for validating ModbusKit client implementation.
This server provides a reference implementation that follows the Modbus specification.

Usage:
    python3 Scripts/reference_server.py [--port PORT] [--host HOST]

The server outputs the assigned port to stdout in the format:
    MODBUS_PORT=<port>

This allows parent processes (Swift tests) to discover the ephemeral port.

Reference: https://pymodbus.readthedocs.io/
"""

import argparse
import asyncio
import json
import signal
import sys

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
    from pymodbus.server import ModbusTcpServer
    # pymodbus 3.11+ moved ModbusDeviceIdentification to top-level
    try:
        from pymodbus import ModbusDeviceIdentification
    except ImportError:
        from pymodbus.device import ModbusDeviceIdentification
    from pymodbus import __version__ as pymodbus_version
except ImportError:
    print("ERROR: pymodbus not installed. Run: pip3 install pymodbus>=3.5.0", file=sys.stderr)
    sys.exit(1)


class ReferenceServer:
    """
    Reference Modbus TCP server for validation testing.

    Features:
    - Ephemeral port binding (port 0)
    - Pre-configured test data patterns
    - All standard Modbus data types (coils, discrete inputs, holding/input registers)
    - Device Identification (FC 0x2B/0x0E)
    - Proper address space boundaries
    - Clean shutdown handling
    """

    # Address space configuration (matches typical Modbus devices)
    COIL_COUNT = 1000
    DISCRETE_INPUT_COUNT = 1000
    HOLDING_REGISTER_COUNT = 1000
    INPUT_REGISTER_COUNT = 1000

    # Device Identification values for FC 0x2B/0x0E testing
    VENDOR_NAME = "ModbusKit"
    PRODUCT_CODE = "Petro-Rovenskyi"
    VENDOR_URL = "https://petro.rovenskyi.com"
    PRODUCT_NAME = "Reference Server"
    MODEL_NAME = "PyModbus Test Server"
    MAJOR_MINOR_REVISION = "1.0.0"

    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self.host = host
        self.port = port
        self.actual_port: int | None = None
        self.server: ModbusTcpServer | None = None

    def _create_datastore(self) -> ModbusServerContext:
        """
        Create datastore with test data patterns.

        Data patterns for validation:
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

        # Single device context (unit ID 1)
        # Also accepts broadcast (unit ID 0) and unit ID 247 for testing
        # pymodbus 3.7+ renamed 'slaves' to 'devices'
        return ModbusServerContext(devices=store, single=True)

    def _create_identity(self) -> ModbusDeviceIdentification:
        """
        Create device identification for FC 0x2B/0x0E testing.

        Reference: Modbus Application Protocol Specification V1.1b3, Section 6.21
        Object IDs per Modbus spec Table 5-2:
            0x00 = VendorName
            0x01 = ProductCode
            0x02 = MajorMinorRevision
            0x03 = VendorUrl
            0x04 = ProductName
            0x05 = ModelName
        """
        # Use numeric object IDs for pymodbus 3.11+ compatibility
        identity = ModbusDeviceIdentification(
            info={
                0x00: self.VENDOR_NAME,          # VendorName
                0x01: self.PRODUCT_CODE,         # ProductCode
                0x02: self.MAJOR_MINOR_REVISION, # MajorMinorRevision
                0x03: self.VENDOR_URL,           # VendorUrl
                0x04: self.PRODUCT_NAME,         # ProductName
                0x05: self.MODEL_NAME,           # ModelName
            }
        )
        return identity

    async def start(self) -> int:
        """
        Start the server and return the assigned port.

        Returns:
            The actual port number (useful when port=0 for ephemeral binding)
        """
        context = self._create_datastore()
        identity = self._create_identity()

        # Create server instance with identity for FC 0x2B/0x0E support
        self.server = ModbusTcpServer(
            context=context,
            identity=identity,
            address=(self.host, self.port),
        )

        # Start server in background mode - this binds the socket
        await self.server.serve_forever(background=True)

        # Get actual port from server transport
        # pymodbus 3.x: transport is asyncio.Server with sockets attribute
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


async def main(host: str, port: int, verbose: bool = False):
    """Main entry point."""
    server = ReferenceServer(host=host, port=port)
    shutdown_event = asyncio.Event()

    # Setup signal handlers
    loop = asyncio.get_running_loop()

    def signal_handler():
        shutdown_event.set()

    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, signal_handler)

    try:
        actual_port = await server.start()

        # Output port for parent process discovery
        # This is the key mechanism for Swift tests to find the server
        # CRITICAL: flush=True ensures immediate output before blocking
        print(f"MODBUS_PORT={actual_port}", flush=True)

        if verbose:
            print(f"pymodbus version: {pymodbus_version}", file=sys.stderr)
            print(f"Server listening on {host}:{actual_port}", file=sys.stderr)
            print("Press Ctrl+C to stop", file=sys.stderr)

        # Wait for shutdown signal
        await shutdown_event.wait()

    finally:
        if verbose:
            print("Shutting down...", file=sys.stderr)
        await server.stop()


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="ModbusKit Reference Validation Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Data Patterns:
  Coils (FC 0x01):           Alternating True/False
  Discrete Inputs (FC 0x02): First 100 True, rest False
  Holding Registers (FC 0x03): Sequential 0, 1, 2, ...
  Input Registers (FC 0x04):  Value = Address * 10

Device Identification (FC 0x2B/0x0E):
  VendorName:          ModbusKit
  ProductCode:         Petro-Rovenskyi
  VendorUrl:           https://petro.rovenskyi.com
  ProductName:         Reference Server
  ModelName:           PyModbus Test Server
  MajorMinorRevision:  1.0.0

Examples:
  # Start with ephemeral port (for testing)
  python3 reference_server.py

  # Start on specific port
  python3 reference_server.py --port 5020

  # Verbose mode
  python3 reference_server.py -v
        """,
    )

    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="Port to bind to (default: 0 for ephemeral)",
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
        # JSON output mode for programmatic discovery
        async def json_main():
            server = ReferenceServer(host=args.host, port=args.port)
            shutdown_event = asyncio.Event()

            loop = asyncio.get_running_loop()
            for sig in (signal.SIGTERM, signal.SIGINT):
                loop.add_signal_handler(sig, lambda: shutdown_event.set())

            port = await server.start()
            print(json.dumps({
                "host": args.host,
                "port": port,
                "pymodbus_version": pymodbus_version,
                "status": "running",
            }), flush=True)
            await shutdown_event.wait()
            await server.stop()

        asyncio.run(json_main())
    else:
        asyncio.run(main(args.host, args.port, args.verbose))
