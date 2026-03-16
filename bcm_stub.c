#define _GNU_SOURCE
#include <EGL/egl.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// --- BCM Host Stubs ---
// These satisfy linker dependencies for the Pi specific libraries
void bcm_host_init() {}
void bcm_host_deinit() {}
int graphics_get_display_size(int d, uint32_t *w, uint32_t *h) {
  *w = 640;
  *h = 480;
  return 0;
}
int vc_dispmanx_display_open(int device) { return 1; }
int vc_dispmanx_display_close(int display) { return 0; }
int vc_dispmanx_update_start(int priority) { return 0; }
int vc_dispmanx_update_submit_sync(int update) { return 0; }
int vc_dispmanx_element_remove(int update, int element) { return 0; }

// The game calls this to get a handle for the window. We return a fake '1'.
int vc_dispmanx_element_add(int update, int display, int layer, void *dest_rect,
                            int src, void *src_rect, int protection,
                            void *alpha, void *clamp, int transform) {
  return 1; // Fake Handle
}

// --- EGL Shim ---
// This intercepts the call where the game tries to use that fake handle '1'
// and checks SDL for the *real* X11 window ID to pass to Mesa.

typedef EGLSurface (*REAL_EGL_CREATE_WINDOW_SURFACE_FN)(EGLDisplay, EGLConfig,
                                                        EGLNativeWindowType,
                                                        const EGLint *);

EGLSurface eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config,
                                  EGLNativeWindowType win,
                                  const EGLint *attrib_list) {

  static REAL_EGL_CREATE_WINDOW_SURFACE_FN real_fn = NULL;
  if (!real_fn) {
    real_fn = (REAL_EGL_CREATE_WINDOW_SURFACE_FN)dlsym(
        RTLD_NEXT, "eglCreateWindowSurface");
    if (!real_fn) {
      fprintf(stderr,
              "SHIM_ERROR: Could not find real eglCreateWindowSurface!\n");
      return EGL_NO_SURFACE;
    }
  }

  // Checking if we got the fake handle (1) or valid pointer/ID.
  // Since we are 32-bit, handles are 32-bit.
  // We assume any call to this is likely needing the SDL window if SDL is
  // initialized.

  SDL_SysWMinfo info;
  SDL_VERSION(&info.version);
  // We need to link against SDL but we don't want to init it if the app hasn't.
  // SDL_GetWMInfo returns 1 on success.
  if (SDL_GetWMInfo(&info)) {
    if (info.subsystem == SDL_SYSWM_X11) {
      unsigned long sdl_x11_window = info.info.x11.window;
      if ((uintptr_t)win == 1 || (uintptr_t)win == 0) {
        fprintf(stderr,
                "SHIM: Intercepted eglCreateWindowSurface with fake handle %p. "
                "Swapping with Real SDL X11 Window ID: %lu\n",
                (void *)win, sdl_x11_window);
        win = (EGLNativeWindowType)sdl_x11_window;
      } else {
        // Even if it's not strictly 1, if SDL has a window and we are running
        // this shim, correct implementation implies we likely want that window.
        // But let's be careful.
        fprintf(stderr,
                "SHIM: eglCreateWindowSurface handling valid-looking window? "
                "%p. Forcing SDL window anyway: %lu\n",
                (void *)win, sdl_x11_window);
        win = (EGLNativeWindowType)sdl_x11_window;
      }
    } else {
      fprintf(stderr, "SHIM: SDL Subsystem is NOT X11! (%d)\n", info.subsystem);
    }
  } else {
    const char *err = SDL_GetError();
    if (err && *err) {
      fprintf(stderr,
              "SHIM: Could not get SDL WM Info: %s. Continuing with original "
              "handle.\n",
              err);
    }
  }

  return real_fn(dpy, config, win, attrib_list);
}
