#!/bin/bash

# Check local bin first
export PATH="$(pwd)/tools/bin:$PATH"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    # If docker client is missing (binary), we might need to get that too, 
    # but usually the brew one works fine as a client even if x86.
    if [ -f "$(pwd)/tools/bin/docker" ]; then
         echo "Found local docker client."
    else
         echo "Error: docker command not found."
         # Quick client fetch if needed, but assuming manual install worked or brew present
         echo "Please ensure docker client is in PATH."
         exit 1
    fi
fi

# Ensure the Docker daemon (Colima) is running
if [ -f "$(pwd)/tools/bin/colima" ]; then
    COLIMA_CMD="$(pwd)/tools/bin/colima"
else
    COLIMA_CMD="colima"
fi

if ! docker info &> /dev/null; then
    echo "Docker daemon is not running. Attempting to start Colima..."
    $COLIMA_CMD start --arch aarch64
fi

echo "Downloading and running Minecraft Pi in Docker (Native ARM64 Host -> 32-bit Emulation)..."

# Explanation:
# - Apple Silicon M2/M3 has NO hardware 32-bit support.
# - We use Ubuntu 16.04 (ARM64) as base because it still has 'libpng12' in repos.
# - We enable 'armhf' (32-bit) architecture to download the 32-bit libraries the game needs.
# - We use 'qemu-user' to emulate the CPU instructions.
# - We set QEMU_LD_PREFIX so qemu knows where to find the 32-bit libs.

docker run --rm -it \
  --platform linux/arm64 \
  -v "$(pwd)":/game \
  -w /game \
  ubuntu:16.04 \
  /bin/bash -c "
    echo '1. Enabling 32-bit architecture...' && \
    dpkg --add-architecture armhf && \
    echo \"Acquire::http::Pipeline-Depth 0;\" > /etc/apt/apt.conf.d/99custom && \
    echo \"Acquire::http::No-Cache true;\" >> /etc/apt/apt.conf.d/99custom && \
    echo \"Acquire::BrokenProxy true;\" >> /etc/apt/apt.conf.d/99custom && \
    rm -rf /var/lib/apt/lists/* && \
    (apt-get update || apt-get update) && \
    
    echo '2. Installing Core System Dependencies (Modern)...' && \
    apt-get install -y --fix-missing qemu-user libc6:armhf libstdc++6:armhf libpng12-0:armhf libsdl1.2debian:armhf libx11-xcb1:armhf libxcb1:armhf libx11-6:armhf xvfb x11-utils gcc-arm-linux-gnueabihf file \
        libxcb-dri2-0:armhf libxcb-dri3-0:armhf libxcb-present0:armhf libxcb-sync1:armhf libxshmfence1:armhf libxcb-glx0:armhf \
        libxcb-xfixes0:armhf libxcb-shape0:armhf libxcb-randr0:armhf \
        libwayland-client0:armhf libwayland-server0:armhf libwayland-cursor0:armhf libgbm1:armhf && \
    
    echo '2b. Side-Loading Legacy Mesa 11.2.0 (for GLESv1 Support)...' && \
    mkdir -p /opt/mcpi-compat /opt/debs && \
    cd /opt/debs && \
    apt-get download \
        libglapi-mesa:armhf=11.2.0-1ubuntu2 \
        libgl1-mesa-dri:armhf=11.2.0-1ubuntu2 \
        libgles1-mesa:armhf=11.2.0-1ubuntu2 \
        libgles2-mesa:armhf=11.2.0-1ubuntu2 \
        libegl1-mesa:armhf=11.2.0-1ubuntu2 && \
    
    echo 'Extracting legacy libraries...' && \
    for deb in *.deb; do dpkg -x \"\$deb\" /opt/mcpi-compat; done && \
    cd /game && \
    
    # Define variables dynamically inside the container so they persist
    COMPAT_LIB=\"/opt/mcpi-compat/usr/lib/arm-linux-gnueabihf\" && \
    COMPAT_EGL=\"/opt/mcpi-compat/usr/lib/arm-linux-gnueabihf/mesa-egl\" && \
    
    echo '3. Configuring Environment...' && \
    
    # Fix missing unversioned symlinks (Game wants .so, debs provide .so.2)
    echo 'Creating libGLESv2/EGL symlinks...' && \
    find /opt/mcpi-compat -name \"libGLESv2.so.2\" -exec sh -c 'ln -sf \$(basename {}) \$(dirname {})/libGLESv2.so' \; && \
    find /opt/mcpi-compat -name \"libEGL.so.1\" -exec sh -c 'ln -sf \$(basename {}) \$(dirname {})/libEGL.so' \; && \
    
    ls -la \"\$COMPAT_EGL/libGLESv1_CM.so.1\" || echo 'ERROR: libGLESv1_CM.so.1 NOT FOUND!' && \
    ls -la \"\$COMPAT_EGL/libGLESv2.so\" || echo 'ERROR: libGLESv2.so SYMLINK FAILED!' && \

    # Fix ELF Interpreter (Loader) - Find REAL file (-type f) to avoid circular symlinks
    LOADER=\$(find /lib /usr/lib -name ld-linux-armhf.so.3 -type f | head -n 1) && \
    if [ -n \"\$LOADER\" ]; then \
        echo \"Found real loader at \$LOADER. Checking symlink...\" && \
        if [ \"\$LOADER\" != \"/lib/ld-linux-armhf.so.3\" ]; then \
            mkdir -p /lib && \
            ln -sf \"\$LOADER\" /lib/ld-linux-armhf.so.3 && \
            echo \"Symlinked to /lib/ld-linux-armhf.so.3\"; \
        else \
             echo \"Loader is already in the correct place.\"; \
        fi; \
    else \
        echo \"CRITICAL ERROR: ARMHF Loader ld-linux-armhf.so.3 not found!\"; \
    fi && \

    # Create Dummy libbcm_host.so
    echo 'Creating dummy libbcm_host stub...' && \
    echo \"#include <stdint.h>\" > bcm_stub.c && \
    echo \"
    int bcm_host_init() { return 0; } 
    int bcm_host_deinit() { return 0; } 
    int graphics_get_display_size(int d, uint32_t *w, uint32_t *h) { *w=800; *h=600; return 0; }
    int vc_dispmanx_display_open(int device) { return 1; }
    int vc_dispmanx_update_start(int priority) { return 1; }
    int vc_dispmanx_element_add(int u, int d, int l, void *dr, int s, void *sr, int p, void *a, void *c, int t) { return 1; }
    int vc_dispmanx_update_submit_sync(int u) { return 0; }
    int vc_dispmanx_element_remove(int u, int e) { return 0; }
    int vc_dispmanx_display_close(int d) { return 0; }
    \" >> bcm_stub.c && \
    arm-linux-gnueabihf-gcc -shared -o /usr/lib/arm-linux-gnueabihf/libbcm_host.so -fPIC bcm_stub.c && \

    echo '4. Running Minecraft Pi...' && \
    
    # Locate DRI driver
    DRI_DRIVER=\$(find /opt/mcpi-compat -name swrast_dri.so | head -n 1) && \
    if [ -n \"\$DRI_DRIVER\" ]; then \
        DRI_PATH=\$(dirname \"\$DRI_DRIVER\"); \
        echo \"Found DRI driver at: \$DRI_DRIVER\"; \
    else \
        echo \"WARNING: swrast_dri.so not found! Rendering may fail.\"; \
        DRI_PATH=\"\$COMPAT_LIB/dri\"; \
    fi && \

    # Debug: Check cwd contents
    echo \"Current Directory content:\" && \
    ls -la && \
    
    # Ensure binary is executable
    if [ -f \"./minecraft-pi\" ]; then \
        chmod +x ./minecraft-pi; \
        echo \"Binary info:\" && \
        file ./minecraft-pi && \
        ls -l /lib/ld-linux-armhf.so.3; \
    else \
        echo \"CRITICAL ERROR: ./minecraft-pi NOT FOUND in \$(pwd)\"; \
    fi && \
    
    # Construct paths
    GAME_LD_LIBRARY_PATH=\"\$COMPAT_EGL:\$COMPAT_LIB:/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf\" && \
    GAME_LD_PRELOAD=\"\$COMPAT_EGL/libGLESv1_CM.so.1\" && \
    
    echo \"LD_LIBRARY_PATH (Guest) is: \$GAME_LD_LIBRARY_PATH\" && \
    echo \"LD_PRELOAD (Guest) is: \$GAME_LD_PRELOAD\" && \
    
    echo \"Starting Xvfb and Game...\" && \
    
    # We pass corrected DRI Path
    xvfb-run --auto-servernum --server-args='-screen 0 800x600x24' \
    qemu-arm \
      -E LD_LIBRARY_PATH=\"\$GAME_LD_LIBRARY_PATH\" \
      -E LD_PRELOAD=\"\$GAME_LD_PRELOAD\" \
      -E LIBGL_DRIVERS_PATH=\"\$DRI_PATH\" \
      ./minecraft-pi
  "
