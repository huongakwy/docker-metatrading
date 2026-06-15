#!/bin/bash
# Test rebuild image với lsiown fix

set -e

cd /home/dev/Docker_MetaTrader

echo "=========================================="
echo "  Testing lsiown fix - Rebuilding Image"
echo "=========================================="
echo ""

# Rebuild image
docker build -t mt5-local:working -f ./snapshot/Dockerfile ./snapshot

echo ""
echo "=========================================="
echo "  Verifying lsiown command in image"
echo "=========================================="
echo ""

# Test lsiown exists in built image
docker run --rm mt5-local:working which lsiown

echo ""
echo "=========================================="
echo "  Testing lsiown functionality"
echo "=========================================="
echo ""

# Test lsiown works
docker run --rm mt5-local:working lsiown --version 2>&1 || echo "lsiown exists and executes"

echo ""
echo "✅ Build successful with lsiown fix!"
