#include "keys.h"

#include <stdlib.h>

void wsk_keys_append(struct wsk_keypress **head, struct wsk_keypress *keypress,
                     int max_keys) {
  struct wsk_keypress **link = head;
  size_t key_count = 0;
  while (*link) {
    link = &(*link)->next;
    ++key_count;
  }
  *link = keypress;
  ++key_count;

  while ((int)key_count > max_keys && *head) {
    struct wsk_keypress *oldest = *head;
    *head = oldest->next;
    free(oldest);
    --key_count;
  }
}

void wsk_keys_clear(struct wsk_keypress **head) {
  struct wsk_keypress *key = *head;
  while (key) {
    struct wsk_keypress *next = key->next;
    free(key);
    key = next;
  }
  *head = NULL;
}

bool wsk_keys_expired(struct wsk_keypress *head, struct timespec last_key,
                      int timeout, struct timespec now) {
  if (!head) {
    return false;
  }

  return now.tv_sec > last_key.tv_sec + timeout ||
         (now.tv_sec == last_key.tv_sec + timeout &&
          now.tv_nsec >= last_key.tv_nsec);
}
