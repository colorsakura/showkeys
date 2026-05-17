#ifndef SHOWKEYS_ICONS_H
#define SHOWKEYS_ICONS_H

#include <librsvg/rsvg.h>
#include <stdbool.h>

struct wsk_icon_cache_entry {
  char *icon_name;
  RsvgHandle *svg;
  bool failed;
  struct wsk_icon_cache_entry *next;
};

struct wsk_icon_cache {
  struct wsk_icon_cache_entry *entries;
};

const char *wsk_special_icon_name(const char *key_name);

RsvgHandle *wsk_icon_cache_get(struct wsk_icon_cache *cache,
                               const char *base_dir,
                               const char *icon_name);

void wsk_icon_cache_finish(struct wsk_icon_cache *cache);

#endif
