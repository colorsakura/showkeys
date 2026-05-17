#ifndef SHOWKEYS_APP_H
#define SHOWKEYS_APP_H

#include "config.h"
#include "icons.h"
#include "keys.h"
#include "shm.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"
#include <libinput.h>
#include <libudev.h>
#include <librsvg/rsvg.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

struct wsk_output {
  struct wl_output *output;
  int scale;
  enum wl_output_subpixel subpixel;
  struct wsk_output *next;
};

struct wsk_state {
  int devmgr;
  pid_t devmgr_pid;
  struct udev *udev;
  struct libinput *libinput;

  struct wsk_config config;
  char *icon_dir;
  RsvgHandle *key_svg;
  bool key_svg_failed;
  struct wsk_icon_cache icons;

  struct wl_display *display;
  struct wl_registry *registry;
  struct wl_compositor *compositor;
  struct wl_shm *shm;
  struct wl_seat *seat;
  struct wl_keyboard *keyboard;
  struct zxdg_output_manager_v1 *output_mgr;
  struct zwlr_layer_shell_v1 *layer_shell;

  struct wl_surface *surface;
  struct zwlr_layer_surface_v1 *layer_surface;
  uint32_t width, height;
  bool layer_configured, layer_pending_configure, frame_scheduled, dirty;
  struct pool_buffer buffers[2];
  struct pool_buffer *current_buffer;
  struct wsk_output *output, *outputs;

  struct xkb_state *xkb_state;
  struct xkb_context *xkb_context;
  struct xkb_keymap *xkb_keymap;

  struct wsk_keypress *keys;
  struct timespec last_key;

  bool run;
};

#endif
