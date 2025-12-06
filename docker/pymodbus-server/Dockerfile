# PyModbus Reference Server for ModbusKit Validation
# Based on Python 3.12 slim for minimal image size

FROM python:3.12-slim

LABEL org.opencontainers.image.title="PyModbus Reference Server"
LABEL org.opencontainers.image.description="Modbus TCP server for validating ModbusKit implementation"
LABEL org.opencontainers.image.version="1.0"

# Install pymodbus
RUN pip install --no-cache-dir "pymodbus>=3.11.0"

# Create non-root user
RUN useradd --create-home --shell /bin/bash modbus
USER modbus
WORKDIR /home/modbus

# Copy server script
COPY --chown=modbus:modbus reference_server.py .

# Default port
ENV MODBUS_PORT=5020
ENV MODBUS_HOST=0.0.0.0

EXPOSE 5020

# Health check - verify server responds to TCP connection
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1', 5020)); s.close()" || exit 1

# Run server
CMD ["python", "reference_server.py", "--host", "0.0.0.0", "--port", "5020", "-v"]
