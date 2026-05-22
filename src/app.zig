const std = @import("std");
const c = @import("c");
const types = @import("types.zig");
const keys = @import("keys.zig");
const events = @import("event.zig");
const module = @import("module.zig");
const config = @import("config.zig");
const input_raw = @import("input.zig");
const input_mod = @import("input_mod.zig");
const theme = @import("theme.zig");
const devmgr = @import("devmgr.zig");
const wl = @import("wayland.zig");
const wl_mod = @import("wayland");
const errno = @import("errno.zig");
const timerfd = @import("timerfd.zig");
const render_mod_module = @import("render_mod.zig");
const keycap = @import("keycap.zig");

const App = types.App;
const KeyList = keys.KeyList;
const InputModule = input_mod.InputModule;

// ---------------------------------------------------------------------------
// Timer configuration constants
// ---------------------------------------------------------------------------

/// Timerfd fires every 16 ms (≈ 60 fps) while animations are active.
const anim_timer_ms: u64 = 16;

/// Timerfd fires every 100 ms when keys are visible but idle, for
/// expiration checks.
const idle_timer_ms: u64 = 100;

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

// ---------------------------------------------------------------------------
// Event handlers — called by EventBus on every published event.
// Each handler checks the event tag and reacts as needed.
// ---------------------------------------------------------------------------

/// App module event handler — manages key lifecycle and render scheduling.
fn appEventHandler(ctx: *anyopaque, event: events.Event) void {
    const app: *App = @ptrCast(@alignCast(ctx));

    switch (event) {
        .key_pressed => |keypress| {
            appendKeypressToApp(app, keypress);
            armExpiryTimer(app);
        },
        .pointer_button => |name| {
            appendPointerEventToApp(app, name);
            armExpiryTimer(app);
        },
        .pointer_scroll => |direction| {
            appendScrollEventToApp(app, direction);
            armExpiryTimer(app);
        },
        .tick => |t| {
            handleTick(app, t.now_ns);
        },
        .key_expired => {
            const key_list: *KeyList = @ptrCast(&app.keys);
            key_list.clear();
            disarmExpiryTimer(app);
            requestRender(app);
        },
        .quit => {
            app.run = false;
        },
        else => {},
    }
}

/// Input module event handler — subscribes to keymap_updated.
fn inputModEventHandler(ctx: *anyopaque, event: events.Event) void {
    const app: *App = @ptrCast(@alignCast(ctx));

    switch (event) {
        .keymap_updated => |ev| {
            app.input_mod.setKeymapFromFd(ev.format, ev.fd, ev.size);
        },
        else => {},
    }
}

/// Wayland module event handler — reacts to Wayland lifecycle events.
fn waylandModEventHandler(ctx: *anyopaque, event: events.Event) void {
    const app: *App = @ptrCast(@alignCast(ctx));

    switch (event) {
        .layer_configured => |ev| {
            app.wayland.width = ev.width;
            app.wayland.height = ev.height;
            requestRender(app);
        },
        .layer_closed => {
            app.run = false;
        },
        .surface_entered_output => |output| {
            updateCurrentOutput(app, output);
            requestRender(app);
        },
        .quit => {
            app.run = false;
        },
        else => {},
    }
}

/// Render module event handler — dispatches render lifecycle events.
fn renderModEventHandler(ctx: *anyopaque, event: events.Event) void {
    render_mod_module.handleEvent(ctx, event);
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

/// Initialise the app: parse config, load theme, set up input and Wayland.
pub fn init(app: *App, argc: c_int, argv: [*c][*c]u8) bool {
    const cfg: *config.Config = @ptrCast(&app.config);
    config.initDefaults(cfg);
    if (!config.parse(cfg, argc, argv)) return false;
    if (cfg.exit_after_parse) return true;

    // ── Register modules on the event bus ────────────────────────────
    app.event_bus.subscribe(.app_mod, app, appEventHandler);
    app.event_bus.subscribe(.input_mod, app, inputModEventHandler);
    app.event_bus.subscribe(.wayland_mod, app, waylandModEventHandler);
    app.event_bus.subscribe(.render_mod, app, renderModEventHandler);

    // ── Initialise sub-modules ───────────────────────────────────────
    app.wayland_mod.init(&app.event_bus);

    _ = theme.init(&app.theme, app.config.key_svg_path);

    // ── Initialise the input module ──────────────────────────────────
    if (!app.input_mod.init(&app.event_bus)) return false;

    // ── Create the libinput udev context ─────────────────────────────
    app.input_mod_libinput = input_raw.createUdevContext(&app.devmgr);
    if (app.input_mod_libinput == null) return false;

    if (!wl.init(&app.wayland, app)) return false;

    // Assign the libinput seat after Wayland has been initialised
    // (the compositor may have seat information available).
    if (!input_raw.assignSeat(app.input_mod_libinput)) return false;

    // ── Create the animation/expiry timerfd ──────────────────────────
    app.timer_fd = timerfd.create();
    if (app.timer_fd < 0) {
        std.log.err("timerfd_create failed", .{});
        return false;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Main event loop
// ---------------------------------------------------------------------------

/// Main event loop: poll input, Wayland, and timer fds; dispatch events.
pub fn run(app: *App) c_int {
    if (app.config.exit_after_parse) return app.config.exit_code;

    var pollfds = [_]c.struct_pollfd{
        .{
            .fd = input_raw.getFd(app.input_mod_libinput),
            .events = c.POLLIN,
            .revents = 0,
        },
        .{
            .fd = wl.getFd(&app.wayland),
            .events = c.POLLIN,
            .revents = 0,
        },
        .{
            .fd = app.timer_fd,
            .events = c.POLLIN,
            .revents = 0,
        },
    };

    app.run = true;
    while (app.run) {
        // ── Flush Wayland display before blocking ────────────────────
        while (true) {
            errno.set(0);
            if (wl.flush(&app.wayland) == -1) {
                std.log.err("wl_display_flush: {s}", .{errno.strerror()});
                break;
            }
            if (!errno.isAgain()) break;
        }
        if (errno.get() != 0 and !errno.isAgain()) break;

        // Determine poll timeout: we rely on timerfd for timing, so
        // the poll can block indefinitely (timerfd will wake us up).
        const timeout: c_int = -1;

        if (c.poll(&pollfds, pollfds.len, timeout) < 0) {
            std.log.err("poll: {s}", .{errno.strerror()});
            break;
        }

        // ── Dispatch libinput events ─────────────────────────────────
        if ((pollfds[0].revents & c.POLLIN) != 0) {
            if (input_raw.dispatch(app.input_mod_libinput) != 0) {
                std.log.err("libinput_dispatch failed", .{});
                break;
            }
            while (input_raw.getEvent(app.input_mod_libinput)) |event| {
                app.input_mod.handleEvent(event);
                input_raw.destroyEvent(event);
            }
        }

        // ── Dispatch Wayland events ──────────────────────────────────
        if ((pollfds[1].revents & c.POLLIN) != 0) {
            if (wl.dispatch(&app.wayland, app) == -1) {
                std.log.err("wl_display_dispatch failed", .{});
                break;
            }
        }

        // ── Dispatch timer events ────────────────────────────────────
        if ((pollfds[2].revents & c.POLLIN) != 0) {
            const expirations = timerfd.readExpirations(app.timer_fd);
            if (expirations > 0) {
                // Read the current monotonic time for event subscribers.
                var now_ts: c.struct_timespec = undefined;
                _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now_ts);
                const now_ns = @as(i64, @intCast(now_ts.tv_sec)) * 1_000_000_000 + @as(i64, @intCast(now_ts.tv_nsec));

                // Publish tick event — subscribers will handle animation
                // progression, expiry checks, and render scheduling.
                app.event_bus.publish(.{ .tick = .{ .now_ns = now_ns } });
            }
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

/// Release all resources and shut down.
pub fn finish(app: ?*App) void {
    const state = app orelse return;

    // Close the timerfd.
    if (state.timer_fd >= 0) {
        timerfd.close(state.timer_fd);
    }

    const key_list: *KeyList = @ptrCast(&state.keys);
    key_list.clear();
    theme.finish(&state.theme);
    state.input_mod.finish(state.input_mod_libinput);
    wl.finish(&state.wayland);
    devmgr.finish(state.devmgr, state.devmgr_pid);
    std.heap.page_allocator.destroy(state);

    keys.deinitModule();
}

// ---------------------------------------------------------------------------
// Internal helpers — key list management, timer arming, render triggering
// ---------------------------------------------------------------------------

/// Handle a tick event: advance animations and check for key expiry.
fn handleTick(app: *App, now_ns: i64) void {
    const anim_dur_ns: i64 = @as(i64, @intCast(app.config.anim_duration)) * 1_000_000;
    const key_list: *KeyList = @ptrCast(&app.keys);

    if (key_list.head == null) {
        // No keys — disarm the timer and return.
        timerfd.disarm(app.timer_fd);
        return;
    }

    // Check for key expiry first.
    var now_ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now_ts);
    const now_key_ts = keys.TimeSpec{
        .tv_sec = now_ts.tv_sec,
        .tv_nsec = now_ts.tv_nsec,
    };
    if (key_list.expired(@intCast(app.config.timeout), now_key_ts)) {
        app.event_bus.publish(.key_expired);
        return;
    }

    // Tick animation state machine so entering keys become visible
    // once their duration has elapsed.
    key_list.tickAnimations(anim_dur_ns, now_ns);

    // Check if any entry animation is still in progress.
    const has_anim = key_list.hasActiveAnimation(anim_dur_ns, now_ns) or keycap.shift_active;

    // Check if we need to schedule a render for animation continuation.
    if (has_anim and app.wayland.layer_configured and app.wayland.surface != null) {
        requestRender(app);
    }

    // Re-arm the timer with the appropriate interval.
    rearmTimer(app, has_anim, key_list.head != null);
}

/// Re-arm the timerfd with the appropriate interval based on current state.
fn rearmTimer(app: *App, has_anim: bool, has_keys: bool) void {
    const interval_ns: u64 = if (has_anim)
        anim_timer_ms * 1_000_000
    else if (has_keys)
        idle_timer_ms * 1_000_000
    else
        0; // Disarm when idle.

    if (interval_ns == 0) {
        timerfd.disarm(app.timer_fd);
    } else {
        timerfd.setInterval(app.timer_fd, interval_ns);
    }
}

/// Arm the animation timer (fires at 60 fps for smooth entry animation,
/// then switches to idle interval for expiry checks).
/// Called each time a new keypress is registered.
fn armExpiryTimer(app: *App) void {
    // Start with the animation interval so entry animation runs smoothly.
    // After the animation completes, `handleTick` / `rearmTimer` will
    // switch to idle_timer_ms for expiration checking.
    timerfd.setInterval(app.timer_fd, anim_timer_ms * 1_000_000);
}

/// Disarm the expiry timer (called when keys are cleared).
fn disarmExpiryTimer(app: *App) void {
    timerfd.disarm(app.timer_fd);
}

/// Append a keypress to the app's key list, set timestamps, and
/// request a render.
fn appendKeypressToApp(app: *App, keypress: *keys.Keypress) void {
    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    const now_ns = @as(i64, @intCast(now.tv_sec)) * 1_000_000_000 + @as(i64, @intCast(now.tv_nsec));
    keypress.anim_state = .entering;
    keypress.anim_start_ns = now_ns;
    const key_list: *KeyList = @ptrCast(&app.keys);
    key_list.append(keypress, @intCast(app.config.max_keys), .{
        .tv_sec = now.tv_sec,
        .tv_nsec = now.tv_nsec,
    });
    requestRender(app);
}

/// Create a keypress for a pointer event and append it.
fn appendPointerEventToApp(app: *App, name: []const u8) void {
    const keypress = keys.KeyList.createKeypress() catch return;
    keypress.* = .{ .sym = @intCast(c.XKB_KEY_NoSymbol) };
    const copy_len = @min(name.len, keypress.name.len - 1);
    @memcpy(keypress.name[0..copy_len], name[0..copy_len]);
    keypress.name[copy_len] = 0;
    keypress.utf8[0] = 0;
    appendKeypressToApp(app, keypress);
}

/// Create a keypress for a scroll event and append it.
fn appendScrollEventToApp(app: *App, direction: events.ScrollDirection) void {
    const name = switch (direction) {
        .up => "Mouse Wheel Up",
        .down => "Mouse Wheel Down",
        .left => "Mouse Wheel Left",
        .right => "Mouse Wheel Right",
    };
    appendPointerEventToApp(app, name);
}

/// Request a render via the event bus.
/// If the layer surface has not been configured yet, also request
/// a configure round-trip from the compositor.
fn requestRender(app: *App) void {
    if (!app.wayland.layer_configured) {
        wl.requestLayerConfigure(app);
    }
    app.event_bus.publish(.request_render);
}

/// Update the current output pointer when the surface enters an output.
fn updateCurrentOutput(app: *App, entered_output: ?*anyopaque) void {
    const wayland = &app.wayland;
    const wl_output_ptr: ?*wl_mod.client.wl.Output = @ptrCast(@alignCast(entered_output));
    var wsk_output = wayland.outputs;
    while (wsk_output) |candidate| {
        if (candidate.output == wl_output_ptr) {
            wayland.output = candidate;
            return;
        }
        wsk_output = candidate.next;
    }
}
