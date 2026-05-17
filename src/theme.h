#ifndef SHOWKEYS_THEME_H
#define SHOWKEYS_THEME_H

#include <cairo/cairo.h>
#include <librsvg/rsvg.h>
#include <stdbool.h>

char *wsk_xstrdup(const char *str);

char *wsk_path_dirname(const char *path);

char *wsk_join_path3(const char *dir, const char *subdir, const char *file);

bool wsk_svg_draw_to_rect(cairo_t *cr, RsvgHandle *svg, double x, double y,
                          double width, double height,
                          const char *description);

#endif
