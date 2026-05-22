const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const types = @import("types.zig");
const events = @import("event.zig");

const wl = wl_mod.client.wl;
const zwlr = wl_mod.client.zwlr;
const zxdg = wl_mod.client.zxdg;

const App = types.App;
const Wayland = types.Wayland;
const WskOutput = types.WskOutput;

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
// Layer surface listener — publishes events to the bus
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

            // Notify the wayland_mod and others.
            data.wayland_mod.onLayerConfigured(ev.width, ev.height, ev.serial);
        },
        .closed => {
            data.wayland_mod.onLayerClosed();
        },
    }
}

// ---------------------------------------------------------------------------
// Surface listener — publishes events to the bus
// ---------------------------------------------------------------------------

fn surfaceListener(surface: *wl.Surface, event: wl.Surface.Event, data: *App) void {
    switch (event) {
        .enter => |ev| {
            data.wayland_mod.onSurfaceEnteredOutput(ev.output);
        },
        .leave => {},
    }
    _ = surface;
}

// ---------------------------------------------------------------------------
// Keyboard listener — publishes keymap_updated events
// ---------------------------------------------------------------------------

fn keyboardListener(kb: *wl.Keyboard, event: wl.Keyboard.Event, data: *App) void {
    switch (event) {
        .keymap => |ev| {
            data.event_bus.publish(.{
                .keymap_updated = .{
                    .format = @intCast(@intFromEnum(ev.format)),
                    .fd = ev.fd,
                    .size = ev.size,
                },
            });
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
        .name => {},
    }
}

// ---------------------------------------------------------------------------
// Output listener — tracks scale and subpixel for HiDPI
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

/// Destroy the entire layer surface (surface + layer surface + frame callback).
pub fn destroyLayerSurface(wayland: *types.Wayland) void {
    if (wayland.frame_callback) |callback| {
        callback.destroy();
        wayland.frame_callback = null;
    }
    wayland.frame_scheduled = false;
    if (wayland.layer_surface) |layer_surface| {
        layer_surface.destroy();
        wayland.layer_surface = null;
    }
    if (wayland.surface) |surface| {
        surface.destroy();
        wayland.surface = null;
    }
    wayland.output = null;
    wayland.width = 0;
    wayland.height = 0;
    wayland.layer_configured = false;
    wayland.layer_pending_configure = false;
}

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
        destroyLayerSurface(wayland);
        return false;
    };
    wayland.layer_surface.?.setListener(*App, layerSurfaceListener, app);
    wayland.layer_surface.?.setKeyboardInteractivity(.none);
    return true;
}

/// Request a configure round-trip for the layer surface.
pub fn requestLayerConfigure(app: *App) void {
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

/// Errors that can occur during Wayland initialisation.
pub const WaylandError = error{
    DisplayConnectFailed,
    RegistryGetFailed,
    MissingInterface,
};

/// Initialize the Wayland connection, bind global interfaces, and
/// register the seat listener.
pub fn init(wayland: *Wayland, app: *App) WaylandError!void {
    wayland.* = .{};

    wayland.display = wl.Display.connect(null) catch {
        std.log.err("wl_display_connect failed", .{});
        return error.DisplayConnectFailed;
    };

    wayland.registry = wayland.display.?.getRegistry() catch {
        std.log.err("Failed to get wl_registry", .{});
        return error.RegistryGetFailed;
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
        return error.MissingInterface;
    }

    wayland.seat.?.setListener(*App, seatListener, app);
    _ = wayland.display.?.roundtrip();
}

/// Release all Wayland resources.
pub fn finish(wayland: *Wayland) void {
    destroyLayerSurface(wayland);
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
