#ifndef WSK_INPUT_H
#define WSK_INPUT_H

#include <stdbool.h>
#include <libinput.h>
#include <libudev.h>
#include <xkbcommon/xkbcommon.h>

struct wsk_app;

struct wsk_input {
    struct udev *udev;
    struct libinput *libinput;

    struct xkb_context *xkb_context;
    struct xkb_keymap *xkb_keymap;
    struct xkb_state *xkb_state;
};

bool wsk_input_init(struct wsk_input *input, struct wsk_app *app);

void wsk_input_finish(struct wsk_input *input);

int wsk_input_get_fd(struct wsk_input *input);

void wsk_input_handle_libinput_event(struct wsk_app *app,
                                     struct libinput_event *event,
                                     bool *dirty);

void wsk_input_set_keymap(struct wsk_input *input,
                          struct xkb_keymap *keymap,
                          struct xkb_state *xkb_state);

void wsk_input_set_keymap_from_fd(struct wsk_input *input,
                                  uint32_t format, int32_t fd,
                                  uint32_t size);

#endif // WSK_INPUT_H
