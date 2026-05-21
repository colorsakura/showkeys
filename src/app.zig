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

        // Dynamic poll timeout: short (16 ms ≈ 60 fps) when animations
        // are active, 100 ms when keys are visible (for expiration
        // checks), and infinite (-1) when idle.
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now_ts);
        const now_ns = @as(i64, @intCast(now_ts.tv_sec)) * 1_000_000_000 + @as(i64, @intCast(now_ts.tv_nsec));
        const anim_dur_ns: i64 = @as(i64, @intCast(app.config.anim_duration)) * 1_000_000;

        const key_list: *KeyList = @ptrCast(&app.keys);
        const has_anim = key_list.hasActiveAnimation(anim_dur_ns, now_ns);
        const timeout: c_int = if (has_anim) 16 else if (app.keys.head != null) 100 else -1;

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

        // Tick animation state machine so entering keys become visible
        // once their duration has elapsed.
        key_list.tickAnimations(anim_dur_ns, now_ns);

        if (key_list.expired(@intCast(app.config.timeout), .{
            .tv_sec = now_ts.tv_sec,
            .tv_nsec = now_ts.tv_nsec,
        })) {
            key_list.clear();
            wl.setDirty(app);
        }

        // When animations are active, schedule another frame to
        // continue the animation.
        if (has_anim and app.wayland.layer_configured and app.wayland.surface != null) {
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
