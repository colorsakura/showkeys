#ifndef SHOWKEYS_KEYCAP_H
#define SHOWKEYS_KEYCAP_H

#include "config.h"
#include "icons.h"
#include "keys.h"

#include "theme.h"
#include <cairo/cairo.h>
#include <librsvg/rsvg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

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

/*
 * Measure keycaps layout without drawing. cairo is used only for text
 * measurement and must have font options configured. Returns the number of
 * keys, or 0 on empty/error. Sets *width and *height to the required
 * surface dimensions. Caller must free *out_layouts with free().
 */
size_t wsk_measure_keycaps(cairo_t *cairo, const struct wsk_keypress *keys,
                           const struct wsk_config *config,
                           struct wsk_theme *theme, int scale,
                           uint32_t *width, uint32_t *height,
                           struct keycap_layout **out_layouts);

/*
 * Draw pre-measured keycaps to a cairo context. The caller is responsible
 * for clearing/drawing the background before calling this function.
 */
void wsk_render_keycaps(cairo_t *cairo, struct keycap_layout *layouts,
                        size_t key_count, const struct wsk_config *config,
                        struct wsk_theme *theme, int scale,
                        uint32_t surface_width, uint32_t content_width);

/*
 * Combined measure + draw. Convenience wrapper for callers that don't need
 * the split-phase optimization. Clears background before drawing.
 */
void wsk_render_keycaps_to_cairo(cairo_t *cairo, const struct wsk_keypress *keys,
                                 const struct wsk_config *config,
                                 struct wsk_theme *theme, int scale,
                                 uint32_t *width, uint32_t *height);

#endif
