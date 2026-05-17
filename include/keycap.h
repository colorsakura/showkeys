#ifndef SHOWKEYS_KEYCAP_H
#define SHOWKEYS_KEYCAP_H

#include "config.h"
#include "icons.h"
#include "keys.h"

#include "theme.h"
#include <cairo/cairo.h>
#include <librsvg/rsvg.h>
#include <stdbool.h>
#include <stdint.h>

void wsk_render_keycaps_to_cairo(cairo_t *cr, const struct wsk_keypress *keys,
                                 const struct wsk_config *config,
                                 struct wsk_theme *theme, int scale,
                                 uint32_t *width, uint32_t *height);

#endif
