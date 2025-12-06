#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2025 Petro Rovenskyi
#
# Generate self-signed TLS certificates for Modbus/TCP Security testing.
#
# Creates:
#   - CA certificate (ca.crt, ca.key)
#   - Server certificate signed by CA (server.crt, server.key)
#   - Client certificate signed by CA (client.crt, client.key) - optional for mTLS
#
# Reference: Modbus/TCP Security Protocol Specification
# - Requires TLS 1.2 minimum
# - Port 802 default
#
# Usage:
#   ./generate_certs.sh [output_dir]
#
# Example:
#   ./generate_certs.sh certs/

set -e

OUTPUT_DIR="${1:-certs}"
mkdir -p "$OUTPUT_DIR"

# Certificate validity (days)
VALIDITY=365

# Common settings
COUNTRY="UA"
STATE="Kyiv"
LOCALITY="Kyiv"
ORGANIZATION="ModbusKit"
ORG_UNIT="Testing"

echo "Generating TLS certificates in $OUTPUT_DIR..."

# 1. Generate CA private key and certificate
echo "1. Creating CA certificate..."
openssl genrsa -out "$OUTPUT_DIR/ca.key" 4096

openssl req -new -x509 -days $VALIDITY -key "$OUTPUT_DIR/ca.key" \
    -out "$OUTPUT_DIR/ca.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=ModbusKit Test CA"

# 2. Generate server private key and CSR
echo "2. Creating server certificate..."
openssl genrsa -out "$OUTPUT_DIR/server.key" 2048

openssl req -new -key "$OUTPUT_DIR/server.key" \
    -out "$OUTPUT_DIR/server.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=localhost"

# Create server certificate extensions file
cat > "$OUTPUT_DIR/server_ext.cnf" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = modbus-tls-server
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Sign server certificate with CA
openssl x509 -req -days $VALIDITY \
    -in "$OUTPUT_DIR/server.csr" \
    -CA "$OUTPUT_DIR/ca.crt" \
    -CAkey "$OUTPUT_DIR/ca.key" \
    -CAcreateserial \
    -out "$OUTPUT_DIR/server.crt" \
    -extfile "$OUTPUT_DIR/server_ext.cnf"

# 3. Generate client certificate (for mTLS testing)
echo "3. Creating client certificate..."
openssl genrsa -out "$OUTPUT_DIR/client.key" 2048

openssl req -new -key "$OUTPUT_DIR/client.key" \
    -out "$OUTPUT_DIR/client.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/OU=$ORG_UNIT/CN=ModbusKit Client"

# Create client certificate extensions file
cat > "$OUTPUT_DIR/client_ext.cnf" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = clientAuth
EOF

# Sign client certificate with CA
openssl x509 -req -days $VALIDITY \
    -in "$OUTPUT_DIR/client.csr" \
    -CA "$OUTPUT_DIR/ca.crt" \
    -CAkey "$OUTPUT_DIR/ca.key" \
    -CAcreateserial \
    -out "$OUTPUT_DIR/client.crt" \
    -extfile "$OUTPUT_DIR/client_ext.cnf"

# Cleanup CSR and extension files
rm -f "$OUTPUT_DIR"/*.csr "$OUTPUT_DIR"/*.cnf "$OUTPUT_DIR"/*.srl

# Set permissions
chmod 644 "$OUTPUT_DIR"/*.crt
chmod 600 "$OUTPUT_DIR"/*.key

echo ""
echo "Certificates generated successfully:"
echo "  CA:     $OUTPUT_DIR/ca.crt, $OUTPUT_DIR/ca.key"
echo "  Server: $OUTPUT_DIR/server.crt, $OUTPUT_DIR/server.key"
echo "  Client: $OUTPUT_DIR/client.crt, $OUTPUT_DIR/client.key"
echo ""
echo "To verify server certificate:"
echo "  openssl verify -CAfile $OUTPUT_DIR/ca.crt $OUTPUT_DIR/server.crt"
