#ifndef WSK_WAYLAND_H
#define WSK_WAYLAND_H

#include <stdbool.h>
#include <wayland-client.h>

struct wsk_state;

struct wsk_output {
	struct wl_output *output;
	int scale;
	enum wl_output_subpixel subpixel;
	struct wsk_output *next;
};

bool wsk_wayland_init(struct wsk_state *state);
void wsk_wayland_finish(struct wsk_state *state);

int wsk_wayland_get_fd(struct wsk_state *state);
int wsk_wayland_dispatch(struct wsk_state *state);
int wsk_wayland_flush(struct wsk_state *state);

void wsk_wayland_set_dirty(struct wsk_state *state);
void wsk_wayland_request_layer_configure(struct wsk_state *state);
void wsk_wayland_destroy_layer_surface(struct wsk_state *state);
bool wsk_wayland_create_layer_surface(struct wsk_state *state);

#endif // WSK_WAYLAND_H
