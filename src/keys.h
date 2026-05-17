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

struct wsk_key_list {
    struct wsk_keypress *head;
    struct timespec last_key;
};

void wsk_keys_append(struct wsk_key_list *keys, struct wsk_keypress *keypress,
                     int max_keys, const struct timespec *now);

void wsk_keys_clear(struct wsk_key_list *keys);

bool wsk_keys_expired(const struct wsk_key_list *keys, int timeout,
                      struct timespec now);

#endif
