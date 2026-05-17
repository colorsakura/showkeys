#ifndef SHOWKEYS_CONFIG_H
#define SHOWKEYS_CONFIG_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

struct wsk_config {
  uint32_t foreground;
  uint32_t background;
  uint32_t specialfg;
  const char *font;
  int timeout;
  int max_keys;
  const char *key_svg_path;
  uint32_t anchor;
  int margin;
  bool exit_after_parse;
  int exit_code;
};

void wsk_config_init_defaults(struct wsk_config *config);
bool wsk_config_parse(struct wsk_config *config, int argc, char *argv[]);
void wsk_config_print_usage(FILE *stream);

#endif
