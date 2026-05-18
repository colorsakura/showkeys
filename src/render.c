#include "app.h"
#include "render.h"

#include "keycap.h"
#include "wayland.h"
#include "shm.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#include <cairo/cairo.h>
#include <wayland-client.h>

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

void wsk_render_frame(struct wsk_app *app) {
    struct wsk_wayland *wl = &app->wayland;
    cairo_surface_t *recorder =
            cairo_recording_surface_create(CAIRO_CONTENT_COLOR_ALPHA, NULL);
    cairo_t *cairo = cairo_create(recorder);
    cairo_set_antialias(cairo, CAIRO_ANTIALIAS_BEST);
    cairo_font_options_t *fo = cairo_font_options_create();
    cairo_font_options_set_hint_style(fo, CAIRO_HINT_STYLE_FULL);
    cairo_font_options_set_antialias(fo, CAIRO_ANTIALIAS_SUBPIXEL);
    if (wl->output) {
        cairo_font_options_set_subpixel_order(
            fo, to_cairo_subpixel_order(wl->output->subpixel));
    }
    cairo_set_font_options(cairo, fo);
    cairo_font_options_destroy(fo);
    cairo_save(cairo);
    cairo_set_operator(cairo, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cairo);
    cairo_restore(cairo);

    int scale = wl->output ? wl->output->scale : 1;
    uint32_t width = 0, height = 0;
    wsk_render_keycaps_to_cairo(cairo, app->keys.head, &app->config,
                                &app->theme, scale, &width, &height);
    if (height / scale != wl->height || width / scale != wl->width ||
        wl->width == 0) {
        // Reconfigure surface
        if (width == 0 || height == 0) {
            wsk_wayland_destroy_layer_surface(wl);
        } else {
            zwlr_layer_surface_v1_set_size(wl->layer_surface, width / scale,
                                           height / scale);
        }

        // TODO: this could infinite loop if the compositor assigns us a
        // different height than what we asked for
        if (wl->surface) {
            wl_surface_commit(wl->surface);
        }
    } else if (height > 0) {
        // Replay recording into shm and send it off
        wl->current_buffer =
                get_next_buffer(wl->shm, wl->buffers, wl->width * scale,
                                wl->height * scale);
        if (!wl->current_buffer) {
            cairo_surface_destroy(recorder);
            cairo_destroy(cairo);
            return;
        }
        cairo_t *shm = wl->current_buffer->cairo;

        cairo_save(shm);
        cairo_set_operator(shm, CAIRO_OPERATOR_CLEAR);
        cairo_paint(shm);
        cairo_restore(shm);

        cairo_set_source_surface(shm, recorder, 0.0, 0.0);
        cairo_paint(shm);

        wl_surface_set_buffer_scale(wl->surface, scale);
        wl_surface_attach(wl->surface, wl->current_buffer->buffer, 0, 0);
        wl_surface_damage_buffer(wl->surface, 0, 0, wl->width * scale,
                                 wl->height * scale);

        // Register frame callback BEFORE commit to throttle rendering
        wl->frame_callback = wl_surface_frame(wl->surface);
        wl_callback_add_listener(wl->frame_callback,
                                 &frame_listener, app);
        wl->frame_scheduled = true;

        wl_surface_commit(wl->surface);
    }
}

