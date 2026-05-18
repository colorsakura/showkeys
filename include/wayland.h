#ifndef WSK_WAYLAND_H
#define WSK_WAYLAND_H

#include "shm.h"
#include <stdbool.h>
#include <wayland-client.h>
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

struct wsk_app;

struct wsk_output {
    struct wl_output *output;
    int scale;
    enum wl_output_subpixel subpixel;
    struct wsk_output *next;
};

struct wsk_wayland {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct wl_seat *seat;
    struct wl_keyboard *keyboard;
    struct zxdg_output_manager_v1 *output_mgr;
    struct zwlr_layer_shell_v1 *layer_shell;

    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer_surface;
    uint32_t width, height;
    bool layer_configured, layer_pending_configure, frame_scheduled, dirty;
    struct wl_callback *frame_callback;
    struct pool_buffer buffers[2];
    struct pool_buffer *current_buffer;
    struct wsk_output *output, *outputs;
};

bool wsk_wayland_init(struct wsk_wayland *wayland, struct wsk_app *app);

void wsk_wayland_finish(struct wsk_wayland *wayland);

int wsk_wayland_get_fd(struct wsk_wayland *wayland);

int wsk_wayland_dispatch(struct wsk_wayland *wayland, struct wsk_app *app);

int wsk_wayland_flush(struct wsk_wayland *wayland);

void wsk_wayland_set_dirty(struct wsk_app *app);

void wsk_wayland_request_layer_configure(struct wsk_app *app);

void wsk_wayland_destroy_layer_surface(struct wsk_wayland *wayland);

extern const struct wl_callback_listener frame_listener;

bool wsk_wayland_create_layer_surface(struct wsk_app *app);

#endif // WSK_WAYLAND_H
