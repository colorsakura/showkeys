const std = @import("std");
const c = @import("c");

// ---------------------------------------------------------------------------
// Type aliases
// ---------------------------------------------------------------------------

const App = c.struct_wsk_app;

/// Get the current errno value via C __errno_location.
fn errnoPtr() *c_int {
    return c.__errno_location();
}

// ---------------------------------------------------------------------------
// Public API — C ABI
// ---------------------------------------------------------------------------

/// Allocate the app struct and start the privileged device manager.
export fn wsk_app_init_privileged(app_ptr: *?*App) bool {
    const allocation = c.calloc(1, @sizeOf(App)) orelse {
        std.log.err("Failed to allocate app state", .{});
        return false;
    };
    const app: *App = @ptrCast(@alignCast(allocation));
    app_ptr.* = app;

    if (c.devmgr_start(&app.devmgr, &app.devmgr_pid, c.INPUTDEVPATH) > 0) {
        c.free(app);
        app_ptr.* = null;
        return false;
    }
    return true;
}

/// Initialise the app: parse config, load theme, set up input and Wayland.
export fn wsk_app_init(app: *App, argc: c_int, argv: [*c][*c]u8) bool {
    c.wsk_config_init_defaults(&app.config);
    if (!c.wsk_config_parse(&app.config, argc, argv)) return false;
    if (app.config.exit_after_parse) return true;

    _ = c.wsk_theme_init(&app.theme, app.config.key_svg_path);

    if (!c.wsk_input_init(&app.input, app)) return false;
    if (!c.wsk_wayland_init(&app.wayland, app)) return false;

    return true;
}

/// Main event loop: poll input and Wayland fds, dispatch events,
/// handle key expiry.
export fn wsk_app_run(app: *App) c_int {
    if (app.config.exit_after_parse) return app.config.exit_code;

    var pollfds = [_]c.struct_pollfd{
        .{
            .fd = c.wsk_input_get_fd(&app.input),
            .events = c.POLLIN,
            .revents = 0,
        },
        .{
            .fd = c.wsk_wayland_get_fd(&app.wayland),
            .events = c.POLLIN,
            .revents = 0,
        },
    };

    app.run = true;
    while (app.run) {
        errnoPtr().* = 0;
        while (true) {
            if (c.wsk_wayland_flush(&app.wayland) == -1) {
                std.log.err("wl_display_flush: {s}", .{c.strerror(errnoPtr().*)});
                break;
            }
            if (errnoPtr().* != c.EAGAIN) break;
        }
        if (errnoPtr().* != 0 and errnoPtr().* != c.EAGAIN) break;

        const timeout: c_int = if (app.keys.head != null) 100 else -1;

        if (c.poll(&pollfds, pollfds.len, timeout) < 0) {
            std.log.err("poll: {s}", .{c.strerror(errnoPtr().*)});
            break;
        }

        if ((pollfds[0].revents & c.POLLIN) != 0) {
            if (c.libinput_dispatch(app.input.libinput) != 0) {
                std.log.err("libinput_dispatch: {s}", .{c.strerror(errnoPtr().*)});
                break;
            }
            var input_dirty = false;
            while (c.libinput_get_event(app.input.libinput)) |event| {
                c.wsk_input_handle_libinput_event(app, event, &input_dirty);
                c.libinput_event_destroy(event);
            }
            if (input_dirty) c.wsk_wayland_set_dirty(app);
        }

        if ((pollfds[1].revents & c.POLLIN) != 0 and
            c.wsk_wayland_dispatch(&app.wayland, app) == -1)
        {
            std.log.err("wl_display_dispatch: {s}", .{c.strerror(errnoPtr().*)});
            break;
        }

        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
        if (c.wsk_keys_expired(&app.keys, app.config.timeout, now)) {
            c.wsk_keys_clear(&app.keys);
            c.wsk_wayland_set_dirty(app);
        }
    }
    return 0;
}

/// Release all resources and shut down.
export fn wsk_app_finish(app: ?*App) void {
    const state = app orelse return;

    c.wsk_keys_clear(&state.keys);
    c.wsk_theme_finish(&state.theme);
    c.wsk_input_finish(&state.input);
    c.wsk_wayland_finish(&state.wayland);
    c.devmgr_finish(state.devmgr, state.devmgr_pid);
    c.free(state);
}
