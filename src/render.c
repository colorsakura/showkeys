#include "render.h"

#include "keycap.h"
#include "wayland.h"

#include <cairo/cairo.h>

cairo_subpixel_order_t
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

void wsk_render_frame(struct wsk_state *state) {
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
  wsk_render_keycaps_to_cairo(cairo, state->keys, &state->config, &state->icons,
                              state->icon_dir, state->key_svg,
                              &state->key_svg_failed, scale, &width,
                              &height);
  if (height / scale != state->height || width / scale != state->width ||
      state->width == 0) {
    // Reconfigure surface
    if (width == 0 || height == 0) {
      wsk_wayland_destroy_layer_surface(state);
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

