# Minecraft Pi on Apple Silicon (macOS) via Docker

This repository contains scripts to run the original 32-bit ARM binary of **Minecraft: Pi Edition** (2013) on modern Apple Silicon Macs (M1/M2/M3) using Docker, QEMU, and XQuartz. 

Because the game was compiled specifically for the Raspberry Pi's VideoCore IV GPU, it cannot run natively on macOS. This solution bypasses the hardware requirements by emulating an ARMhf environment and injecting a custom EGL shim to route the graphics to a standard X11 window.

## Prerequisites

1.  **Homebrew** must be installed on your Mac.
2.  **XQuartz** must be installed and configured:
    ```bash
    brew install --cask xquartz
    ```
    *Important: Open XQuartz > Settings > Security and check **"Allow connections from network clients"**.*
3.  **Docker & Colima**:
    Install the dependencies using the provided script which sets up an aarch64 virtual machine:
    ```bash
    chmod +x install_dependencies.sh
    ./install_dependencies.sh
    ```

## Usage

To launch the game with full graphical output, run:

```bash
chmod +x run_with_display.sh
./run_with_display.sh
```

**What the script does under the hood:**
1. Pulls an Ubuntu 16.04 image (to access legacy `libpng12` and compatible `libsdl1.2` versions).
2. Enables `armhf` multi-architecture and downloads necessary legacy Mesa libraries.
3. Compiles `bcm_stub.c`, a custom EGL shim that intercepts the game's native Raspberry Pi "DispmanX" window calls and forcefully redirects them to an SDL / X11 window surface.
4. Mounts a local `games/` folder into the container's `~/.minecraft/games/` directory so your worlds are permanently saved on your Mac.
5. Emulates the execution environment using `qemu-arm` and software rendering (`llvmpipe` with multi-threading).

## Included Files
*   `run_with_display.sh`: The main launcher script (automatically downloads the game client from official Minecraft servers).
*   `install_dependencies.sh`: Host configuration for Colima/Docker.
*   `bcm_stub.c`: The C source code for the custom EGL wrapper.

## Troubleshooting
*   **Black Screen or Not Loading?** Make sure you ran `xhost +` or `xhost +localhost` on your Mac terminal to allow the Docker container to connect to your screen.
*   **Performance is slow?** The game uses software emulation. The script dynamically lowers the internal rendering resolution and turns on multi-threading to make it playable, but it will not run at native 60FPS. 
