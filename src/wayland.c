#include "app.h"
#include "wayland.h"
#include "input.h"
#include "render.h"
#include "shm.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// Forward declarations for listener functions
static void layer_surface_configure(void *data,
                                    struct zwlr_layer_surface_v1 *surface,
                                    uint32_t serial, uint32_t width,
                                    uint32_t height);

static void layer_surface_closed(void *data,
                                 struct zwlr_layer_surface_v1 *surface);

static void surface_enter(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output);

static void surface_leave(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output);

static void keyboard_keymap(void *data, struct wl_keyboard *wl_keyboard,
                            uint32_t format, int32_t fd, uint32_t size);

static void keyboard_enter(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface,
                           struct wl_array *keys);

static void keyboard_leave(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface);

static void keyboard_key(void *data, struct wl_keyboard *wl_keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state);

static void keyboard_modifiers(void *data, struct wl_keyboard *wl_keyboard,
                               uint32_t serial, uint32_t mods_depressed,
                               uint32_t mods_latched, uint32_t mods_locked,
                               uint32_t group);

static void keyboard_repeat_info(void *data, struct wl_keyboard *wl_keyboard,
                                 int32_t rate, int32_t delay);

static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t capabilities);

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name);

static void output_geometry(void *data, struct wl_output *wl_output, int32_t x,
                            int32_t y, int32_t physical_width,
                            int32_t physical_height, int32_t subpixel,
                            const char *make, const char *model,
                            int32_t transform);

static void output_mode(void *data, struct wl_output *wl_output, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh);

static void output_done(void *data, struct wl_output *wl_output);

static void output_scale(void *data, struct wl_output *wl_output,
                         int32_t factor);

static void registry_global(void *data, struct wl_registry *wl_registry,
                            uint32_t name, const char *interface,
                            uint32_t version);

static void registry_global_remove(void *data, struct wl_registry *wl_registry,
                                   uint32_t name);

// Listener structs
static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = layer_surface_closed,
};
static const struct wl_surface_listener wl_surface_listener = {
    .enter = surface_enter,
    .leave = surface_leave,
};
static const struct wl_keyboard_listener wl_keyboard_listener = {
    .keymap = keyboard_keymap,
    .enter = keyboard_enter,
    .leave = keyboard_leave,
    .key = keyboard_key,
    .modifiers = keyboard_modifiers,
    .repeat_info = keyboard_repeat_info,
};
static const struct wl_seat_listener wl_seat_listener = {
    .capabilities = seat_capabilities,
    .name = seat_name,
};
static const struct wl_output_listener wl_output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
};
static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// Listener function implementations
static void
layer_surface_configure(void *data,
                        struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1,
                        uint32_t serial, uint32_t width, uint32_t height) {
    struct wsk_app *app = data;
    struct wsk_wayland *wayland = &app->wayland;
    wayland->width = width;
    wayland->height = height;
    wayland->layer_configured = true;
    wayland->layer_pending_configure = false;
    zwlr_layer_surface_v1_ack_configure(zwlr_layer_surface_v1, serial);
    wsk_wayland_set_dirty(app);
}

static void
layer_surface_closed(void *data,
                     struct zwlr_layer_surface_v1 *zwlr_layer_surface_v1) {
    struct wsk_app *app = data;
    app->run = false;
}

static void surface_enter(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output) {
    struct wsk_app *app = data;
    struct wsk_wayland *wayland = &app->wayland;
    struct wsk_output *wsk_output = wayland->outputs;
    while (wsk_output && wsk_output->output != output) {
        wsk_output = wsk_output->next;
    }
    if (wsk_output) {
        wayland->output = wsk_output;
        // Output/scale now known — re-render at correct scale if surface is
        // already configured (deferred by render_frame when output was NULL).
        wsk_wayland_set_dirty(app);
    }
}

static void surface_leave(void *data, struct wl_surface *wl_surface,
                          struct wl_output *output) {
    // Who cares (not really possible with layer shell)
}

static void keyboard_keymap(void *data, struct wl_keyboard *wl_keyboard,
                            uint32_t format, int32_t fd, uint32_t size) {
    struct wsk_app *app = data;
    wsk_input_set_keymap_from_fd(&app->input, format, fd, size);
}

static void keyboard_enter(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface,
                           struct wl_array *keys) {
    // Who cares
}

static void keyboard_leave(void *data, struct wl_keyboard *wl_keyboard,
                           uint32_t serial, struct wl_surface *surface) {
    // Who cares
}

static void keyboard_key(void *data, struct wl_keyboard *wl_keyboard,
                         uint32_t serial, uint32_t time, uint32_t key,
                         uint32_t state) {
    // Who cares
}

static void keyboard_modifiers(void *data, struct wl_keyboard *wl_keyboard,
                               uint32_t serial, uint32_t mods_depressed,
                               uint32_t mods_latched, uint32_t mods_locked,
                               uint32_t group) {
    // Who cares
}

static void keyboard_repeat_info(void *data, struct wl_keyboard *wl_keyboard,
                                 int32_t rate, int32_t delay) {
    // TODO
}

static void seat_capabilities(void *data, struct wl_seat *wl_seat,
                              uint32_t capabilities) {
    struct wsk_app *app = data;
    struct wsk_wayland *wayland = &app->wayland;
    if (wayland->keyboard) {
        // TODO: support multiple seats
        return;
    }

    if (!(capabilities & WL_SEAT_CAPABILITY_KEYBOARD)) {
        fprintf(stderr, "wl_seat does not support keyboard");
        app->run = false;
        return;
    }

    wayland->keyboard = wl_seat_get_keyboard(wl_seat);
    wl_keyboard_add_listener(wayland->keyboard, &wl_keyboard_listener, app);
}

static void seat_name(void *data, struct wl_seat *wl_seat, const char *name) {
    struct wsk_app *app = data;
    /* TODO: support multiple seats */
    if (libinput_udev_assign_seat(app->input.libinput, "seat0") != 0) {
        fprintf(stderr, "Failed to assign libinput seat\n");
        app->run = false;
        return;
    }
}

static void output_geometry(void *data, struct wl_output *wl_output, int32_t x,
                            int32_t y, int32_t physical_width,
                            int32_t physical_height, int32_t subpixel,
                            const char *make, const char *model,
                            int32_t transform) {
    struct wsk_output *output = data;
    output->subpixel = subpixel;
}

static void output_mode(void *data, struct wl_output *wl_output, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh) {
    // Who cares
}

static void output_done(void *data, struct wl_output *wl_output) {
    // Who cares
}

static void output_scale(void *data, struct wl_output *wl_output,
                         int32_t factor) {
    struct wsk_output *output = data;
    output->scale = factor;
}

static void registry_global(void *data, struct wl_registry *wl_registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
    struct wsk_app *app = data;
    struct wsk_wayland *wayland = &app->wayland;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        wayland->compositor = wl_registry_bind(
            wl_registry, name, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        wayland->shm =
                wl_registry_bind(wl_registry, name, &wl_shm_interface, 1);
    } else if (strcmp(interface, wl_seat_interface.name) == 0) {
        wayland->seat =
                wl_registry_bind(wl_registry, name, &wl_seat_interface, 5);
    } else if (strcmp(interface,
                      zxdg_output_manager_v1_interface.name) == 0) {
        wayland->output_mgr = wl_registry_bind(
            wl_registry, name, &zxdg_output_manager_v1_interface, 1);
    } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) ==
               0) {
        wayland->layer_shell = wl_registry_bind(
            wl_registry, name, &zwlr_layer_shell_v1_interface, 1);
    } else if (strcmp(interface, wl_output_interface.name) == 0) {
        struct wsk_output *output = calloc(1, sizeof(struct wsk_output));
        output->output =
                wl_registry_bind(wl_registry, name, &wl_output_interface, 3);
        output->scale = 1;
        struct wsk_output **link = &wayland->outputs;
        while (*link) {
            link = &(*link)->next;
        }
        *link = output;
        wl_output_add_listener(output->output, &wl_output_listener,
                               output);
    }
}

static void registry_global_remove(void *data,
                                   struct wl_registry *wl_registry,
                                   uint32_t name) {
    /* This space deliberately left blank */
}


// Finally, the public API functions
void wsk_wayland_destroy_layer_surface(struct wsk_wayland *wayland) {
    if (wayland->layer_surface) {
        zwlr_layer_surface_v1_destroy(wayland->layer_surface);
        wayland->layer_surface = NULL;
    }
    if (wayland->surface) {
        wl_surface_destroy(wayland->surface);
        wayland->surface = NULL;
    }
    wayland->output = NULL;
    wayland->width = 0;
    wayland->height = 0;
    wayland->layer_configured = false;
    wayland->layer_pending_configure = false;
}

bool wsk_wayland_create_layer_surface(struct wsk_app *app) {
    struct wsk_wayland *wayland = &app->wayland;
    if (wayland->surface) {
        return true;
    }

    wayland->surface = wl_compositor_create_surface(wayland->compositor);
    if (!wayland->surface) {
        return false;
    }
    wl_surface_add_listener(wayland->surface, &wl_surface_listener, app);

    wayland->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
        wayland->layer_shell, wayland->surface, NULL,
        ZWLR_LAYER_SHELL_V1_LAYER_TOP, "showkeys");
    if (!wayland->layer_surface) {
        wsk_wayland_destroy_layer_surface(wayland);
        wayland->surface = NULL;
        return false;
    }
    zwlr_layer_surface_v1_add_listener(wayland->layer_surface,
                                       &layer_surface_listener, app);
    return true;
}

void wsk_wayland_request_layer_configure(struct wsk_app *app) {
    struct wsk_wayland *wayland = &app->wayland;
    if (wayland->layer_pending_configure || !app->keys.head) {
        return;
    }
    if (!wsk_wayland_create_layer_surface(app)) {
        return;
    }

    zwlr_layer_surface_v1_set_size(wayland->layer_surface, 1, 1);
    zwlr_layer_surface_v1_set_anchor(wayland->layer_surface,
                                     app->config.anchor);
    zwlr_layer_surface_v1_set_margin(
        wayland->layer_surface, app->config.margin, app->config.margin,
        app->config.margin, app->config.margin);
    zwlr_layer_surface_v1_set_exclusive_zone(wayland->layer_surface, -1);
    wl_surface_commit(wayland->surface);
    wayland->layer_pending_configure = true;
}

void wsk_wayland_set_dirty(struct wsk_app *app) {
    struct wsk_wayland *wayland = &app->wayland;
    if (wayland->frame_scheduled || !wayland->layer_configured) {
        wayland->dirty = true;
        if (!wayland->layer_configured) {
            wsk_wayland_request_layer_configure(app);
        }
    } else if (wayland->surface) {
        wayland->dirty = false;
        wsk_render_frame(app);
    }
}

bool wsk_wayland_init(struct wsk_wayland *wayland, struct wsk_app *app) {
    memset(wayland, 0, sizeof(*wayland));

    wayland->display = wl_display_connect(NULL);
    if (!wayland->display) {
        fprintf(stderr, "wl_display_connect: %s\n", strerror(errno));
        return false;
    }

    wayland->registry = wl_display_get_registry(wayland->display);
    assert(wayland->registry);
    wl_registry_add_listener(wayland->registry, &registry_listener, app);
    wl_display_roundtrip(wayland->display);

    struct {
        const char *name;
        void *ptr;
    } need_globals[] = {
        {"wl_compositor", &wayland->compositor},
        {"wl_shm", &wayland->shm},
        {"wl_seat", &wayland->seat},
        {"wlr_layer_shell", &wayland->layer_shell},
    };
    for (size_t i = 0; i < sizeof(need_globals) / sizeof(need_globals[0]);
         ++i) {
        if (!need_globals[i].ptr) {
            fprintf(stderr,
                    "Error: required Wayland interface '%s' "
                    "is not present\n",
                    need_globals[i].name);
            return false;
        }
    }

    // TODO: Listener for xdg output

    wl_seat_add_listener(wayland->seat, &wl_seat_listener, app);
    wl_display_roundtrip(wayland->display);
    return true;
}

void wsk_wayland_finish(struct wsk_wayland *wayland) {
    wsk_wayland_destroy_layer_surface(wayland);
    struct wsk_output *output = wayland->outputs;
    while (output) {
        struct wsk_output *next = output->next;
        if (output->output) {
            wl_output_destroy(output->output);
        }
        free(output);
        output = next;
    }
    if (wayland->display) {
        wl_display_disconnect(wayland->display);
    }
}

int wsk_wayland_get_fd(struct wsk_wayland *wayland) {
    return wl_display_get_fd(wayland->display);
}

int wsk_wayland_dispatch(struct wsk_wayland *wayland, struct wsk_app *app) {
    return wl_display_dispatch(wayland->display);
}

int wsk_wayland_flush(struct wsk_wayland *wayland) {
    int ret = wl_display_flush(wayland->display);
    if (ret == -1 && errno != EAGAIN) {
        return -1;
    }
    return 0;
}
