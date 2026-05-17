#ifndef SHOWKEYS_COLOR_H
#define SHOWKEYS_COLOR_H

#include <cairo/cairo.h>
#include <stdint.h>

void wsk_cairo_set_source_u32(cairo_t *cr, uint32_t color);
uint32_t wsk_color_parse(const char *text, uint32_t fallback);

#endif
