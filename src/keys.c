#include "keys.h"

#include <stdlib.h>

void wsk_keys_append(struct wsk_key_list *keys, struct wsk_keypress *keypress,
                     int max_keys, const struct timespec *now) {
    keys->last_key = *now;
    struct wsk_keypress **link = &keys->head;
    size_t key_count = 0;
    while (*link) {
        link = &(*link)->next;
        ++key_count;
    }
    *link = keypress;
    ++key_count;

    while ((int) key_count > max_keys && keys->head) {
        struct wsk_keypress *oldest = keys->head;
        keys->head = oldest->next;
        free(oldest);
        --key_count;
    }
}

void wsk_keys_clear(struct wsk_key_list *keys) {
    struct wsk_keypress *key = keys->head;
    while (key) {
        struct wsk_keypress *next = key->next;
        free(key);
        key = next;
    }
    keys->head = NULL;
}

bool wsk_keys_expired(const struct wsk_key_list *keys, int timeout,
                      struct timespec now) {
    if (!keys->head) {
        return false;
    }

    return now.tv_sec > keys->last_key.tv_sec + timeout ||
           (now.tv_sec == keys->last_key.tv_sec + timeout &&
            now.tv_nsec >= keys->last_key.tv_nsec);
}
