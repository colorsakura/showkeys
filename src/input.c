#include "app.h"
#include "input.h"
#include "devmgr.h"
#include "keys.h"
#include <wayland-client-protocol.h>

#include <assert.h>
#include <errno.h>
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>


static const char *pointer_button_name(uint32_t button) {
    switch (button) {
        case BTN_LEFT:
            return "Mouse Left";
        case BTN_RIGHT:
            return "Mouse Right";
        case BTN_MIDDLE:
            return "Mouse Middle";
        case BTN_SIDE:
            return "Mouse Side";
        case BTN_EXTRA:
            return "Mouse Extra";
        case BTN_FORWARD:
            return "Mouse Forward";
        case BTN_BACK:
            return "Mouse Back";
        default:
            return NULL;
    }
}

static void handle_keyboard_key_event(struct wsk_app *app,
                                      struct libinput_event_keyboard *kbevent,
                                      bool *dirty) {
    if (!app->xkb_state) {
        return;
    }

    uint32_t keycode = libinput_event_keyboard_get_key(kbevent) + 8;
    enum libinput_key_state key_state =
            libinput_event_keyboard_get_key_state(kbevent);
    xkb_state_update_key(app->xkb_state, keycode,
                         key_state == LIBINPUT_KEY_STATE_RELEASED
                             ? XKB_KEY_UP
                             : XKB_KEY_DOWN);

    xkb_keysym_t keysym = xkb_state_key_get_one_sym(app->xkb_state, keycode);

    struct wsk_keypress *keypress;
    switch (key_state) {
        case LIBINPUT_KEY_STATE_RELEASED:
            /* Who cares */
            break;
        case LIBINPUT_KEY_STATE_PRESSED:
            keypress = calloc(1, sizeof(struct wsk_keypress));
            assert(keypress);
            keypress->sym = keysym;
            xkb_keysym_get_name(keypress->sym, keypress->name, sizeof(keypress->name));
            if (xkb_state_key_get_utf8(app->xkb_state, keycode, keypress->utf8,
                                       sizeof(keypress->utf8)) <= 0 ||
                keypress->utf8[0] <= ' ') {
                keypress->utf8[0] = '\0';
            }
            wsk_keys_append(&app->keys, keypress, app->config.max_keys);
            clock_gettime(CLOCK_MONOTONIC, &app->last_key);
            *dirty = true;
            break;
    }
}

static void handle_pointer_button_event(struct wsk_app *app,
                                        struct libinput_event_pointer *pevent,
                                        bool *dirty) {
    enum libinput_button_state button_state =
            libinput_event_pointer_get_button_state(pevent);
    if (button_state != LIBINPUT_BUTTON_STATE_PRESSED) {
        return;
    }

    uint32_t button = libinput_event_pointer_get_button(pevent);
    struct wsk_keypress *keypress = calloc(1, sizeof(struct wsk_keypress));
    assert(keypress);
    keypress->sym = XKB_KEY_NoSymbol;
    keypress->utf8[0] = '\0';

    const char *name = pointer_button_name(button);
    if (name) {
        snprintf(keypress->name, sizeof(keypress->name), "%s", name);
    } else {
        snprintf(keypress->name, sizeof(keypress->name), "Mouse 0x%x", button);
    }

    wsk_keys_append(&app->keys, keypress, app->config.max_keys);
    clock_gettime(CLOCK_MONOTONIC, &app->last_key);
    *dirty = true;
}

void wsk_input_handle_libinput_event(struct wsk_app *app,
                                     struct libinput_event *event, bool *dirty) {
    enum libinput_event_type event_type = libinput_event_get_type(event);
    switch (event_type) {
        case LIBINPUT_EVENT_KEYBOARD_KEY:
            handle_keyboard_key_event(app, libinput_event_get_keyboard_event(event),
                                      dirty);
            break;
        case LIBINPUT_EVENT_POINTER_BUTTON:
            handle_pointer_button_event(app, libinput_event_get_pointer_event(event),
                                        dirty);
            break;
        default:
            break;
    }
}

void wsk_input_set_keymap(struct wsk_app *app,
                          struct xkb_keymap *keymap,
                          struct xkb_state *xkb_state) {
    xkb_keymap_unref(app->xkb_keymap);
    xkb_state_unref(app->xkb_state);
    app->xkb_keymap = keymap;
    app->xkb_state = xkb_state;
}

static int libinput_open_restricted(const char *path, int flags, void *data) {
    int *fd = data;
    return devmgr_open(*fd, path);
}

static void libinput_close_restricted(int fd, void *data) { close(fd); }

const struct libinput_interface wsk_libinput_impl = {
    .open_restricted = libinput_open_restricted,
    .close_restricted = libinput_close_restricted,
};

void wsk_input_set_keymap_from_fd(struct wsk_app *app, uint32_t format,
                                  int32_t fd, uint32_t size) {
    char *map_shm = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, 0);
    if (map_shm == MAP_FAILED) {
        close(fd);
        fprintf(stderr, "Unable to mmap keymap: %s", strerror(errno));
        return;
    }
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        munmap(map_shm, size);
        close(fd);
        return;
    }

    struct xkb_keymap *keymap = xkb_keymap_new_from_string(
        app->xkb_context, map_shm, XKB_KEYMAP_FORMAT_TEXT_V1,
        XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map_shm, size);
    close(fd);

    struct xkb_state *xkb_state = xkb_state_new(keymap);
    wsk_input_set_keymap(app, keymap, xkb_state);
}

