#include "app.h"
#include "config.h"
#include "devmgr.h"
#include "input.h"
#include "keys.h"
#include "render.h"
#include "shm.h"
#include "theme.h"
#include "wayland.h"
#include "icons.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-output-unstable-v1-client-protocol.h"

#include <assert.h>
#include <cairo/cairo.h>
#include <errno.h>
#include <libinput.h>
#include <libudev.h>
#include <librsvg/rsvg.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>


bool wsk_app_init_privileged(struct wsk_app **app_ptr) {
    *app_ptr = calloc(1, sizeof(struct wsk_app));
    if (!*app_ptr) {
        fprintf(stderr, "Failed to allocate app state\n");
        return false;
    }
    struct wsk_app *app = *app_ptr;

    if (devmgr_start(&app->devmgr, &app->devmgr_pid, INPUTDEVPATH) > 0) {
        free(app);
        *app_ptr = NULL;
        return false;
    }
    return true;
}

bool wsk_app_init(struct wsk_app *app, int argc, char *argv[]) {
    wsk_config_init_defaults(&app->config);
    if (!wsk_config_parse(&app->config, argc, argv)) {
        return false;
    }
    if (app->config.exit_after_parse) {
        // Special case: parsing requested exit, not a failure.
        return true;
    }

    wsk_theme_init(&app->theme, app->config.key_svg_path);

    if (!wsk_input_init(&app->input, app)) {
        return false;
    }

    if (!wsk_wayland_init(&app->wayland, app)) {
        return false;
    }

    return true;
}

int wsk_app_run(struct wsk_app *app) {
    if (app->config.exit_after_parse) {
        return app->config.exit_code;
    }

    struct pollfd pollfds[] = {
        {
            .fd = wsk_input_get_fd(&app->input),
            .events = POLLIN,
        },
        {
            .fd = wsk_wayland_get_fd(&app->wayland),
            .events = POLLIN,
        },
    };

    app->run = true;
    while (app->run) {
        errno = 0;
        do {
            if (wsk_wayland_flush(&app->wayland) == -1) {
                fprintf(stderr, "wl_display_flush: %s\n",
                        strerror(errno));
                break;
            }
        } while (errno == EAGAIN);
        if (errno != 0 && errno != EAGAIN) {
            break;
        }

        int timeout = -1;
        if (app->keys.head) {
            timeout = 100;
        }

        if (poll(pollfds, sizeof(pollfds) / sizeof(pollfds[0]),
                 timeout) < 0) {
            fprintf(stderr, "poll: %s\n", strerror(errno));
            break;
        }

        /* Clear out old keys */
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        if (wsk_keys_expired(&app->keys, app->config.timeout, now)) {
            wsk_keys_clear(&app->keys);
            wsk_wayland_set_dirty(app);
        }

        if ((pollfds[0].revents & POLLIN)) {
            if (libinput_dispatch(app->input.libinput) != 0) {
                fprintf(stderr, "libinput_dispatch: %s\n",
                        strerror(errno));
                break;
            }
            bool input_dirty = false;
            struct libinput_event *event;
            while ((event = libinput_get_event(app->input.libinput))) {
                wsk_input_handle_libinput_event(
                    app, event, &input_dirty);
                libinput_event_destroy(event);
            }
            if (input_dirty) {
                wsk_wayland_set_dirty(app);
            }
        }

        if ((pollfds[1].revents & POLLIN) &&
            wsk_wayland_dispatch(&app->wayland, app) == -1) {
            fprintf(stderr, "wl_display_dispatch: %s\n",
                    strerror(errno));
            break;
        }
    }
    return 0;
}

void wsk_app_finish(struct wsk_app *app) {
    if (!app) {
        return;
    }

    wsk_keys_clear(&app->keys);
    wsk_theme_finish(&app->theme);
    wsk_input_finish(&app->input);
    wsk_wayland_finish(&app->wayland);
    devmgr_finish(app->devmgr, app->devmgr_pid);
    free(app);
}
