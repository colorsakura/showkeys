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

	if (app->config.key_svg_path) {
		app->icon_dir = wsk_path_dirname(app->config.key_svg_path);
		if (!app->icon_dir) {
			fprintf(stderr,
				"Unable to allocate icon directory path\n");
		}

		GError *error = NULL;
		app->key_svg = rsvg_handle_new_from_file(
		    app->config.key_svg_path, &error);
		if (!app->key_svg) {
			fprintf(stderr, "Unable to load key SVG '%s': %s\n",
				app->config.key_svg_path,
				error ? error->message : "unknown error");
			if (error) {
				g_error_free(error);
			}
			app->key_svg_failed = true;
		}
	}

	app->udev = udev_new();
	if (!app->udev) {
		fprintf(stderr, "udev_create: %s\n", strerror(errno));
		return false;
	}

	app->libinput = libinput_udev_create_context(&wsk_libinput_impl,
						     &app->devmgr, app->udev);
	udev_unref(app->udev);
	app->udev = NULL; // udev is no longer needed after context creation
	if (!app->libinput) {
		fprintf(stderr, "libinput_udev_create_context: %s\n",
			strerror(errno));
		return false;
	}

	app->xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!app->xkb_context) {
		fprintf(stderr, "xkb_context_new: %s\n", strerror(errno));
		return false;
	}

	if (!wsk_wayland_init(app)) {
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
		.fd = libinput_get_fd(app->libinput),
		.events = POLLIN,
	    },
	    {
		.fd = wsk_wayland_get_fd(app),
		.events = POLLIN,
	    },
	};

	app->run = true;
	while (app->run) {
		errno = 0;
		do {
			if (wsk_wayland_flush(app) == -1) {
				fprintf(stderr, "wl_display_flush: %s\n",
					strerror(errno));
				break;
			}
		} while (errno == EAGAIN);
		if (errno != 0 && errno != EAGAIN) {
			break;
		}

		int timeout = -1;
		if (app->keys) {
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
		if (wsk_keys_expired(app->keys, app->last_key,
				     app->config.timeout, now)) {
			wsk_keys_clear(&app->keys);
			wsk_wayland_set_dirty(app);
		}

		if ((pollfds[0].revents & POLLIN)) {
			if (libinput_dispatch(app->libinput) != 0) {
				fprintf(stderr, "libinput_dispatch: %s\n",
					strerror(errno));
				break;
			}
			bool input_dirty = false;
			struct libinput_event *event;
			while ((event = libinput_get_event(app->libinput))) {
				wsk_input_handle_libinput_event(
				    app, event, &input_dirty);
				libinput_event_destroy(event);
			}
			if (input_dirty) {
				wsk_wayland_set_dirty(app);
			}
		}

		if ((pollfds[1].revents & POLLIN) &&
		    wsk_wayland_dispatch(app) == -1) {
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

	wsk_icon_cache_finish(&app->icons);
	free(app->icon_dir);
	if (app->key_svg) {
		g_object_unref(app->key_svg);
	}
	wsk_wayland_finish(app);
	if (app->libinput) {
		libinput_unref(app->libinput);
	}
	if (app->xkb_context) {
		xkb_context_unref(app->xkb_context);
	}
	devmgr_finish(app->devmgr, app->devmgr_pid);
	free(app);
}
