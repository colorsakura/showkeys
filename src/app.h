#ifndef SHOWKEYS_APP_H
#define SHOWKEYS_APP_H

#include "config.h"
#include "input.h"
#include "keys.h"
#include "theme.h"
#include "wayland.h"

#include <stdbool.h>
#include <sys/types.h>

struct wsk_app {
    // Privileged process state
    int devmgr;
    pid_t devmgr_pid;

    // Core modules
    struct wsk_config config;
    struct wsk_input input;
    struct wsk_theme theme;
    struct wsk_wayland wayland;
    struct wsk_key_list keys;

    bool run;
};

// Functions for managing the application lifecycle
bool wsk_app_init_privileged(struct wsk_app **app_ptr);

bool wsk_app_init(struct wsk_app *app, int argc, char *argv[]);

int wsk_app_run(struct wsk_app *app);

void wsk_app_finish(struct wsk_app *app);

#endif // SHOWKEYS_APP_H
