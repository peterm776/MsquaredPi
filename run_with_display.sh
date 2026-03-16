#!/bin/bash

# Check local bin first
export PATH="$(pwd)/tools/bin:$PATH"

# Download Game Client if Missing
if [ ! -f "minecraft-pi" ]; then
    echo "=========================================================="
    echo " Downloading Minecraft Pi client (original binary) "
    echo "=========================================================="
    echo "Fetching from official minecraft.net site..."
    curl -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" -L -o minecraft-pi-0.1.1.tar.gz.zip "https://www.minecraft.net/content/dam/minecraftnet/games/minecraft/software/minecraft-pi-0.1.1.tar.gz.zip"
    
    if [ -f "minecraft-pi-0.1.1.tar.gz.zip" ]; then
        echo "Extracting client..."
        unzip -q minecraft-pi-0.1.1.tar.gz.zip
        tar -xzf minecraft-pi-0.1.1.tar.gz
        
        echo "Moving files and cleaning up..."
        mv mcpi/* .
        rm -rf mcpi minecraft-pi-0.1.1.tar.gz minecraft-pi-0.1.1.tar.gz.zip
        echo "Download successful."
    else
        echo "Error: Failed to download the game client."
        exit 1
    fi
    echo "=========================================================="
fi

# Docker Check
if ! command -v docker &> /dev/null; then
    if [ -f "$(pwd)/tools/bin/docker" ]; then
         echo "Found local docker client."
    else
         echo "Error: docker command not found."
         echo "Please ensure docker client is in PATH."
         exit 1
    fi
fi

# Colima Check
if [ -f "$(pwd)/tools/bin/colima" ]; then
    COLIMA_CMD="$(pwd)/tools/bin/colima"
else
    COLIMA_CMD="colima"
fi

if ! docker info &> /dev/null; then
    echo "Docker daemon is not running. Attempting to start Colima..."
    $COLIMA_CMD start --arch aarch64
fi

echo "=========================================================="
echo " Starting Minecraft Pi with Remote X11 Display"
echo "=========================================================="
echo " IMPORTANT PRE-REQUISITES (macOS Host):"
echo " 1. Install XQuartz (brew install --cask xquartz)"
echo " 2. Open XQuartz > Settings > Security"
echo " 3. CHECK 'Allow connections from network clients'"
echo " 4. Run 'xhost +localhost' or 'xhost +' in a terminal on your Mac"
echo "=========================================================="

echo "Starting Container..."

# We use host.docker.internal to reach the Mac host from inside the container
docker run --rm -it \
  --platform linux/arm64 \
  -v "$(pwd)":/game \
  -w /game \
  -e DISPLAY=host.docker.internal:0 \
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
    # We include dev packages here to compile our shim BEFORE we downgrade to legacy Mesa
    apt-get install -y --fix-missing qemu-user libc6:armhf libstdc++6:armhf libpng12-0:armhf libsdl1.2debian:armhf libsdl1.2-dev:armhf libegl1-mesa-dev:armhf libx11-xcb1:armhf libxcb1:armhf libx11-6:armhf x11-utils gcc-arm-linux-gnueabihf file \
        libxcb-dri2-0:armhf libxcb-dri3-0:armhf libxcb-present0:armhf libxcb-sync1:armhf libxshmfence1:armhf libxcb-glx0:armhf \
        libxcb-xfixes0:armhf libxcb-shape0:armhf libxcb-randr0:armhf \
        libwayland-client0:armhf libwayland-server0:armhf libwayland-cursor0:armhf \
        libtxc-dxtn-s2tc0:armhf libllvm4.0:armhf libelf1:armhf libexpat1:armhf && \
    
    echo '2a. Compiling EGL/SDL Shim...' && \
    # Compile Shim while headers (SDL, EGL) are still present (versions match modern repo)
    if [ -f /game/bcm_stub.c ]; then \
        # Find SDL Header path
        SDL_HEADER=\$(find /usr/include -name \"SDL.h\" | head -n 1) && \
        if [ -n \"\$SDL_HEADER\" ]; then \
             SDL_INC_DIR=\$(dirname \"\$SDL_HEADER\"); \
             echo \"Found SDL headers at: \$SDL_INC_DIR\"; \
        else \
             SDL_INC_DIR=\"/usr/include/SDL\"; \
             echo \"WARNING: SDL headers not found. Using default.\"; \
        fi && \
        
        # Compile!
        # Note: We link against current system libs, but since shim uses dynamic lookup (dlsym) and standard ABI, it works with legacy libs too.
        arm-linux-gnueabihf-gcc -shared -o /usr/lib/arm-linux-gnueabihf/libbcm_host.so -fPIC /game/bcm_stub.c -ldl -lSDL -I\"\$SDL_INC_DIR\"; \
        echo \"Shim compilation successful.\"; \
    else \
        echo \"ERROR: /game/bcm_stub.c not found!\"; \
        exit 1; \
    fi && \

    echo '2b. Installing Diagnostics...' && \
    apt-get install -y x11-utils iputils-ping net-tools && \
    
    echo '2c. Installing Legacy Mesa 11.2.0 (Pinned Stack)...' && \
    # Fix potential partial install states
    dpkg --configure -a || true && \
    # Force overwrite shared config files (like /etc/drirc) using Dpkg Options
    # NOTE: This step will REMOVE the dev packages installed earlier due to conflicts. This is expected.
    apt-get install -y --allow-downgrades -o Dpkg::Options::=\"--force-overwrite\" \
        libglapi-mesa:armhf=11.2.0-1ubuntu2 \
        libgl1-mesa-dri:armhf=11.2.0-1ubuntu2 \
        libgles1-mesa:armhf=11.2.0-1ubuntu2 \
        libgles2-mesa:armhf=11.2.0-1ubuntu2 \
        libegl1-mesa:armhf=11.2.0-1ubuntu2 \
        libgbm1:armhf=11.2.0-1ubuntu2 && \
    
    # Clean up
    rm -rf /opt/mcpi-compat /opt/debs && \
    cd /game && \
    
    # Define variables dynamically inside the container so they persist
    COMPAT_LIB=\"/usr/lib/arm-linux-gnueabihf\" && \
    COMPAT_EGL=\"/usr/lib/arm-linux-gnueabihf/mesa-egl\" && \
    
    echo '3. Configuring Environment...' && \
    
    # Fix missing unversioned symlinks
    find /usr/lib/arm-linux-gnueabihf -name \"libGLESv2.so.2\" -exec sh -c 'ln -sf \$(basename {}) \$(dirname {})/libGLESv2.so' \; && \
    find /usr/lib/arm-linux-gnueabihf -name \"libEGL.so.1\" -exec sh -c 'ln -sf \$(basename {}) \$(dirname {})/libEGL.so' \; && \

    # Fix ELF Interpreter (Loader)
    LOADER=\$(find /lib /usr/lib -name ld-linux-armhf.so.3 -type f | head -n 1) && \
    if [ -n \"\$LOADER\" ]; then \
        if [ \"\$LOADER\" != \"/lib/ld-linux-armhf.so.3\" ]; then \
            mkdir -p /lib && \
            ln -sf \"\$LOADER\" /lib/ld-linux-armhf.so.3; \
        fi; \
    fi && \

    # Create .minecraft directory and symlink games folder for persistence
    mkdir -p /root/.minecraft && \
    if [ -d /game/games ]; then \
        echo \"Mounting host 'games' directory to /root/.minecraft/games...\" && \
        ln -sf /game/games /root/.minecraft/games; \
    else \
        echo \"Creating local games directory...\" && \
        mkdir -p /root/.minecraft/games; \
    fi && \

    echo '4. Running Minecraft Pi...' && \
    
    # Locate GLESv1_CM
    GLES1_PATH=\$(find /usr/lib -name libGLESv1_CM.so.1 | head -n 1) && \
    if [ -z \"\$GLES1_PATH\" ]; then \
        echo \"ERROR: libGLESv1_CM.so.1 not found! Search dump:\"; \
        find /usr/lib -name \"libGLES*\" || true; \
    else \
        echo \"Found GLESv1 at: \$GLES1_PATH\"; \
        GLES1_DIR=\$(dirname \"\$GLES1_PATH\"); \
        ln -sf \"\$GLES1_PATH\" \"\$GLES1_DIR/libGLESv1_CM.so\"; \
    fi && \

    # Ensure binary is executable
    chmod +x ./minecraft-pi && \
    
    GAME_LD_PATH=\"\$GLES1_DIR:/usr/lib/arm-linux-gnueabihf/mesa-egl:/usr/lib/arm-linux-gnueabihf:/lib/arm-linux-gnueabihf\" && \
    
    echo \"LD_LIBRARY_PATH (Guest) is: \$GAME_LD_PATH\" && \
    
    # Copy drirc
    if [ -f /game/drirc ]; then \
        cp /game/drirc /root/.drirc; \
    fi && \

    # Resolve Host IP Dynamically
    HOST_IP=\$(getent hosts host.docker.internal | awk '{ print \$1 }') && \
    if [ -z \"\$HOST_IP\" ]; then \
        HOST_IP=\$(ip route show | grep default | awk '{print \$3}'); \
    fi && \
    
    echo \"Resolved Host IP: \$HOST_IP\" && \
    export DISPLAY=\"\$HOST_IP:0\" && \

    echo \"Connecting to Host X11 Display (\$DISPLAY)...\" && \
    
    # Test X11 connection
    if (echo > /dev/tcp/\$HOST_IP/6000) >/dev/null 2>&1; then \
        echo \"X11 Network Connection Successful! (Port 6000 Open)\" && \
        echo \"Launching game client...\" && \
        true; \
    else \
        echo \"WARNING: X11 Port 6000 is CLOSED.\" && \
        echo \"  Diagnostics:\" && \
        echo \"  - Host IP reachable? \$(ping -c 1 -W 1 \$HOST_IP >/dev/null && echo 'Yes' || echo 'No')\" && \
        echo \"\" && \
        echo \"  Troubleshooting:\" && \
        echo \"  1. Ensure XQuartz is running.\" && \
        echo \"  2. Ensure 'Allow connections from network clients' is checked in XQuartz settings.\" && \
        echo \"  3. Run 'xhost +' in macOS terminal.\" && \
        true; \
    fi && \

    echo \"Starting Minecraft Pi...\" && \
    
    qemu-arm \
      -E DISPLAY=\"\$DISPLAY\" \
      -E LD_LIBRARY_PATH=\"\$GAME_LD_PATH\" \
      -E LD_PRELOAD=\"/usr/lib/arm-linux-gnueabihf/libbcm_host.so:\$GLES1_PATH\" \
      -E LIBGL_ALWAYS_SOFTWARE=1 \
      -E GALLIUM_DRIVER=llvmpipe \
      -E LP_NUM_THREADS=8 \
      -E MESA_GL_VERSION_OVERRIDE=2.1 \
      -E MESA_GLES_VERSION_OVERRIDE=1.1 \
      ./minecraft-pi 2>&1
  "
