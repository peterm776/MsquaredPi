#!/bin/bash

echo "Compiling fixer_loader..."
gcc fixer_loader.c -o run_mcpi

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    echo "Run ./run_mcpi to attempt to start the game."
    echo ""
    echo "NOTE: Running 32-bit ARM Linux binaries on macOS is complex."
    echo "If the direct loader fails, the most reliable method is using Docker."
    echo "Command: docker run --rm -it --platform linux/arm/v7 -v \"\$(pwd)\":/game -w /game ubuntu:18.04 ./minecraft-pi"
else
    echo "Compilation failed."
fi
