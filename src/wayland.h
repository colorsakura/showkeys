#ifndef SHOWKEYS_WAYLAND_H
#define SHOWKEYS_WAYLAND_H

#include <stdbool.h>

struct wsk_state;

void destroy_layer_surface(struct wsk_state *state);
bool create_layer_surface(struct wsk_state *state);

#endif
