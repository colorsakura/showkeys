#include "app.h"
#include "config.h"
#include "devmgr.h"
#include "input.h"
#include "keys.h"
#include "render.h"
#include "shm.h"
#include "theme.h"
#include "wayland.h"
#include <assert.h>
#include <cairo/cairo.h>
#include <errno.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#include <librsvg/rsvg.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

int main(int argc, char *argv[]) {
	/* NOTICE: This code runs as root */
	struct wsk_state state = {0};
	if (devmgr_start(&state.devmgr, &state.devmgr_pid, INPUTDEVPATH) > 0) {
		return 1;
	}

	/* Begin normal user code: */
	int ret = 0;

	wsk_config_init_defaults(&state.config);
	if (!wsk_config_parse(&state.config, argc, argv)) {
		ret = 1;
		goto exit;
	}
	if (state.config.exit_after_parse) {
		ret = state.config.exit_code;
		goto exit;
	}

	if (state.config.key_svg_path) {
		state.icon_dir = wsk_path_dirname(state.config.key_svg_path);
		if (!state.icon_dir) {
			fprintf(stderr,
				"Unable to allocate icon directory path\n");
		}

		GError *error = NULL;
		state.key_svg = rsvg_handle_new_from_file(
		    state.config.key_svg_path, &error);
		if (!state.key_svg) {
			fprintf(stderr, "Unable to load key SVG '%s': %s\n",
				state.config.key_svg_path,
				error ? error->message : "unknown error");
			if (error) {
				g_error_free(error);
			}
			state.key_svg_failed = true;
		}
	}

	state.udev = udev_new();
	if (!state.udev) {
		fprintf(stderr, "udev_create: %s\n", strerror(errno));
		ret = 1;
		goto exit;
	}

	state.libinput = libinput_udev_create_context(&wsk_libinput_impl,
						      &state.devmgr,
						      state.udev);
	udev_unref(state.udev);
	if (!state.libinput) {
		fprintf(stderr, "libinput_udev_create_context: %s\n",
			strerror(errno));
		ret = 1;
		goto exit;
	}

	state.xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	if (!state.xkb_context) {
		fprintf(stderr, "xkb_context_new: %s\n", strerror(errno));
		ret = 1;
		goto exit;
	}

	if (!wsk_wayland_init(&state)) {
		ret = 1;
		goto exit;
	}

	struct pollfd pollfds[] = {
	    {
		.fd = libinput_get_fd(state.libinput),
		.events = POLLIN,
	    },
	    {
		.fd = wsk_wayland_get_fd(&state),
		.events = POLLIN,
	    },
	};

	state.run = true;
	while (state.run) {
		errno = 0;
		do {
			if (wsk_wayland_flush(&state) == -1) {
				fprintf(stderr, "wl_display_flush: %s\n",
					strerror(errno));
				break;
			}
		} while (errno == EAGAIN);
		if (errno != 0 && errno != EAGAIN) {
			break;
		}

		int timeout = -1;
		if (state.keys) {
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
		if (wsk_keys_expired(state.keys, state.last_key,
				     state.config.timeout, now)) {
			wsk_keys_clear(&state.keys);
			wsk_wayland_set_dirty(&state);
		}

		if ((pollfds[0].revents & POLLIN)) {
			if (libinput_dispatch(state.libinput) != 0) {
				fprintf(stderr, "libinput_dispatch: %s\n",
					strerror(errno));
				break;
			}
			bool input_dirty = false;
			struct libinput_event *event;
			while ((event = libinput_get_event(state.libinput))) {
				wsk_input_handle_libinput_event(
				    &state, event, &input_dirty);
				libinput_event_destroy(event);
			}
			if (input_dirty) {
				wsk_wayland_set_dirty(&state);
			}
		}

		if ((pollfds[1].revents & POLLIN) &&
		    wsk_wayland_dispatch(&state) == -1) {
			fprintf(stderr, "wl_display_dispatch: %s\n",
				strerror(errno));
			break;
		}
	}

exit:
	wsk_icon_cache_finish(&state.icons);
	free(state.icon_dir);
	if (state.key_svg) {
		g_object_unref(state.key_svg);
	}
	wsk_wayland_finish(&state);
	libinput_unref(state.libinput);
	if (state.xkb_context) {
		xkb_context_unref(state.xkb_context);
	}
	devmgr_finish(state.devmgr, state.devmgr_pid);
	return ret;
}
