#ifndef WSK_WAYLAND_H
#define WSK_WAYLAND_H

#include <stdbool.h>
#include <wayland-client.h>

struct wsk_app;

struct wsk_output {
	struct wl_output *output;
	int scale;
	enum wl_output_subpixel subpixel;
	struct wsk_output *next;
};

bool wsk_wayland_init(struct wsk_app *app);
void wsk_wayland_finish(struct wsk_app *app);

int wsk_wayland_get_fd(struct wsk_app *app);
int wsk_wayland_dispatch(struct wsk_app *app);
int wsk_wayland_flush(struct wsk_app *app);

void wsk_wayland_set_dirty(struct wsk_app *app);
void wsk_wayland_request_layer_configure(struct wsk_app *app);
void wsk_wayland_destroy_layer_surface(struct wsk_app *app);
bool wsk_wayland_create_layer_surface(struct wsk_app *app);

#endif // WSK_WAYLAND_H
