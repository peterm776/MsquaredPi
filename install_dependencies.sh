#!/bin/bash

echo "diagnosing architecture..."
ARCH=$(uname -m)
echo "Current Architecture: $ARCH"

if [ "$ARCH" == "x86_64" ]; then
    # Check if we are actually on Apple Silicon but running in Rosetta
    IS_TRANSLATED=$(sysctl -n sysctl.proc_translated 2>/dev/null)
    
    if [ "$IS_TRANSLATED" == "1" ]; then
        echo "========================================================"
        echo "CRITICAL WARNING: You are running this terminal in Rosetta mode (Intel emulation)."
        echo "This causes issues with Colima/Lima which require native ARM64 compilation."
        echo "========================================================"
        echo "Please do the following:"
        echo "1. Close this terminal."
        echo "2. Open Finder, go to Applications > Utilities."
        echo "3. Right-click Terminal.app -> Get Info."
        echo "4. Uncheck 'Open using Rosetta'."
        echo "5. Restart Terminal and run this script again."
        exit 1
    fi
fi

echo "Attempting to fix/start Colima..."

if command -v colima &> /dev/null; then
    echo "Stopping any existing instance..."
    colima stop 2>/dev/null

    echo "Starting Colima..."
    # We use aarch64 (native) VM. Docker handles non-native binaries (like armv7) via binfmt/qemu automatically.
    # Removed --vz-rosetta as it's not supported in all versions/configurations or redundant here.
    colima start --arch aarch64 --cpu 2 --memory 2 --vm-type=vz 
else
    echo "Error: Colima not found. Please ensure brew install was successful."
    echo "Try manual install: brew install colima docker"
    exit 1
fi

echo "Configuration complete."
echo "You can now run ./run_with_display.sh"
