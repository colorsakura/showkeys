#ifndef SHOWKEYS_KEYS_H
#define SHOWKEYS_KEYS_H

#include <stdbool.h>
#include <time.h>
#include <xkbcommon/xkbcommon.h>

struct wsk_keypress {
  xkb_keysym_t sym;
  char name[128];
  char utf8[128];
  struct wsk_keypress *next;
};

void wsk_keys_append(struct wsk_keypress **head, struct wsk_keypress *keypress,
                     int max_keys);
void wsk_keys_clear(struct wsk_keypress **head);
bool wsk_keys_expired(struct wsk_keypress *head, struct timespec last_key,
                      int timeout, struct timespec now);

#endif
