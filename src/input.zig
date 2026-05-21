const std = @import("std");

const c = @import("c");

fn libinputOpenRestricted(path: [*c]const u8, flags: c_int, data: ?*anyopaque) callconv(.c) c_int {
    _ = flags;
    const fd: *c_int = @ptrCast(@alignCast(data.?));
    return c.devmgr_open(fd.*, path);
}

fn libinputCloseRestricted(fd: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    _ = c.close(fd);
}

const libinput_impl: c.struct_libinput_interface = .{
    .open_restricted = libinputOpenRestricted,
    .close_restricted = libinputCloseRestricted,
};

export fn wsk_input_init(input: *c.struct_wsk_input, app: *c.struct_wsk_app) bool {
    input.* = std.mem.zeroes(c.struct_wsk_input);

    input.udev = c.udev_new();
    if (input.udev == null) {
        _ = c.fprintf(c.stderr, "udev_create: %s\n", c.strerror(std.c._errno().*));
        return false;
    }

    input.libinput = c.libinput_udev_create_context(&libinput_impl, &app.devmgr, input.udev);
    if (input.libinput == null) {
        _ = c.fprintf(c.stderr, "libinput_udev_create_context: %s\n", c.strerror(std.c._errno().*));
        _ = c.udev_unref(input.udev);
        input.udev = null;
        return false;
    }
    _ = c.udev_unref(input.udev);
    input.udev = null;

    input.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (input.xkb_context == null) {
        _ = c.fprintf(c.stderr, "xkb_context_new: %s\n", c.strerror(std.c._errno().*));
        return false;
    }

    return true;
}

export fn wsk_input_finish(input: *c.struct_wsk_input) void {
    if (input.libinput) |libinput| {
        _ = c.libinput_unref(libinput);
    }
    if (input.xkb_context) |xkb_context| {
        c.xkb_context_unref(xkb_context);
    }
    if (input.xkb_keymap) |xkb_keymap| {
        c.xkb_keymap_unref(xkb_keymap);
    }
    if (input.xkb_state) |xkb_state| {
        c.xkb_state_unref(xkb_state);
    }
}

export fn wsk_input_get_fd(input: *c.struct_wsk_input) c_int {
    return c.libinput_get_fd(input.libinput);
}

fn pointerButtonName(button: u32) ?[*:0]const u8 {
    return switch (button) {
        c.BTN_LEFT => "Mouse Left",
        c.BTN_RIGHT => "Mouse Right",
        c.BTN_MIDDLE => "Mouse Middle",
        c.BTN_SIDE => "Mouse Side",
        c.BTN_EXTRA => "Mouse Extra",
        c.BTN_FORWARD => "Mouse Forward",
        c.BTN_BACK => "Mouse Back",
        else => null,
    };
}

fn allocKeypress() *c.struct_wsk_keypress {
    const allocation = c.calloc(1, @sizeOf(c.struct_wsk_keypress));
    std.debug.assert(allocation != null);
    return @ptrCast(@alignCast(allocation.?));
}

fn handleKeyboardKeyEvent(app: *c.struct_wsk_app, kbevent: ?*c.struct_libinput_event_keyboard, dirty: *bool) void {
    const input = &app.input;
    if (input.xkb_state == null) {
        return;
    }

    const keycode: u32 = c.libinput_event_keyboard_get_key(kbevent) + 8;
    const key_state = c.libinput_event_keyboard_get_key_state(kbevent);
    _ = c.xkb_state_update_key(
        input.xkb_state,
        keycode,
        if (key_state == c.LIBINPUT_KEY_STATE_RELEASED) c.XKB_KEY_UP else c.XKB_KEY_DOWN,
    );

    const keysym = c.xkb_state_key_get_one_sym(input.xkb_state, keycode);

    switch (key_state) {
        c.LIBINPUT_KEY_STATE_RELEASED => {},
        c.LIBINPUT_KEY_STATE_PRESSED => {
            const keypress = allocKeypress();
            keypress.sym = keysym;
            _ = c.xkb_keysym_get_name(keypress.sym, @ptrCast(&keypress.name), keypress.name.len);
            if (c.xkb_state_key_get_utf8(input.xkb_state, keycode, @ptrCast(&keypress.utf8), keypress.utf8.len) <= 0 or keypress.utf8[0] <= ' ') {
                keypress.utf8[0] = 0;
            }
            var now: c.struct_timespec = undefined;
            _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
            c.wsk_keys_append(&app.keys, keypress, app.config.max_keys, &now);
            dirty.* = true;
        },
        else => {},
    }
}

fn appendPointerEvent(app: *c.struct_wsk_app, name: [*c]const u8, dirty: *bool) void {
    const keypress = allocKeypress();
    keypress.sym = c.XKB_KEY_NoSymbol;
    keypress.utf8[0] = 0;
    _ = c.snprintf(@ptrCast(&keypress.name), keypress.name.len, "%s", name);

    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    c.wsk_keys_append(&app.keys, keypress, app.config.max_keys, &now);
    dirty.* = true;
}

fn handlePointerButtonEvent(app: *c.struct_wsk_app, pevent: ?*c.struct_libinput_event_pointer, dirty: *bool) void {
    const button_state = c.libinput_event_pointer_get_button_state(pevent);
    if (button_state != c.LIBINPUT_BUTTON_STATE_PRESSED) {
        return;
    }

    const button = c.libinput_event_pointer_get_button(pevent);
    var fallback_name: [32]u8 = undefined;
    const name: [*c]const u8 = if (pointerButtonName(button)) |button_name|
        button_name
    else blk: {
        _ = c.snprintf(@ptrCast(&fallback_name), fallback_name.len, "Mouse 0x%x", button);
        break :blk @ptrCast(&fallback_name);
    };

    appendPointerEvent(app, name, dirty);
}

fn handlePointerScrollWheelEvent(app: *c.struct_wsk_app, pevent: ?*c.struct_libinput_event_pointer, dirty: *bool) void {
    if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL) != 0) {
        const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
        if (value < 0.0) {
            appendPointerEvent(app, "Mouse Wheel Up", dirty);
        } else if (value > 0.0) {
            appendPointerEvent(app, "Mouse Wheel Down", dirty);
        }
    }

    if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL) != 0) {
        const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL);
        if (value < 0.0) {
            appendPointerEvent(app, "Mouse Wheel Left", dirty);
        } else if (value > 0.0) {
            appendPointerEvent(app, "Mouse Wheel Right", dirty);
        }
    }
}

export fn wsk_input_handle_libinput_event(app: *c.struct_wsk_app, event: ?*c.struct_libinput_event, dirty: *bool) void {
    switch (c.libinput_event_get_type(event)) {
        c.LIBINPUT_EVENT_KEYBOARD_KEY => handleKeyboardKeyEvent(app, c.libinput_event_get_keyboard_event(event), dirty),
        c.LIBINPUT_EVENT_POINTER_BUTTON => handlePointerButtonEvent(app, c.libinput_event_get_pointer_event(event), dirty),
        c.LIBINPUT_EVENT_POINTER_SCROLL_WHEEL => handlePointerScrollWheelEvent(app, c.libinput_event_get_pointer_event(event), dirty),
        else => {},
    }
}

export fn wsk_input_set_keymap(input: *c.struct_wsk_input, keymap: ?*c.struct_xkb_keymap, xkb_state: ?*c.struct_xkb_state) void {
    c.xkb_keymap_unref(input.xkb_keymap);
    c.xkb_state_unref(input.xkb_state);
    input.xkb_keymap = keymap;
    input.xkb_state = xkb_state;
}

export fn wsk_input_set_keymap_from_fd(input: *c.struct_wsk_input, format: u32, fd: i32, size: u32) void {
    const map_shm = c.mmap(null, size, c.PROT_READ, c.MAP_SHARED, fd, 0);
    if (map_shm == c.MAP_FAILED) {
        _ = c.close(fd);
        _ = c.fprintf(c.stderr, "Unable to mmap keymap: %s", c.strerror(std.c._errno().*));
        return;
    }
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        _ = c.munmap(map_shm, size);
        _ = c.close(fd);
        return;
    }

    const keymap = c.xkb_keymap_new_from_string(
        input.xkb_context,
        @ptrCast(map_shm),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );
    _ = c.munmap(map_shm, size);
    _ = c.close(fd);

    const xkb_state = c.xkb_state_new(keymap);
    wsk_input_set_keymap(input, keymap, xkb_state);
}
