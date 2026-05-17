#include "color.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void wsk_cairo_set_source_u32(cairo_t *cr, uint32_t color) {
    cairo_set_source_rgba(cr, (color >> (3 * 8) & 0xFF) / 255.0,
                          (color >> (2 * 8) & 0xFF) / 255.0,
                          (color >> (1 * 8) & 0xFF) / 255.0,
                          (color >> (0 * 8) & 0xFF) / 255.0);
}

uint32_t wsk_color_parse(const char *text, uint32_t fallback) {
    if (text[0] == '#') {
        ++text;
    }

    int len = strlen(text);
    if (len != 6 && len != 8) {
        fprintf(stderr, "Invalid color %s, defaulting to color 0x%08X\n", text,
                fallback);
        return fallback;
    }

    uint32_t color = (uint32_t) strtoul(text, NULL, 16);
    if (len == 6) {
        color = (color << 8) | 0xFF;
    }
    return color;
}
