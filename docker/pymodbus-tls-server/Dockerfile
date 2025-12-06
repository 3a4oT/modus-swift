# SPDX-License-Identifier: Apache-2.0
# Copyright 2025 Petro Rovenskyi
#
# ModbusKit TLS Reference Server
#
# Provides a pymodbus-based Modbus/TCP Security server for validation testing.
# Port 5021 is used instead of standard 802 to avoid requiring root privileges.
#
# Build:
#   docker build -t modbus-tls-reference-server docker/pymodbus-tls-server
#
# Run:
#   docker run -p 5021:5021 modbus-tls-reference-server

FROM python:3.12-slim

LABEL maintainer="Petro Rovenskyi"
LABEL description="PyModbus TLS Reference Server for ModbusKit validation"

# Install pymodbus
RUN pip install --no-cache-dir pymodbus>=3.5.0

WORKDIR /app

# Copy server script
COPY tls_reference_server.py .

# Copy certificates
COPY certs/ certs/

# Expose TLS port (using 5021 to avoid requiring root for port 802)
EXPOSE 5021

# Health check - verify TLS connection
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import socket, ssl; ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE; s = ctx.wrap_socket(socket.socket(), server_hostname='localhost'); s.settimeout(2); s.connect(('127.0.0.1', 5021)); s.close()" || exit 1

# Run server on port 5021 with verbose output
CMD ["python3", "tls_reference_server.py", "--port", "5021", "-v"]
