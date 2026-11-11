#!/usr/bin/env bash
set -euo pipefail

SIGNING_DIR="${HOME}/SchoolPresence-Apple-Signing"
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ -e "$SIGNING_DIR/apple-distribution.key" || -e "$SIGNING_DIR/apple-distribution.csr" ]]; then
  echo "Signing key or CSR already exists in $SIGNING_DIR; refusing to overwrite it." >&2
  exit 1
fi

openssl genrsa -out "$SIGNING_DIR/apple-distribution.key" 2048
chmod 600 "$SIGNING_DIR/apple-distribution.key"
openssl req -new \
  -key "$SIGNING_DIR/apple-distribution.key" \
  -out "$SIGNING_DIR/apple-distribution.csr" \
  -subj "/CN=SchoolPresence Apple Distribution/"

echo "CSR ready: $SIGNING_DIR/apple-distribution.csr"
echo "Keep apple-distribution.key private. Do not upload it to GitHub or send it in chat."
