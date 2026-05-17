#include "theme.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

  size_t len = (size_t)(slash - path);
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
