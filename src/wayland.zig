const std = @import("std");

const c = @import("c");

fn layerSurfaceConfigure(data: ?*anyopaque, surface: ?*c.struct_zwlr_layer_surface_v1, serial: u32, width: u32, height: u32) callconv(.c) void {
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    const wayland = &app.wayland;
    wayland.width = width;
    wayland.height = height;
    wayland.layer_configured = true;
    wayland.layer_pending_configure = false;
    c.zwlr_layer_surface_v1_ack_configure(surface, serial);
    wsk_wayland_set_dirty(app);
}

fn layerSurfaceClosed(data: ?*anyopaque, surface: ?*c.struct_zwlr_layer_surface_v1) callconv(.c) void {
    _ = surface;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    app.run = false;
}

fn surfaceEnter(data: ?*anyopaque, surface: ?*c.struct_wl_surface, output: ?*c.struct_wl_output) callconv(.c) void {
    _ = surface;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    const wayland = &app.wayland;
    var wsk_output = wayland.outputs;
    while (wsk_output) |candidate| {
        if (candidate[0].output == output) {
            wayland.output = candidate;
            wsk_wayland_set_dirty(app);
            return;
        }
        wsk_output = candidate[0].next;
    }
}

fn surfaceLeave(data: ?*anyopaque, surface: ?*c.struct_wl_surface, output: ?*c.struct_wl_output) callconv(.c) void {
    _ = data;
    _ = surface;
    _ = output;
}

fn keyboardKeymap(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    _ = keyboard;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    c.wsk_input_set_keymap_from_fd(&app.input, format, fd, size);
}

fn keyboardEnter(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, serial: u32, surface: ?*c.struct_wl_surface, keys: [*c]c.struct_wl_array) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
    _ = keys;
}

fn keyboardLeave(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, serial: u32, surface: ?*c.struct_wl_surface) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = surface;
}

fn keyboardKey(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, serial: u32, time: u32, key: u32, state: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = time;
    _ = key;
    _ = state;
}

fn keyboardModifiers(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, serial: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = serial;
    _ = mods_depressed;
    _ = mods_latched;
    _ = mods_locked;
    _ = group;
}

fn keyboardRepeatInfo(data: ?*anyopaque, keyboard: ?*c.struct_wl_keyboard, rate: i32, delay: i32) callconv(.c) void {
    _ = data;
    _ = keyboard;
    _ = rate;
    _ = delay;
}

fn frameDone(data: ?*anyopaque, callback: ?*c.struct_wl_callback, callback_data: u32) callconv(.c) void {
    _ = callback_data;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    const wayland = &app.wayland;

    c.wl_callback_destroy(callback);
    wayland.frame_callback = null;
    wayland.frame_scheduled = false;

    if (wayland.dirty and wayland.layer_configured and wayland.surface != null) {
        wayland.dirty = false;
        c.wsk_render_frame(app);
    }
}

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.struct_wl_seat, capabilities: u32) callconv(.c) void {
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    const wayland = &app.wayland;
    if (wayland.keyboard != null) {
        return;
    }

    if ((capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD) == 0) {
        _ = c.fprintf(c.stderr, "wl_seat does not support keyboard");
        app.run = false;
        return;
    }

    wayland.keyboard = c.wl_seat_get_keyboard(seat);
    _ = c.wl_keyboard_add_listener(wayland.keyboard, &keyboard_listener, app);
}

fn seatName(data: ?*anyopaque, seat: ?*c.struct_wl_seat, name: [*c]const u8) callconv(.c) void {
    _ = seat;
    _ = name;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    if (c.libinput_udev_assign_seat(app.input.libinput, "seat0") != 0) {
        _ = c.fprintf(c.stderr, "Failed to assign libinput seat\n");
        app.run = false;
    }
}

fn outputGeometry(data: ?*anyopaque, output: ?*c.struct_wl_output, x: i32, y: i32, physical_width: i32, physical_height: i32, subpixel: i32, make: [*c]const u8, model: [*c]const u8, transform: i32) callconv(.c) void {
    _ = output;
    _ = x;
    _ = y;
    _ = physical_width;
    _ = physical_height;
    _ = make;
    _ = model;
    _ = transform;
    const wsk_output: *c.struct_wsk_output = @ptrCast(@alignCast(data.?));
    wsk_output.subpixel = @intCast(subpixel);
}

fn outputMode(data: ?*anyopaque, output: ?*c.struct_wl_output, flags: u32, width: i32, height: i32, refresh: i32) callconv(.c) void {
    _ = data;
    _ = output;
    _ = flags;
    _ = width;
    _ = height;
    _ = refresh;
}

fn outputDone(data: ?*anyopaque, output: ?*c.struct_wl_output) callconv(.c) void {
    _ = data;
    _ = output;
}

fn outputScale(data: ?*anyopaque, output: ?*c.struct_wl_output, factor: i32) callconv(.c) void {
    _ = output;
    const wsk_output: *c.struct_wsk_output = @ptrCast(@alignCast(data.?));
    wsk_output.scale = factor;
}

fn bindGlobal(comptime T: type, registry: ?*c.struct_wl_registry, name: u32, interface: [*c]const c.struct_wl_interface, version: u32) ?*T {
    return @ptrCast(@alignCast(c.wl_registry_bind(registry, name, interface, version)));
}

fn registryGlobal(data: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    _ = version;
    const app: *c.struct_wsk_app = @ptrCast(@alignCast(data.?));
    const wayland = &app.wayland;
    if (c.strcmp(interface, c.wl_compositor_interface.name) == 0) {
        wayland.compositor = bindGlobal(c.struct_wl_compositor, registry, name, &c.wl_compositor_interface, 4);
    } else if (c.strcmp(interface, c.wl_shm_interface.name) == 0) {
        wayland.shm = bindGlobal(c.struct_wl_shm, registry, name, &c.wl_shm_interface, 1);
    } else if (c.strcmp(interface, c.wl_seat_interface.name) == 0) {
        wayland.seat = bindGlobal(c.struct_wl_seat, registry, name, &c.wl_seat_interface, 5);
    } else if (c.strcmp(interface, c.zxdg_output_manager_v1_interface.name) == 0) {
        wayland.output_mgr = bindGlobal(c.struct_zxdg_output_manager_v1, registry, name, &c.zxdg_output_manager_v1_interface, 1);
    } else if (c.strcmp(interface, c.zwlr_layer_shell_v1_interface.name) == 0) {
        wayland.layer_shell = bindGlobal(c.struct_zwlr_layer_shell_v1, registry, name, &c.zwlr_layer_shell_v1_interface, 1);
    } else if (c.strcmp(interface, c.wl_output_interface.name) == 0) {
        const allocation = c.calloc(1, @sizeOf(c.struct_wsk_output));
        std.debug.assert(allocation != null);
        const output: *c.struct_wsk_output = @ptrCast(@alignCast(allocation.?));
        output.output = bindGlobal(c.struct_wl_output, registry, name, &c.wl_output_interface, 3);
        output.scale = 1;
        if (wayland.outputs) |first| {
            var tail = first;
            while (tail[0].next) |next| {
                tail = next;
            }
            tail[0].next = output;
        } else {
            wayland.outputs = output;
        }
        _ = c.wl_output_add_listener(output.output, &output_listener, output);
    }
}

fn registryGlobalRemove(data: ?*anyopaque, registry: ?*c.struct_wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

const layer_surface_listener: c.struct_zwlr_layer_surface_v1_listener = .{
    .configure = layerSurfaceConfigure,
    .closed = layerSurfaceClosed,
};

const surface_listener: c.struct_wl_surface_listener = .{
    .enter = surfaceEnter,
    .leave = surfaceLeave,
};

export const frame_listener: c.struct_wl_callback_listener = .{
    .done = frameDone,
};

const keyboard_listener: c.struct_wl_keyboard_listener = .{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};

const seat_listener: c.struct_wl_seat_listener = .{
    .capabilities = seatCapabilities,
    .name = seatName,
};

const output_listener: c.struct_wl_output_listener = .{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
};

const registry_listener: c.struct_wl_registry_listener = .{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

export fn wsk_wayland_destroy_layer_surface(wayland: *c.struct_wsk_wayland) void {
    if (wayland.frame_callback) |callback| {
        c.wl_callback_destroy(callback);
        wayland.frame_callback = null;
    }
    wayland.frame_scheduled = false;
    if (wayland.layer_surface) |layer_surface| {
        c.zwlr_layer_surface_v1_destroy(layer_surface);
        wayland.layer_surface = null;
    }
    if (wayland.surface) |surface| {
        c.wl_surface_destroy(surface);
        wayland.surface = null;
    }
    wayland.output = null;
    wayland.width = 0;
    wayland.height = 0;
    wayland.layer_configured = false;
    wayland.layer_pending_configure = false;
}

export fn wsk_wayland_create_layer_surface(app: *c.struct_wsk_app) bool {
    const wayland = &app.wayland;
    if (wayland.surface != null) {
        return true;
    }

    wayland.surface = c.wl_compositor_create_surface(wayland.compositor);
    if (wayland.surface == null) {
        return false;
    }
    _ = c.wl_surface_add_listener(wayland.surface, &surface_listener, app);

    wayland.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(
        wayland.layer_shell,
        wayland.surface,
        null,
        c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
        "showkeys",
    );
    if (wayland.layer_surface == null) {
        wsk_wayland_destroy_layer_surface(wayland);
        wayland.surface = null;
        return false;
    }
    _ = c.zwlr_layer_surface_v1_add_listener(wayland.layer_surface, &layer_surface_listener, app);
    c.zwlr_layer_surface_v1_set_keyboard_interactivity(
        wayland.layer_surface,
        c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE,
    );
    return true;
}

export fn wsk_wayland_request_layer_configure(app: *c.struct_wsk_app) void {
    const wayland = &app.wayland;
    if (wayland.layer_pending_configure or app.keys.head == null) {
        return;
    }
    if (!wsk_wayland_create_layer_surface(app)) {
        return;
    }

    c.zwlr_layer_surface_v1_set_size(wayland.layer_surface, 1, 1);
    c.zwlr_layer_surface_v1_set_anchor(wayland.layer_surface, app.config.anchor);
    c.zwlr_layer_surface_v1_set_margin(
        wayland.layer_surface,
        app.config.margin,
        app.config.margin,
        app.config.margin,
        app.config.margin,
    );
    c.zwlr_layer_surface_v1_set_exclusive_zone(wayland.layer_surface, -1);
    c.wl_surface_commit(wayland.surface);
    wayland.layer_pending_configure = true;
}

export fn wsk_wayland_set_dirty(app: *c.struct_wsk_app) void {
    const wayland = &app.wayland;
    if (wayland.frame_scheduled or wayland.layer_pending_configure or !wayland.layer_configured) {
        wayland.dirty = true;
        if (!wayland.layer_configured) {
            wsk_wayland_request_layer_configure(app);
        }
    } else if (wayland.surface != null) {
        wayland.dirty = false;
        c.wsk_render_frame(app);
    }
}

export fn wsk_wayland_init(wayland: *c.struct_wsk_wayland, app: *c.struct_wsk_app) bool {
    wayland.* = std.mem.zeroes(c.struct_wsk_wayland);

    wayland.display = c.wl_display_connect(null);
    if (wayland.display == null) {
        _ = c.fprintf(c.stderr, "wl_display_connect: %s\n", c.strerror(std.c._errno().*));
        return false;
    }

    wayland.registry = c.wl_display_get_registry(wayland.display);
    std.debug.assert(wayland.registry != null);
    _ = c.wl_registry_add_listener(wayland.registry, &registry_listener, app);
    _ = c.wl_display_roundtrip(wayland.display);

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
        _ = c.fprintf(c.stderr, "Error: required Wayland interface '%s' is not present\n", name);
        return false;
    }

    _ = c.wl_seat_add_listener(wayland.seat, &seat_listener, app);
    _ = c.wl_display_roundtrip(wayland.display);
    return true;
}

export fn wsk_wayland_finish(wayland: *c.struct_wsk_wayland) void {
    wsk_wayland_destroy_layer_surface(wayland);
    var output = wayland.outputs;
    while (output) |current| {
        const next = current[0].next;
        if (current[0].output) |wl_output| {
            c.wl_output_destroy(wl_output);
        }
        c.free(current);
        output = next;
    }
    if (wayland.display) |display| {
        c.wl_display_disconnect(display);
    }
}

export fn wsk_wayland_get_fd(wayland: *c.struct_wsk_wayland) c_int {
    return c.wl_display_get_fd(wayland.display);
}

export fn wsk_wayland_dispatch(wayland: *c.struct_wsk_wayland, app: *c.struct_wsk_app) c_int {
    _ = app;
    return c.wl_display_dispatch(wayland.display);
}

export fn wsk_wayland_flush(wayland: *c.struct_wsk_wayland) c_int {
    const ret = c.wl_display_flush(wayland.display);
    if (ret == -1 and std.c._errno().* != c.EAGAIN) {
        return -1;
    }
    return 0;
}
