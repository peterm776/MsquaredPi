#!/bin/bash

# Manual Native Installer for Apple Silicon - Clean Hierarchy
# Usage: Solves the "limactl running under rosetta" error and "template not found" error.

set -e

# We use a 'tools' directory to keep the bin/share hierarchy intact
TOOLS_DIR="$(pwd)/tools"
BIN_DIR="$TOOLS_DIR/bin"

# Cleanup previous attempts
rm -rf "$(pwd)/bin" 2>/dev/null || true
rm -rf "$TOOLS_DIR" 2>/dev/null || true

mkdir -p "$TOOLS_DIR"

echo "Detected Homebrew environment issue (using /usr/local on ARM64)."
echo "Downloading native ARM64 tools to $TOOLS_DIR..."

# 1. Install Lima (Native ARM64)
# Checking latest version: v2.0.3 (Dec 2025)
LIMA_VERSION="2.0.3" 
echo "Downloading Lima v${LIMA_VERSION}..."
curl -L -o lima.tar.gz "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Darwin-arm64.tar.gz"

# Verify download size
SIZE=$(stat -f%z lima.tar.gz)
if [ "$SIZE" -lt 1000 ]; then
    echo "Error: Download failed (too small). Check internet or URL."
    cat lima.tar.gz
    exit 1
fi

# Extract into tools dir. This creates $TOOLS_DIR/bin and $TOOLS_DIR/share
tar -xzf lima.tar.gz -C "$TOOLS_DIR"
rm lima.tar.gz

# 2. Install Colima (Native ARM64)
# Latest version: v0.9.1 (Sep 2025)
COLIMA_VERSION="0.9.1"
echo "Downloading Colima v${COLIMA_VERSION}..."
# Colima usually is just a binary
curl -L -o colima "https://github.com/abiosoft/colima/releases/download/v${COLIMA_VERSION}/colima-Darwin-arm64"
chmod +x colima
# Move colima to the bin directory created by Lima
mv colima "$BIN_DIR/"

echo "Tools installed to $TOOLS_DIR"
ls -l "$TOOLS_DIR"
ls -l "$BIN_DIR"

# Add to path for this session
export PATH="$BIN_DIR:$PATH"
echo "DEBUG: PATH is $PATH"

echo "Starting Colima (Native Mode)..."
# Stop any broken system instances
colima stop --force 2>/dev/null || true

# Start with local binary
"$BIN_DIR/colima" start --arch aarch64 --cpu 2 --memory 2 --vm-type=vz

echo "=========================================="
echo "Native environment ready!"
echo "Use ./run_in_docker.sh to start the game."
echo "=========================================="
