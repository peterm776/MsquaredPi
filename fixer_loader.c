#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MCPI_BINARY "minecraft-pi"

int main(int argc, char *argv[]) {
  printf("Starting Minecraft Pi Compatibility Loader for Apple Silicon...\n");

  // 1. Check if minecraft-pi binary exists
  struct stat buffer;
  if (stat(MCPI_BINARY, &buffer) != 0) {
    fprintf(stderr, "Error: '%s' binary not found in current directory.\n",
            MCPI_BINARY);
    return 1;
  }

  // 2. Construct the command to run via QEMU
  // We use qemu-arm (user mode emulation) to run the 32-bit ARM binary
  // dynamic linker prefix might be needed depending on qemu setup, but qemu-ar
  // usually handles it if libraries are present. However, on macOS, we don't
  // have the linux libraries natively. This is a "best effort" loader. For a
  // full experience, a Docker container or full VM is usually better, but this
  // attempts to run it directly if the user has qemu set up with binfmt or just
  // qemu-arm.

  // Attempt 1: Try running directly assuming binfmt is set (unlikely on stock
  // macOS but possible) Attempt 2: Explicitly invoke qemu-arm

  char command[1024];
  // We assume 'qemu-arm' is in the path.
  // We also set library path to current directory in case user dumped libs
  // there.
  snprintf(command, sizeof(command), "qemu-arm -L . ./%s", MCPI_BINARY);

  printf("Executing: %s\n", command);
  printf("NOTE: If this fails, you may need ARM Linux libraries (libc.so.6, "
         "ld-linux-armhf.so.3, etc.) in the current directory or a sysroot.\n");

  int result = system(command);

  if (result != 0) {
    fprintf(stderr, "\nExecution failed (code %d).\n", result);
    fprintf(stderr, "Troubleshooting:\n");
    fprintf(stderr, "1. Ensure 'qemu' is installed (brew install qemu)\n");
    fprintf(stderr, "2. You need ARM HF libraries. Running Linux binaries on "
                    "macOS directly effectively requires a Linux sysroot.\n");
    fprintf(
        stderr,
        "   Consider using Docker: 'docker run --rm --platform linux/arm/v7 -v "
        "$(pwd):/app -w /app ubuntu:16.04 ./minecraft-pi'\n");
  }

  return result;
}
