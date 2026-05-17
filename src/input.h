#ifndef WSK_INPUT_H
#define WSK_INPUT_H

#include "devmgr.h"
#include <stdbool.h>
#include <libinput.h>
#include <xkbcommon/xkbcommon.h>

struct wsk_state;

extern const struct libinput_interface wsk_libinput_impl;

void wsk_input_handle_libinput_event(struct wsk_state *state,
                                     struct libinput_event *event,
                                     bool *dirty);

void wsk_input_set_keymap(struct wsk_state *state,
                          struct xkb_keymap *keymap,
                          struct xkb_state *xkb_state);

void wsk_input_set_keymap_from_fd(struct wsk_state *state, uint32_t format,
                                  int32_t fd, uint32_t size);

#endif // WSK_INPUT_H
