#include "app.h"
#include "config.h"
#include "devmgr.h"
#include "render.h"
#include "keys.h"
#include "shm.h"
#include "theme.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"
#include <assert.h>
#include <cairo/cairo.h>
#include <errno.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#include <librsvg/rsvg.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

static const struct wl_surface_listener wl_surface_listener;
static const struct zwlr_layer_surface_v1_listener layer_surface_listener;

void destroy_layer_surface(struct wsk_state *state) {
  if (state->layer_surface) {
    zwlr_layer_surface_v1_destroy(state->layer_surface);
    state->layer_surface = NULL;
  }
  if (state->surface) {
    wl_surface_destroy(state->surface);
    state->surface = NULL;
  }
  state->output = NULL;
  state->width = 0;
  state->height = 0;
  state->layer_configured = false;
  state->layer_pending_configure = false;
}

bool create_layer_surface(struct wsk_state *state) {
  if (state->surface) {
    return true;
  }

  state->surface = wl_compositor_create_surface(state->compositor);
  if (!state->surface) {
    return false;
  }
  wl_surface_add_listener(state->surface, &wl_surface_listener, state);

  state->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
      state->layer_shell, state->surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_TOP,
      "showkeys");
  if (!state->layer_surface) {
    wl_surface_destroy(state->surface);
    state->surface = NULL;
    return false;
  }
  zwlr_layer_surface_v1_add_listener(state->layer_surface,
                                     &layer_surface_listener, state);
  return true;
}

static void request_layer_configure(struct wsk_state *state) {
  if (state->layer_pending_configure || !state->keys) {
    return;
  }
  if (!create_layer_surface(state)) {
    return;
  }

  zwlr_layer_surface_v1_set_size(state->layer_surface, 1, 1);
  zwlr_layer_surface_v1_set_anchor(state->layer_surface, state->config.anchor);
  zwlr_layer_surface_v1_set_margin(state->layer_surface, state->config.margin,
                                   state->config.margin, state->config.margin,
                                   state->config.margin);
  zwlr_layer_surface_v1_set_exclusive_zone(state->layer_surface, -1);
  wl_surface_commit(state->surface);
  state->layer_pending_configure = true;
}

static void set_dirty(struct wsk_state *state) {
  if (state->frame_scheduled || !state->layer_configured) {
    state->dirty = true;
    if (!state->layer_configured) {
      request_layer_configure(state);
    }
  } else if (state->surface) {
    state->dirty = false;
    wsk_render_frame(state);
  }
}

static void
layer_surface_configure(void *data,
                        struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
                        uint32_t serial, uint32_t width, uint32_t height) {
  struct wsk_state *state = data;
  state->width = width;
  state->height = height;
  state->layer_configured = true;
  state->layer_pending_configure = false;
  zwlr_layer_surface_v1_ack_configure(zwlr_layer_surface_v1, serial);
  set_dirty(state);
}

static void
layer_surface_closed(void *data,
                     struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1) {
  struct wsk_state *state = data;
  state->run = false;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = layer_surface_closed,
};

static void surface_enter(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output) {
  struct wsk_state *state = data;
  struct wsk_output *wsk_output = state->outputs;
  while (wsk_output->output != output) {
    wsk_output = wsk_output->next;
  }
  state->output = wsk_output;
}

static void surface_leave(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output) {
  // Who cares (not really possible with layer shell)
}

static const struct wl_surface_listener wl_surface_listener = {
    .enter = surface_enter,
    .leave = surface_leave,
};

static void keyboard_keymap(void *data, struct wl_keyboard *wl_keyboard,
                            uint32_t format, int32_t fd, uint32_t size) {
  struct wsk_state *state = data;
  char *map_shm = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
  if (map_shm == MAP_FAILED) {
    close(fd);
    fprintf(stderr, "Unable to mmap keymap: %s", strerror(errno));
    return;
  }
  if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
    munmap(map_shm, size);
    close(fd);
    return;
  }

  struct xkb_keymap *keymap = xkb_keymap_new_from_string(
      state->xkb_context, map_shm, XKB_KEYMAP_FORMAT_TEXT_V1,
      XKB_KEYMAP_COMPILE_NO_FLAGS);
  munmap(map_shm, size);
  close(fd);

  struct xkb_state *xkb_state = xkb_state_new(keymap);
  xkb_keymap_unref(state->xkb_keymap);
  xkb_state_unref(state->xkb_state);
  state->xkb_keymap = keymap;
  state->xkb_state = xkb_state;
}

static void keyboard_enter(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface,
                           struct wl_array *keys) {
  // Who cares
}

static void keyboard_leave(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface) {
  // Who cares
}

static void keyboard_key(void *data, struct wl_keyboard *wl_keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state) {
  // Who cares
}

static void keyboard_modifiers(void *data, struct wl_keyboard *wl_keyboard,
                               uint32_t serial, uint32_t mods_depressed,
                               uint32_t mods_latched, uint32_t mods_locked,
                               uint32_t group) {
  // Who cares
}

static void keyboard_repeat_info(void *data, struct wl_keyboard *wl_keyboard,
                                 int32_t rate, int32_t delay) {
  // TODO
}

static const struct wl_keyboard_listener wl_keyboard_listener = {
    .keymap = keyboard_keymap,
    .enter = keyboard_enter,
    .leave = keyboard_leave,
    .key = keyboard_key,
    .modifiers = keyboard_modifiers,
    .repeat_info = keyboard_repeat_info,
};

static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t capabilities) {
  struct wsk_state *state = data;
  if (state->keyboard) {
    // TODO: support multiple seats
    return;
  }

  if (!(capabilities & WL_SEAT_CAPABILITY_KEYBOARD)) {
    fprintf(stderr, "wl_seat does not support keyboard");
    state->run = false;
    return;
  }

  state->keyboard = wl_seat_get_keyboard(wl_seat);
  wl_keyboard_add_listener(state->keyboard, &wl_keyboard_listener, state);
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {
  struct wsk_state *state = data;
  /* TODO: support multiple seats */
  if (libinput_udev_assign_seat(state->libinput, "seat0") != 0) {
    fprintf(stderr, "Failed to assign libinput seat\n");
    state->run = false;
    return;
  }
}

static const struct wl_seat_listener wl_seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};

static void output_geometry(void *data, struct wl_output *wl_output, int32_t x,
                            int32_t y, int32_t physical_width,
                            int32_t physical_height, int32_t subpixel,
                            const char *make, const char *model,
                            int32_t transform) {
  struct wsk_output *output = data;
  output->subpixel = subpixel;
}

static void output_mode(void *data, struct wl_output *wl_output, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh) {
  // Who cares
}

static void output_done(void *data, struct wl_output *wl_output) {
  // Who cares
}

static void output_scale(void *data, struct wl_output *wl_output,
                         int32_t factor) {
  struct wsk_output *output = data;
  output->scale = factor;
}

static const struct wl_output_listener wl_output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
};

static void registry_global(void *data, struct wl_registry *wl_registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
  struct wsk_state *state = data;
  if (strcmp(interface, wl_compositor_interface.name) == 0) {
    state->compositor =
        wl_registry_bind(wl_registry, name, &wl_compositor_interface, 4);
  } else if (strcmp(interface, wl_shm_interface.name) == 0) {
    state->shm = wl_registry_bind(wl_registry, name, &wl_shm_interface, 1);
  } else if (strcmp(interface, wl_seat_interface.name) == 0) {
    state->seat = wl_registry_bind(wl_registry, name, &wl_seat_interface, 5);
  } else if (strcmp(interface, zxdg_output_manager_v1_interface.name) == 0) {
    state->output_mgr = wl_registry_bind(wl_registry, name,
                                         &zxdg_output_manager_v1_interface, 1);
  } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
    state->layer_shell =
        wl_registry_bind(wl_registry, name, &zwlr_layer_shell_v1_interface, 1);
  } else if (strcmp(interface, wl_output_interface.name) == 0) {
    struct wsk_output *output = calloc(1, sizeof(struct wsk_output));
    output->output =
        wl_registry_bind(wl_registry, name, &wl_output_interface, 3);
    output->scale = 1;
    struct wsk_output **link = &state->outputs;
    while (*link) {
      link = &(*link)->next;
    }
    *link = output;
    wl_output_add_listener(output->output, &wl_output_listener, output);
  }
}

static void registry_global_remove(void *data, struct wl_registry *wl_registry,
                                   uint32_t name) {
  /* This space deliberately left blank */
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static const char *pointer_button_name(uint32_t button) {
  switch (button) {
  case BTN_LEFT:
    return "Mouse Left";
  case BTN_RIGHT:
    return "Mouse Right";
  case BTN_MIDDLE:
    return "Mouse Middle";
  case BTN_SIDE:
    return "Mouse Side";
  case BTN_EXTRA:
    return "Mouse Extra";
  case BTN_FORWARD:
    return "Mouse Forward";
  case BTN_BACK:
    return "Mouse Back";
  default:
    return NULL;
  }
}

static void handle_keyboard_key_event(struct wsk_state *state,
                                      struct libinput_event_keyboard *kbevent) {
  if (!state->xkb_state) {
    return;
  }

  uint32_t keycode = libinput_event_keyboard_get_key(kbevent) + 8;
  enum libinput_key_state key_state =
      libinput_event_keyboard_get_key_state(kbevent);
  xkb_state_update_key(state->xkb_state, keycode,
                       key_state == LIBINPUT_KEY_STATE_RELEASED ? XKB_KEY_UP
                                                                : XKB_KEY_DOWN);

  xkb_keysym_t keysym = xkb_state_key_get_one_sym(state->xkb_state, keycode);

  struct wsk_keypress *keypress;
  switch (key_state) {
  case LIBINPUT_KEY_STATE_RELEASED:
    /* Who cares */
    break;
  case LIBINPUT_KEY_STATE_PRESSED:
    keypress = calloc(1, sizeof(struct wsk_keypress));
    assert(keypress);
    keypress->sym = keysym;
    xkb_keysym_get_name(keypress->sym, keypress->name, sizeof(keypress->name));
    if (xkb_state_key_get_utf8(state->xkb_state, keycode, keypress->utf8,
                               sizeof(keypress->utf8)) <= 0 ||
        keypress->utf8[0] <= ' ') {
      keypress->utf8[0] = '\0';
    }
    wsk_keys_append(&state->keys, keypress, state->config.max_keys);
    clock_gettime(CLOCK_MONOTONIC, &state->last_key);
    set_dirty(state);
    break;
  }
}

static void handle_pointer_button_event(struct wsk_state *state,
                                        struct libinput_event_pointer *pevent) {
  enum libinput_button_state button_state =
      libinput_event_pointer_get_button_state(pevent);
  if (button_state != LIBINPUT_BUTTON_STATE_PRESSED) {
    return;
  }

  uint32_t button = libinput_event_pointer_get_button(pevent);
  struct wsk_keypress *keypress = calloc(1, sizeof(struct wsk_keypress));
  assert(keypress);
  keypress->sym = XKB_KEY_NoSymbol;
  keypress->utf8[0] = '\0';

  const char *name = pointer_button_name(button);
  if (name) {
    snprintf(keypress->name, sizeof(keypress->name), "%s", name);
  } else {
    snprintf(keypress->name, sizeof(keypress->name), "Mouse 0x%x", button);
  }

  wsk_keys_append(&state->keys, keypress, state->config.max_keys);
  clock_gettime(CLOCK_MONOTONIC, &state->last_key);
  set_dirty(state);
}

static void handle_libinput_event(struct wsk_state *state,
                                  struct libinput_event *event) {
  enum libinput_event_type event_type = libinput_event_get_type(event);
  switch (event_type) {
  case LIBINPUT_EVENT_KEYBOARD_KEY:
    handle_keyboard_key_event(state, libinput_event_get_keyboard_event(event));
    break;
  case LIBINPUT_EVENT_POINTER_BUTTON:
    handle_pointer_button_event(state, libinput_event_get_pointer_event(event));
    break;
  default:
    break;
  }
}

static int libinput_open_restricted(const char *path, int flags, void *data) {
  int *fd = data;
  return devmgr_open(*fd, path);
}

static void libinput_close_restricted(int fd, void *data) { close(fd); }

static const struct libinput_interface libinput_impl = {
    .open_restricted = libinput_open_restricted,
    .close_restricted = libinput_close_restricted,
};

int main(int argc, char *argv[]) {
  /* NOTICE: This code runs as root */
  struct wsk_state state = {0};
  if (devmgr_start(&state.devmgr, &state.devmgr_pid, INPUTDEVPATH) > 0) {
    return 1;
  }

  /* Begin normal user code: */
  int ret = 0;

  wsk_config_init_defaults(&state.config);
  if (!wsk_config_parse(&state.config, argc, argv)) {
    ret = 1;
    goto exit;
  }
  if (state.config.exit_after_parse) {
    ret = state.config.exit_code;
    goto exit;
  }

  if (state.config.key_svg_path) {
    state.icon_dir = wsk_path_dirname(state.config.key_svg_path);
    if (!state.icon_dir) {
      fprintf(stderr, "Unable to allocate icon directory path\n");
    }

    GError *error = NULL;
    state.key_svg = rsvg_handle_new_from_file(state.config.key_svg_path, &error);
    if (!state.key_svg) {
      fprintf(stderr, "Unable to load key SVG '%s': %s\n", state.config.key_svg_path,
              error ? error->message : "unknown error");
      if (error) {
        g_error_free(error);
      }
      state.key_svg_failed = true;
    }
  }

  state.udev = udev_new();
  if (!state.udev) {
    fprintf(stderr, "udev_create: %s\n", strerror(errno));
    ret = 1;
    goto exit;
  }

  state.libinput =
      libinput_udev_create_context(&libinput_impl, &state.devmgr, state.udev);
  udev_unref(state.udev);
  if (!state.libinput) {
    fprintf(stderr, "libinput_udev_create_context: %s\n", strerror(errno));
    ret = 1;
    goto exit;
  }

  state.xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (!state.xkb_context) {
    fprintf(stderr, "xkb_context_new: %s\n", strerror(errno));
    ret = 1;
    goto exit;
  }

  state.display = wl_display_connect(NULL);
  if (!state.display) {
    fprintf(stderr, "wl_display_connect: %s\n", strerror(errno));
    ret = 1;
    goto exit;
  }

  state.registry = wl_display_get_registry(state.display);
  assert(state.registry);
  wl_registry_add_listener(state.registry, &registry_listener, &state);
  wl_display_roundtrip(state.display);

  struct {
    const char *name;
    void *ptr;
  } need_globals[] = {
      "wl_compositor", &state.compositor, "wl_shm",          &state.shm,
      "wl_seat",       &state.seat,       "wlr_layer_shell", &state.layer_shell,
  };
  for (size_t i = 0; i < sizeof(need_globals) / sizeof(need_globals[0]); ++i) {
    if (!need_globals[i].ptr) {
      fprintf(stderr,
              "Error: required Wayland interface '%s' "
              "is not present\n",
              need_globals[i].name);
      ret = 1;
      goto exit;
    }
  }

  // TODO: Listener for xdg output

  wl_seat_add_listener(state.seat, &wl_seat_listener, &state);
  wl_display_roundtrip(state.display);

  struct pollfd pollfds[] = {
      {
          .fd = libinput_get_fd(state.libinput),
          .events = POLLIN,
      },
      {
          .fd = wl_display_get_fd(state.display),
          .events = POLLIN,
      },
  };

  state.run = true;
  while (state.run) {
    errno = 0;
    do {
      if (wl_display_flush(state.display) == -1 && errno != EAGAIN) {
        fprintf(stderr, "wl_display_flush: %s\n", strerror(errno));
        break;
      }
    } while (errno == EAGAIN);

    int timeout = -1;
    if (state.keys) {
      timeout = 100;
    }

    if (poll(pollfds, sizeof(pollfds) / sizeof(pollfds[0]), timeout) < 0) {
      fprintf(stderr, "poll: %s\n", strerror(errno));
      break;
    }

    /* Clear out old keys */
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (wsk_keys_expired(state.keys, state.last_key, state.config.timeout, now)) {
      wsk_keys_clear(&state.keys);
      set_dirty(&state);
    }

    if ((pollfds[0].revents & POLLIN)) {
      if (libinput_dispatch(state.libinput) != 0) {
        fprintf(stderr, "libinput_dispatch: %s\n", strerror(errno));
        break;
      }
      struct libinput_event *event;
      while ((event = libinput_get_event(state.libinput))) {
        handle_libinput_event(&state, event);
        libinput_event_destroy(event);
      }
    }

    if ((pollfds[1].revents & POLLIN) &&
        wl_display_dispatch(state.display) == -1) {
      fprintf(stderr, "wl_display_dispatch: %s\n", strerror(errno));
      break;
    }
  }

exit:
  wsk_icon_cache_finish(&state.icons);
  free(state.icon_dir);
  if (state.key_svg) {
    g_object_unref(state.key_svg);
  }
  wl_display_disconnect(state.display);
  libinput_unref(state.libinput);
  devmgr_finish(state.devmgr, state.devmgr_pid);
  return ret;
}
