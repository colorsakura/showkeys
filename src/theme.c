#include "theme.h"

#include <librsvg/rsvg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool wsk_theme_init(struct wsk_theme *theme, const char *key_svg_path) {
    memset(theme, 0, sizeof(*theme));
    theme->key_svg_path = key_svg_path;

    if (key_svg_path) {
        theme->base_dir = wsk_path_dirname(key_svg_path);
        if (!theme->base_dir) {
            fprintf(stderr, "Unable to allocate icon directory path\\n");
        }

        GError *error = NULL;
        theme->key_svg = rsvg_handle_new_from_file(key_svg_path, &error);
        if (!theme->key_svg) {
            fprintf(stderr, "Unable to load key SVG '%s': %s\\n", key_svg_path,
                    error ? error->message : "unknown error");
            if (error) {
                g_error_free(error);
            }
            theme->key_svg_failed = true;
        }
    }
    return true;
}

void wsk_theme_finish(struct wsk_theme *theme) {
    wsk_icon_cache_finish(&theme->icons);
    free(theme->base_dir);
    if (theme->key_svg) {
        g_object_unref(theme->key_svg);
    }
}


char *wsk_xstrdup(const char *str) {
    size_t len = strlen(str) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, str, len);
    }
    return copy;
}

char *wsk_path_dirname(const char *path) {
    const char *slash = strrchr(path, '/');
    if (!slash) {
        return wsk_xstrdup(".");
    }
    if (slash == path) {
        return wsk_xstrdup("/");
    }

    size_t len = (size_t) (slash - path);
    char *dir = malloc(len + 1);
    if (!dir) {
        return NULL;
    }
    memcpy(dir, path, len);
    dir[len] = '\0';
    return dir;
}

char *wsk_join_path3(const char *dir, const char *subdir, const char *file) {
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

bool wsk_svg_draw_to_rect(cairo_t *cr, RsvgHandle *svg, double x, double y,
                          double width, double height,
                          const char *description) {
    RsvgRectangle viewport = {
        .x = x,
        .y = y,
        .width = width,
        .height = height,
    };
    GError *error = NULL;
    gboolean ok = rsvg_handle_render_document(svg, cr, &viewport, &error);
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
