const std = @import("std");
const c = @import("c");
const types = @import("types.zig");
const keys = @import("keys.zig");
const config = @import("config.zig");
const input = @import("input.zig");
const theme = @import("theme.zig");
const devmgr = @import("devmgr.zig");
const wl = @import("wayland.zig");
const errno = @import("errno.zig");

const App = types.App;
const KeyList = keys.KeyList;

// ---------------------------------------------------------------------------
// Public API — C ABI
// ---------------------------------------------------------------------------

/// Allocate the app struct and start the privileged device manager.
pub fn initPrivileged(app_ptr: *?*App) bool {
    const app = std.heap.page_allocator.create(App) catch {
        std.log.err("Failed to allocate app state", .{});
        return false;
    };
    app.* = .{};
    app_ptr.* = app;

    if (devmgr.start(&app.devmgr, &app.devmgr_pid, c.INPUTDEVPATH) > 0) {
        std.heap.page_allocator.destroy(app);
        app_ptr.* = null;
        return false;
    }
    return true;
}

/// Initialise the app: parse config, load theme, set up input and Wayland.
pub fn init(app: *App, argc: c_int, argv: [*c][*c]u8) bool {
    const cfg: *config.Config = @ptrCast(&app.config);
    config.initDefaults(cfg);
    if (!config.parse(cfg, argc, argv)) return false;
    if (cfg.exit_after_parse) return true;

    _ = theme.init(&app.theme, app.config.key_svg_path);

    if (!input.init(&app.input, app)) return false;
    if (!wl.init(&app.wayland, app)) return false;

    return true;
}

/// Main event loop: poll input and Wayland fds, dispatch events,
/// handle key expiry.
pub fn run(app: *App) c_int {
    if (app.config.exit_after_parse) return app.config.exit_code;

    var pollfds = [_]c.struct_pollfd{
        .{
            .fd = input.getFd(&app.input),
            .events = c.POLLIN,
            .revents = 0,
        },
        .{
            .fd = wl.getFd(&app.wayland),
            .events = c.POLLIN,
            .revents = 0,
        },
    };

    app.run = true;
    while (app.run) {
        errno.set(0);
        while (true) {
            if (wl.flush(&app.wayland) == -1) {
                std.log.err("wl_display_flush: {s}", .{errno.strerror()});
                break;
            }
            if (!errno.isAgain()) break;
        }
        if (errno.get() != 0 and !errno.isAgain()) break;

        const timeout: c_int = if (app.keys.head != null) 100 else -1;

        if (c.poll(&pollfds, pollfds.len, timeout) < 0) {
            std.log.err("poll: {s}", .{errno.strerror()});
            break;
        }

        if ((pollfds[0].revents & c.POLLIN) != 0) {
            if (c.libinput_dispatch(app.input.libinput) != 0) {
                std.log.err("libinput_dispatch: {s}", .{errno.strerror()});
                break;
            }
            var input_dirty = false;
            while (c.libinput_get_event(app.input.libinput)) |event| {
                input.handleEvent(app, event, &input_dirty);
                c.libinput_event_destroy(event);
            }
            if (input_dirty) wl.setDirty(app);
        }

        if ((pollfds[1].revents & c.POLLIN) != 0 and
            wl.dispatch(&app.wayland, app) == -1)
        {
            std.log.err("wl_display_dispatch: {s}", .{errno.strerror()});
            break;
        }

        var now: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
        const key_list: *KeyList = @ptrCast(&app.keys);
        if (key_list.expired(@intCast(app.config.timeout), .{
            .tv_sec = now.tv_sec,
            .tv_nsec = now.tv_nsec,
        })) {
            key_list.clear();
            wl.setDirty(app);
        }
    }
    return 0;
}

/// Release all resources and shut down.
pub fn finish(app: ?*App) void {
    const state = app orelse return;

    const key_list: *KeyList = @ptrCast(&state.keys);
    key_list.clear();
    theme.finish(&state.theme);
    input.finish(&state.input);
    wl.finish(&state.wayland);
    devmgr.finish(state.devmgr, state.devmgr_pid);
    std.heap.page_allocator.destroy(state);

    keys.deinitModule();
}
