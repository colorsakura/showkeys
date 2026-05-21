const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const types = @import("types.zig");
const input = @import("input.zig");
const render_mod = @import("render.zig");

const wl = wl_mod.client.wl;
const zwlr = wl_mod.client.zwlr;
const zxdg = wl_mod.client.zxdg;

const App = types.App;
const Wayland = types.Wayland;
const WskOutput = types.Output;

/// Arena allocator for `WskOutput` nodes.
var output_arena: std.heap.ArenaAllocator = undefined;
var output_arena_initialized = false;

fn ensureOutputArena() void {
    if (!output_arena_initialized) {
        output_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        output_arena_initialized = true;
    }
}

fn deinitOutputArena() void {
    if (output_arena_initialized) {
        output_arena.deinit();
        output_arena_initialized = false;
    }
}

// ---------------------------------------------------------------------------
// Layer surface listener
// ---------------------------------------------------------------------------

fn layerSurfaceListener(ls: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, data: *App) void {
    switch (event) {
        .configure => |ev| {
            const wayland = &data.wayland;
            wayland.width = ev.width;
            wayland.height = ev.height;
            wayland.layer_configured = true;
            wayland.layer_pending_configure = false;
            ls.ackConfigure(ev.serial);
            setDirty(data);
        },
        .closed => {
            data.run = false;
        },
    }
}

// ---------------------------------------------------------------------------
// Surface listener
// ---------------------------------------------------------------------------

fn surfaceListener(surface: *wl.Surface, event: wl.Surface.Event, data: *App) void {
    switch (event) {
        .enter => |ev| {
            const wayland = &data.wayland;
            var wsk_output = wayland.outputs;
            while (wsk_output) |candidate| {
                if (candidate.output == ev.output) {
                    wayland.output = candidate;
                    setDirty(data);
                    return;
                }
                wsk_output = candidate.next;
            }
        },
        .leave => {},
    }
    _ = surface;
}

// ---------------------------------------------------------------------------
// Keyboard listener
// ---------------------------------------------------------------------------

fn keyboardListener(kb: *wl.Keyboard, event: wl.Keyboard.Event, data: *App) void {
    switch (event) {
        .keymap => |ev| {
            input.setKeymapFromFd(&data.input, @intCast(@intFromEnum(ev.format)), ev.fd, ev.size);
        },
        .enter => {},
        .leave => {},
        .key => {},
        .modifiers => {},
        .repeat_info => {},
    }
    _ = kb;
}

// ---------------------------------------------------------------------------
// Seat listener
// ---------------------------------------------------------------------------

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, data: *App) void {
    switch (event) {
        .capabilities => |ev| {
            const wayland = &data.wayland;
            if (wayland.keyboard != null) return;

            if (!ev.capabilities.keyboard) {
                std.log.err("wl_seat does not support keyboard", .{});
                data.run = false;
                return;
            }

            wayland.keyboard = seat.getKeyboard() catch return;
            wayland.keyboard.?.setListener(*App, keyboardListener, data);
        },
        .name => {
            if (c.libinput_udev_assign_seat(data.input.libinput, "seat0") != 0) {
                std.log.err("Failed to assign libinput seat", .{});
                data.run = false;
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Output listener
// ---------------------------------------------------------------------------

fn outputListener(output: *wl.Output, event: wl.Output.Event, data: *WskOutput) void {
    switch (event) {
        .geometry => |ev| {
            data.subpixel = @intFromEnum(ev.subpixel);
        },
        .mode => {},
        .done => {},
        .scale => |ev| {
            data.scale = ev.factor;
        },
    }
    _ = output;
}

// ---------------------------------------------------------------------------
// Registry listener
// ---------------------------------------------------------------------------

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, data: *App) void {
    switch (event) {
        .global => |ev| {
            const wayland = &data.wayland;
            const iface = std.mem.sliceTo(ev.interface, 0);

            if (std.mem.eql(u8, iface, std.mem.sliceTo(wl.Compositor.interface.name, 0))) {
                wayland.compositor = registry.bind(ev.name, wl.Compositor, ev.version) catch return;
            } else if (std.mem.eql(u8, iface, std.mem.sliceTo(wl.Shm.interface.name, 0))) {
                wayland.shm = registry.bind(ev.name, wl.Shm, ev.version) catch return;
            } else if (std.mem.eql(u8, iface, std.mem.sliceTo(wl.Seat.interface.name, 0))) {
                wayland.seat = registry.bind(ev.name, wl.Seat, ev.version) catch return;
            } else if (std.mem.eql(u8, iface, std.mem.sliceTo(zxdg.OutputManagerV1.interface.name, 0))) {
                wayland.output_mgr = registry.bind(ev.name, zxdg.OutputManagerV1, ev.version) catch return;
            } else if (std.mem.eql(u8, iface, std.mem.sliceTo(zwlr.LayerShellV1.interface.name, 0))) {
                wayland.layer_shell = registry.bind(ev.name, zwlr.LayerShellV1, ev.version) catch return;
            } else if (std.mem.eql(u8, iface, std.mem.sliceTo(wl.Output.interface.name, 0))) {
                ensureOutputArena();
                const output = output_arena.allocator().create(WskOutput) catch return;
                output.* = .{};
                output.output = registry.bind(ev.name, wl.Output, ev.version) catch return;
                output.scale = 1;
                output.output.?.setListener(*WskOutput, outputListener, output);

                if (wayland.outputs) |first| {
                    var tail = first;
                    while (tail.next) |next| {
                        tail = next;
                    }
                    tail.next = output;
                } else {
                    wayland.outputs = output;
                }
            }
        },
        .global_remove => {},
    }
}

// ---------------------------------------------------------------------------
// Display wrappers (errno → c_int)
// ---------------------------------------------------------------------------

fn displayDispatch(display: *wl.Display) c_int {
    const e = display.dispatch();
    return if (@intFromEnum(e) == 0) 0 else -1;
}

fn displayFlush(display: *wl.Display) c_int {
    const e = display.flush();
    return if (@intFromEnum(e) == 0) 0 else -1;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Create the layer surface and register listeners.
fn createLayerSurface(app: *App) bool {
    const wayland = &app.wayland;
    if (wayland.surface != null) return true;

    wayland.surface = wayland.compositor.?.createSurface() catch return false;
    wayland.surface.?.setListener(*App, surfaceListener, app);

    wayland.layer_surface = wayland.layer_shell.?.getLayerSurface(
        wayland.surface.?,
        null,
        .overlay,
        "showkeys",
    ) catch {
        render_mod.destroyLayerSurface(wayland);
        return false;
    };
    wayland.layer_surface.?.setListener(*App, layerSurfaceListener, app);
    wayland.layer_surface.?.setKeyboardInteractivity(.none);
    return true;
}

/// Request a configure round-trip for the layer surface.
fn requestLayerConfigure(app: *App) void {
    const wayland = &app.wayland;
    if (wayland.layer_pending_configure or app.keys.head == null) return;
    if (!createLayerSurface(app)) return;

    wayland.layer_surface.?.setSize(1, 1);
    wayland.layer_surface.?.setAnchor(@as(zwlr.LayerSurfaceV1.Anchor, @bitCast(app.config.anchor)));
    wayland.layer_surface.?.setMargin(
        app.config.margin,
        app.config.margin,
        app.config.margin,
        app.config.margin,
    );
    wayland.layer_surface.?.setExclusiveZone(-1);
    wayland.surface.?.commit();
    wayland.layer_pending_configure = true;
}

/// Mark the app as dirty and schedule a re-render.
pub fn setDirty(app: *App) void {
    const wayland = &app.wayland;
    if (wayland.frame_scheduled or wayland.layer_pending_configure or !wayland.layer_configured) {
        wayland.dirty = true;
        if (!wayland.layer_configured) {
            requestLayerConfigure(app);
        }
    } else if (wayland.surface != null) {
        wayland.dirty = false;
        render_mod.renderFrame(app);
    }
}

/// Initialize the Wayland connection, bind global interfaces, and
/// register the seat listener. Returns true on success.
pub fn init(wayland: *Wayland, app: *App) bool {
    wayland.* = .{};

    wayland.display = wl.Display.connect(null) catch {
        std.log.err("wl_display_connect failed", .{});
        return false;
    };

    wayland.registry = wayland.display.?.getRegistry() catch {
        std.log.err("Failed to get wl_registry", .{});
        return false;
    };
    wayland.registry.?.setListener(*App, registryListener, app);

    _ = wayland.display.?.roundtrip();

    const missing: ?[*:0]const u8 = if (wayland.compositor == null)
        "wl_compositor"
    else if (wayland.shm == null)
        "wl_shm"
    else if (wayland.seat == null)
        "wl_seat"
    else if (wayland.layer_shell == null)
        "wlr_layer_shell"
    else
        null;

    if (missing) |name| {
        std.log.err("Error: required Wayland interface '{s}' is not present", .{std.mem.sliceTo(name, 0)});
        return false;
    }

    wayland.seat.?.setListener(*App, seatListener, app);
    _ = wayland.display.?.roundtrip();
    return true;
}

/// Release all Wayland resources.
pub fn finish(wayland: *Wayland) void {
    render_mod.destroyLayerSurface(wayland);
    var output = wayland.outputs;
    while (output) |current| {
        const next = current.next;
        if (current.output) |wl_output| {
            wl_output.destroy();
        }
        output = next;
    }
    deinitOutputArena();
    if (wayland.display) |display| {
        display.disconnect();
    }
}

/// Get the Wayland display file descriptor for polling.
pub fn getFd(wayland: *Wayland) c_int {
    return wayland.display.?.getFd();
}

/// Dispatch pending Wayland events.
pub fn dispatch(wayland: *Wayland, app: *App) c_int {
    _ = app;
    return displayDispatch(wayland.display.?);
}

/// Flush pending Wayland requests. Returns 0 on success, -1 on error.
pub fn flush(wayland: *Wayland) c_int {
    return displayFlush(wayland.display.?);
}
