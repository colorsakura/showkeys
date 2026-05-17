#ifndef SHOWKEYS_THEME_H
#define SHOWKEYS_THEME_H

#include "icons.h"
#include <cairo/cairo.h>
#include <librsvg/rsvg.h>
#include <stdbool.h>

struct wsk_theme {
    const char *key_svg_path;
    char *base_dir;

    RsvgHandle *key_svg;
    bool key_svg_failed;

    struct wsk_icon_cache icons;
};

bool wsk_theme_init(struct wsk_theme *theme, const char *key_svg_path);

void wsk_theme_finish(struct wsk_theme *theme);

char *wsk_xstrdup(const char *str);

char *wsk_path_dirname(const char *path);

char *wsk_join_path3(const char *dir, const char *subdir, const char *file);

bool wsk_svg_draw_to_rect(cairo_t *cr, RsvgHandle *svg, double x, double y,
                          double width, double height,
                          const char *description);

#endif
