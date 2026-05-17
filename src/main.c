#include "devmgr.h"
#include "pango.h"
#include "shm.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"
#include <assert.h>
#include <cairo/cairo.h>
#include <errno.h>
#include <getopt.h>
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

struct wsk_keypress {
  xkb_keysym_t sym;
  char name[128];
  char utf8[128];
  struct wsk_keypress *next;
};

struct wsk_output {
  struct wl_output *output;
  int scale;
  enum wl_output_subpixel subpixel;
  struct wsk_output *next;
};

struct keycap_style {
  int padding_x;
  int padding_y;
  int gap;
  int radius;
  int border_width;
  int icon_size;
  uint32_t normal_bg;
  uint32_t normal_fg;
  uint32_t special_bg;
  uint32_t special_fg;
  uint32_t border;
};

struct icon_cache_entry {
  char *icon_name;
  RsvgHandle *svg;
  bool failed;
  struct icon_cache_entry *next;
};

struct keycap_layout {
  const struct wsk_keypress *key;
  const char *label;
  bool special;
  const char *icon_name;
  RsvgHandle *icon_svg;
  int text_width;
  int text_height;
  int text_baseline;
  int x;
  int y;
  int width;
  int height;
  int icon_x;
  int icon_y;
  int text_x;
  int text_y;
};

struct wsk_state {
  int devmgr;
  pid_t devmgr_pid;
  struct udev *udev;
  struct libinput *libinput;

  uint32_t foreground, background, specialfg;
  const char *font;
  int timeout;
  int max_keys;
  const char *key_svg_path;
  char *icon_dir;
  RsvgHandle *key_svg;
  bool key_svg_failed;
  struct icon_cache_entry *icons;

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
  uint32_t anchor;
  int margin;
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

static void cairo_set_source_u32(cairo_t *cairo, uint32_t color) {
  cairo_set_source_rgba(cairo, (color >> (3 * 8) & 0xFF) / 255.0,
                        (color >> (2 * 8) & 0xFF) / 255.0,
                        (color >> (1 * 8) & 0xFF) / 255.0,
                        (color >> (0 * 8) & 0xFF) / 255.0);
}

static void rounded_rectangle(cairo_t *cairo, double x, double y, double w,
                              double h, double r) {
  if (r > w / 2.0) {
    r = w / 2.0;
  }
  if (r > h / 2.0) {
    r = h / 2.0;
  }

  cairo_new_sub_path(cairo);
  cairo_arc(cairo, x + w - r, y + r, r, -1.5707963267948966, 0.0);
  cairo_arc(cairo, x + w - r, y + h - r, r, 0.0, 1.5707963267948966);
  cairo_arc(cairo, x + r, y + h - r, r, 1.5707963267948966,
            3.141592653589793);
  cairo_arc(cairo, x + r, y + r, r, 3.141592653589793,
            4.71238898038469);
  cairo_close_path(cairo);
}

static char *xstrdup(const char *str) {
  size_t len = strlen(str) + 1;
  char *copy = malloc(len);
  if (copy) {
    memcpy(copy, str, len);
  }
  return copy;
}

static char *path_dirname(const char *path) {
  const char *slash = strrchr(path, '/');
  if (!slash) {
    return xstrdup(".");
  }
  if (slash == path) {
    return xstrdup("/");
  }

  size_t len = (size_t)(slash - path);
  char *dir = malloc(len + 1);
  if (!dir) {
    return NULL;
  }
  memcpy(dir, path, len);
  dir[len] = '\0';
  return dir;
}

static char *join_path3(const char *dir, const char *subdir, const char *file) {
  const char *sep1 = (dir[0] && dir[strlen(dir) - 1] == '/') ? "" : "/";
  const char *sep2 = (subdir[0] && subdir[strlen(subdir) - 1] == '/') ? "" : "/";
  size_t len = strlen(dir) + strlen(sep1) + strlen(subdir) + strlen(sep2) +
               strlen(file) + 1;
  char *path = malloc(len);
  if (!path) {
    return NULL;
  }
  snprintf(path, len, "%s%s%s%s%s", dir, sep1, subdir, sep2, file);
  return path;
}

static const char *special_icon_name(const char *key_name) {
  static const struct {
    const char *key_name;
    const char *icon_name;
  } icon_map[] = {
      {"Escape", "escape.svg"},
      {"Tab", "tab.svg"},
      {"ISO_Left_Tab", "tab.svg"},
      {"Enter", "enter.svg"},
      {"Return", "enter.svg"},
      {"KP_Enter", "enter.svg"},
      {"BackSpace", "backspace.svg"},
      {"Delete", "delete.svg"},
      {"KP_Delete", "delete.svg"},
      {"Insert", "insert.svg"},
      {"KP_Insert", "insert.svg"},
      {"Home", "home.svg"},
      {"KP_Home", "home.svg"},
      {"End", "end.svg"},
      {"KP_End", "end.svg"},
      {"Page_Up", "page-up.svg"},
      {"KP_Page_Up", "page-up.svg"},
      {"Page_Down", "page-down.svg"},
      {"KP_Page_Down", "page-down.svg"},
      {"Caps_Lock", "caps-lock.svg"},
      {"Num_Lock", "num-lock.svg"},
      {"Scroll_Lock", "scroll-lock.svg"},
      {"Pause", "pause.svg"},
      {"Break", "pause.svg"},
      {"Print", "print-screen.svg"},
      {"Sys_Req", "print-screen.svg"},
      {"Menu", "menu.svg"},
      {"XF86MenuKB", "menu.svg"},
      {"space", "space.svg"},
      {"KP_Space", "space.svg"},
      {"Shift_L", "shift.svg"},
      {"Shift_R", "shift.svg"},
      {"Control_L", "ctrl.svg"},
      {"Control_R", "ctrl.svg"},
      {"Alt_L", "alt.svg"},
      {"Alt_R", "alt.svg"},
      {"Meta_L", "alt.svg"},
      {"Meta_R", "alt.svg"},
      {"Super_L", "super.svg"},
      {"Super_R", "super.svg"},
      {"Hyper_L", "super.svg"},
      {"Hyper_R", "super.svg"},
      {"Left", "arrow-left.svg"},
      {"KP_Left", "arrow-left.svg"},
      {"Right", "arrow-right.svg"},
      {"KP_Right", "arrow-right.svg"},
      {"Up", "arrow-up.svg"},
      {"KP_Up", "arrow-up.svg"},
      {"Down", "arrow-down.svg"},
      {"KP_Down", "arrow-down.svg"},
      {"KP_Begin", "keypad.svg"},
      {"KP_Add", "keypad.svg"},
      {"KP_Subtract", "keypad.svg"},
      {"KP_Multiply", "keypad.svg"},
      {"KP_Divide", "keypad.svg"},
      {"XF86AudioPlay", "media-play.svg"},
      {"XF86AudioPause", "pause.svg"},
      {"XF86AudioStop", "media-stop.svg"},
      {"XF86AudioPrev", "media-prev.svg"},
      {"XF86AudioNext", "media-next.svg"},
      {"XF86AudioRaiseVolume", "volume-up.svg"},
      {"XF86AudioLowerVolume", "volume-down.svg"},
      {"XF86AudioMute", "volume-mute.svg"},
      {"XF86MonBrightnessUp", "brightness.svg"},
      {"XF86MonBrightnessDown", "brightness.svg"},
      {"XF86KbdBrightnessUp", "brightness.svg"},
      {"XF86KbdBrightnessDown", "brightness.svg"},
      {"XF86Fn", "fn.svg"},
      {"XF86Fn_Esc", "fn.svg"},
      {"Mouse Left", "mouse-left.svg"},
      {"Mouse Right", "mouse-right.svg"},
      {"Mouse Middle", "mouse-middle.svg"},
      {"Mouse Side", "mouse-side.svg"},
      {"Mouse Extra", "mouse-extra.svg"},
      {"Mouse Forward", "mouse-forward.svg"},
      {"Mouse Back", "mouse-back.svg"},
  };

  for (size_t i = 0; i < sizeof(icon_map) / sizeof(icon_map[0]); ++i) {
    if (strcmp(key_name, icon_map[i].key_name) == 0) {
      return icon_map[i].icon_name;
    }
  }
  return NULL;
}

static RsvgHandle *get_icon_svg(struct wsk_state *state, const char *icon_name) {
  if (!state->icon_dir || !icon_name) {
    return NULL;
  }

  for (struct icon_cache_entry *entry = state->icons; entry;
       entry = entry->next) {
    if (strcmp(entry->icon_name, icon_name) == 0) {
      return entry->failed ? NULL : entry->svg;
    }
  }

  struct icon_cache_entry *entry = calloc(1, sizeof(*entry));
  if (!entry) {
    return NULL;
  }
  entry->icon_name = xstrdup(icon_name);
  if (!entry->icon_name) {
    free(entry);
    return NULL;
  }

  char *path = join_path3(state->icon_dir, "icons", icon_name);
  if (!path) {
    entry->failed = true;
  } else {
    GError *error = NULL;
    entry->svg = rsvg_handle_new_from_file(path, &error);
    if (!entry->svg) {
      entry->failed = true;
      if (error) {
        g_error_free(error);
      }
    }
    free(path);
  }

  entry->next = state->icons;
  state->icons = entry;
  return entry->failed ? NULL : entry->svg;
}

static void free_icon_cache(struct icon_cache_entry *icons) {
  while (icons) {
    struct icon_cache_entry *next = icons->next;
    if (icons->svg) {
      g_object_unref(icons->svg);
    }
    free(icons->icon_name);
    free(icons);
    icons = next;
  }
}

static void draw_cairo_keycap(cairo_t *cairo, const struct keycap_layout *layout,
                              const struct keycap_style *style, int radius,
                              int border_width) {
  rounded_rectangle(cairo, layout->x, layout->y, layout->width, layout->height,
                    radius);
  cairo_set_source_u32(cairo, layout->special ? style->special_bg
                                              : style->normal_bg);
  cairo_fill_preserve(cairo);

  if (border_width > 0) {
    cairo_set_line_width(cairo, border_width);
    cairo_set_source_u32(cairo, style->border);
    cairo_stroke(cairo);
  } else {
    cairo_new_path(cairo);
  }
}

static bool draw_svg_to_rect(cairo_t *cairo, RsvgHandle *svg, double x,
                             double y, double width, double height,
                             const char *description) {
  RsvgRectangle viewport = {
      .x = x,
      .y = y,
      .width = width,
      .height = height,
  };
  GError *error = NULL;
  gboolean ok = rsvg_handle_render_document(svg, cairo, &viewport, &error);
  if (!ok) {
    if (error) {
      fprintf(stderr, "Unable to render %s SVG: %s\n", description,
              error->message);
      g_error_free(error);
    } else {
      fprintf(stderr, "Unable to render %s SVG\n", description);
    }
    return false;
  }
  return true;
}

static bool draw_svg_keycap(cairo_t *cairo, RsvgHandle *svg,
                            const struct keycap_layout *layout) {
  return draw_svg_to_rect(cairo, svg, layout->x, layout->y, layout->width,
                          layout->height, "key");
}

static bool draw_svg_icon(cairo_t *cairo, RsvgHandle *svg,
                          const struct keycap_layout *layout,
                          int icon_size) {
  return draw_svg_to_rect(cairo, svg, layout->icon_x, layout->icon_y, icon_size,
                          icon_size, "icon");
}

static cairo_subpixel_order_t
to_cairo_subpixel_order(enum wl_output_subpixel subpixel) {
  switch (subpixel) {
  case WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB:
    return CAIRO_SUBPIXEL_ORDER_RGB;
  case WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR:
    return CAIRO_SUBPIXEL_ORDER_BGR;
  case WL_OUTPUT_SUBPIXEL_VERTICAL_RGB:
    return CAIRO_SUBPIXEL_ORDER_VRGB;
  case WL_OUTPUT_SUBPIXEL_VERTICAL_BGR:
    return CAIRO_SUBPIXEL_ORDER_VBGR;
  default:
    return CAIRO_SUBPIXEL_ORDER_DEFAULT;
  }
  return CAIRO_SUBPIXEL_ORDER_DEFAULT;
}

static void render_to_cairo(cairo_t *cairo, struct wsk_state *state, int scale,
                            uint32_t *width, uint32_t *height) {
  const struct keycap_style style = {
      .padding_x = 12,
      .padding_y = 6,
      .gap = 6,
      .radius = 8,
      .border_width = 1,
      .icon_size = 20,
      .normal_bg = 0x222222CC,
      .normal_fg = state->foreground,
      .special_bg = 0x444444CC,
      .special_fg = state->specialfg,
      .border = 0xFFFFFF33,
  };

  cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_u32(cairo, state->background);
  cairo_paint(cairo);
  cairo_set_operator(cairo, CAIRO_OPERATOR_OVER);

  size_t key_count = 0;
  for (const struct wsk_keypress *key = state->keys; key; key = key->next) {
    ++key_count;
  }
  if (key_count == 0) {
    return;
  }

  struct keycap_layout *layouts = calloc(key_count, sizeof(*layouts));
  if (!layouts) {
    return;
  }

  const int padding_x = style.padding_x * scale;
  const int padding_y = style.padding_y * scale;
  const int gap = style.gap * scale;
  const int radius = style.radius * scale;
  const int border_width = style.border_width * scale;
  const int icon_size = style.icon_size * scale;

  int text_min_width = 0;
  int text_min_height = 0;
  int text_min_baseline = 0;
  get_text_size(cairo, state->font, &text_min_width, &text_min_height,
                &text_min_baseline, scale, "M");

  const int min_content_width =
      icon_size > text_min_width ? icon_size : text_min_width;
  const int min_content_height =
      icon_size > text_min_height ? icon_size : text_min_height;

  size_t i = 0;
  int max_width = 0;
  int max_height = 0;
  for (const struct wsk_keypress *key = state->keys; key; key = key->next) {
    struct keycap_layout *layout = &layouts[i++];
    layout->key = key;
    layout->special = key->utf8[0] == '\0';
    layout->label = layout->special ? key->name : key->utf8;
    layout->icon_name = layout->special ? special_icon_name(key->name) : NULL;
    layout->icon_svg = get_icon_svg(state, layout->icon_name);
    get_text_size(cairo, state->font, &layout->text_width,
                  &layout->text_height, &layout->text_baseline, scale, "%s",
                  layout->label);
    int content_width = layout->icon_svg ? icon_size : layout->text_width;
    int content_height = layout->icon_svg ? icon_size : layout->text_height;
    if (content_width < min_content_width) {
      content_width = min_content_width;
    }
    if (content_height < min_content_height) {
      content_height = min_content_height;
    }
    layout->width = content_width + padding_x * 2;
    layout->height = content_height + padding_y * 2;
    if (max_width < layout->width) {
      max_width = layout->width;
    }
    if (max_height < layout->height) {
      max_height = layout->height;
    }
  }

  int popup_height = max_height;
  for (i = 0; i < key_count; ++i) {
    struct keycap_layout *layout = &layouts[i];
    if ((layout->icon_svg || !layout->special) && layout->width > popup_height) {
      popup_height = layout->width;
    }
  }

  size_t total_width = 0;
  for (i = 0; i < key_count; ++i) {
    struct keycap_layout *layout = &layouts[i];
    layout->height = popup_height;
    if (layout->icon_svg || !layout->special) {
      layout->width = popup_height;
    } else {
      layout->width = max_width;
    }
    total_width += (size_t)layout->width;
  }

  *width = (uint32_t)(total_width + (key_count - 1) * (size_t)gap);
  *height = popup_height;

  int x = 0;
  for (i = 0; i < key_count; ++i) {
    struct keycap_layout *layout = &layouts[i];
    layout->x = x;
    layout->y = 0;
    x += layout->width + gap;

    if (!state->key_svg || state->key_svg_failed ||
        !draw_svg_keycap(cairo, state->key_svg, layout)) {
      if (state->key_svg && !state->key_svg_failed) {
        fprintf(stderr, "Falling back to Cairo keycap background\n");
        state->key_svg_failed = true;
      }
      draw_cairo_keycap(cairo, layout, &style, radius, border_width);
    }

    if (layout->icon_svg) {
      layout->icon_x = layout->x + (layout->width - icon_size) / 2;
      layout->icon_y = layout->y + (layout->height - icon_size) / 2;
      draw_svg_icon(cairo, layout->icon_svg, layout, icon_size);
      continue;
    }

    layout->text_x = layout->x + (layout->width - layout->text_width) / 2;
    layout->text_y = layout->y + (layout->height - layout->text_height) / 2;
    cairo_set_source_u32(cairo,
                         layout->special ? style.special_fg : style.normal_fg);
    cairo_move_to(cairo, layout->text_x, layout->text_y);
    pango_printf(cairo, state->font, scale, "%s", layout->label);
  }

  free(layouts);
}

static const struct wl_surface_listener wl_surface_listener;
static const struct zwlr_layer_surface_v1_listener layer_surface_listener;

static void destroy_layer_surface(struct wsk_state *state) {
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

static bool create_layer_surface(struct wsk_state *state) {
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

static void render_frame(struct wsk_state *state) {
  cairo_surface_t *recorder =
      cairo_recording_surface_create(CAIRO_CONTENT_COLOR_ALPHA, NULL);
  cairo_t *cairo = cairo_create(recorder);
  cairo_set_antialias(cairo, CAIRO_ANTIALIAS_BEST);
  cairo_font_options_t *fo = cairo_font_options_create();
  cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_FULL);
  cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_SUBPIXEL);
  if (state->output) {
    cairo_font_options_set_subpixel_order(
        fo, to_cairo_subpixel_order(state->output->subpixel));
  }
  cairo_set_font_options(cairo, fo);
  cairo_font_options_destroy(fo);
  cairo_save(cairo);
  cairo_set_operator(cairo, CAIRO_OPERATOR_CLEAR);
  cairo_paint(cairo);
  cairo_restore(cairo);

  int scale = state->output ? state->output->scale : 1;
  uint32_t width = 0, height = 0;
  render_to_cairo(cairo, state, scale, &width, &height);
  if (height / scale != state->height || width / scale != state->width ||
      state->width == 0) {
    // Reconfigure surface
    if (width == 0 || height == 0) {
      destroy_layer_surface(state);
    } else {
      zwlr_layer_surface_v1_set_size(state->layer_surface, width / scale,
                                     height / scale);
    }

    // TODO: this could infinite loop if the compositor assigns us a
    // different height than what we asked for
    if (state->surface) {
      wl_surface_commit(state->surface);
    }
  } else if (height > 0) {
    // Replay recording into shm and send it off
    state->current_buffer =
        get_next_buffer(state->shm, state->buffers, state->width * scale,
                        state->height * scale);
    if (!state->current_buffer) {
      cairo_surface_destroy(recorder);
      cairo_destroy(cairo);
      return;
    }
    cairo_t *shm = state->current_buffer->cairo;

    cairo_save(shm);
    cairo_set_operator(shm, CAIRO_OPERATOR_CLEAR);
    cairo_paint(shm);
    cairo_restore(shm);

    cairo_set_source_surface(shm, recorder, 0.0, 0.0);
    cairo_paint(shm);

    wl_surface_set_buffer_scale(state->surface, scale);
    wl_surface_attach(state->surface, state->current_buffer->buffer, 0, 0);
    wl_surface_damage_buffer(state->surface, 0, 0, state->width * scale,
                             state->height * scale);
    wl_surface_commit(state->surface);
  }
}

static void request_layer_configure(struct wsk_state *state) {
  if (state->layer_pending_configure || !state->keys) {
    return;
  }
  if (!create_layer_surface(state)) {
    return;
  }

  zwlr_layer_surface_v1_set_size(state->layer_surface, 1, 1);
  zwlr_layer_surface_v1_set_anchor(state->layer_surface, state->anchor);
  zwlr_layer_surface_v1_set_margin(state->layer_surface, state->margin,
                                   state->margin, state->margin,
                                   state->margin);
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
    render_frame(state);
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

static void append_keypress(struct wsk_state *state,
                            struct wsk_keypress *keypress) {
  struct wsk_keypress **link = &state->keys;
  size_t key_count = 0;
  while (*link) {
    link = &(*link)->next;
    ++key_count;
  }
  *link = keypress;
  ++key_count;

  while ((int)key_count > state->max_keys && state->keys) {
    struct wsk_keypress *oldest = state->keys;
    state->keys = oldest->next;
    free(oldest);
    --key_count;
  }
}

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
    append_keypress(state, keypress);
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

  append_keypress(state, keypress);
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

static uint32_t parse_color(const char *color) {
  if (color[0] == '#') {
    ++color;
  }

  int len = strlen(color);
  if (len != 6 && len != 8) {
    fprintf(stderr,
            "Invalid color %s, defaulting to color "
            "0xFFFFFFFF\n",
            color);
    return 0xFFFFFFFF;
  }
  uint32_t res = (uint32_t)strtoul(color, NULL, 16);
  if (strlen(color) == 6) {
    res = (res << 8) | 0xFF;
  }
  return res;
}

int main(int argc, char *argv[]) {
  /* NOTICE: This code runs as root */
  struct wsk_state state = {0};
  if (devmgr_start(&state.devmgr, &state.devmgr_pid, INPUTDEVPATH) > 0) {
    return 1;
  }

  /* Begin normal user code: */
  int ret = 0;

  state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                 ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
  state.margin = 32;
  state.background = 0x00000000;
  state.specialfg = 0xAAAAAAFF;
  state.foreground = 0xFFFFFFFF;
  state.font = "monospace 24";
  state.timeout = 1;
  state.max_keys = 5;

  int c;
  while ((c = getopt(argc, argv, "hb:f:s:F:t:n:a:m:o:k:")) != -1) {
    switch (c) {
    case 'b':
      state.background = parse_color(optarg);
      break;
    case 'f':
      state.foreground = parse_color(optarg);
      break;
    case 's':
      state.specialfg = parse_color(optarg);
      break;
    case 'F':
      state.font = optarg;
      break;
    case 't':
      state.timeout = atoi(optarg);
      break;
    case 'n':
      state.max_keys = atoi(optarg);
      if (state.max_keys < 1) {
        fprintf(stderr, "Invalid max key count '%s'\n", optarg);
        return 1;
      }
      break;
    case 'a':
      if (strcmp(optarg, "top-right") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                       ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
      } else if (strcmp(optarg, "top-center") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
      } else if (strcmp(optarg, "top-left") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                       ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
      } else if (strcmp(optarg, "bottom-right") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                       ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
      } else if (strcmp(optarg, "bottom-center") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
      } else if (strcmp(optarg, "bottom-left") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                       ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
      } else if (strcmp(optarg, "center-right") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
      } else if (strcmp(optarg, "center-left") == 0) {
        state.anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
      } else if (strcmp(optarg, "center") == 0) {
        state.anchor = 0;
      } else {
        fprintf(stderr, "Invalid anchor value '%s'\n", optarg);
      }
      break;
    case 'm':
      state.margin = atoi(optarg);
      break;
    case 'o':
      fprintf(stderr, "-o is unimplemented\n");
      return 0;
    case 'k':
      state.key_svg_path = optarg;
      break;
    default:
      fprintf(stderr, "usage: wshowkeys [-b|-f|-s #RRGGBB[AA]] [-F font] "
                      "[-t timeout] [-n max-keys]\n\t"
                      "[-a top|left|right|bottom] [-m margin] "
                      "[-o output] [-k key.svg]\n");
      return 1;
    }
  }

  if (state.key_svg_path) {
    state.icon_dir = path_dirname(state.key_svg_path);
    if (!state.icon_dir) {
      fprintf(stderr, "Unable to allocate icon directory path\n");
    }

    GError *error = NULL;
    state.key_svg = rsvg_handle_new_from_file(state.key_svg_path, &error);
    if (!state.key_svg) {
      fprintf(stderr, "Unable to load key SVG '%s': %s\n", state.key_svg_path,
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
    if (now.tv_sec > state.last_key.tv_sec + state.timeout ||
        (now.tv_sec == state.last_key.tv_sec + state.timeout &&
         now.tv_nsec >= state.last_key.tv_nsec)) {
      struct wsk_keypress *key = state.keys;
      while (key) {
        struct wsk_keypress *next = key->next;
        free(key);
        key = next;
      }
      state.keys = NULL;
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
  free_icon_cache(state.icons);
  free(state.icon_dir);
  if (state.key_svg) {
    g_object_unref(state.key_svg);
  }
  wl_display_disconnect(state.display);
  libinput_unref(state.libinput);
  devmgr_finish(state.devmgr, state.devmgr_pid);
  return ret;
}
