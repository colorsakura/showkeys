const std = @import("std");
const c = @import("c");
const keys = @import("keys.zig");
const devmgr = @import("devmgr.zig");

/// Type aliases for C structs, maintaining ABI compatibility.
const Input = c.struct_wsk_input;
const App = c.struct_wsk_app;
const Keypress = c.struct_wsk_keypress;

/// libinput open_restricted callback — delegates to the privileged
/// device manager via the stored file descriptor.
fn libinputOpenRestricted(path: [*c]const u8, flags: c_int, data: ?*anyopaque) callconv(.c) c_int {
    _ = flags;
    const fd: *c_int = @ptrCast(@alignCast(data.?));
    return devmgr.open(fd.*, path);
}

/// libinput close_restricted callback.
fn libinputCloseRestricted(fd: c_int, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    _ = c.close(fd);
}

const libinput_impl: c.struct_libinput_interface = .{
    .open_restricted = libinputOpenRestricted,
    .close_restricted = libinputCloseRestricted,
};

/// Initialize the input subsystem: udev, libinput context, and xkbcommon.
/// Returns true on success, false on failure.
pub fn init(input: *Input, app: *App) bool {
    input.* = .{};

    input.udev = c.udev_new();
    if (input.udev == null) {
        std.log.err("udev_create: {s}", .{c.strerror(c.__errno_location().*)});
        return false;
    }

    input.libinput = c.libinput_udev_create_context(&libinput_impl, &app.devmgr, input.udev);
    if (input.libinput == null) {
        std.log.err("libinput_udev_create_context: {s}", .{c.strerror(c.__errno_location().*)});
        _ = c.udev_unref(input.udev);
        input.udev = null;
        return false;
    }
    _ = c.udev_unref(input.udev);
    input.udev = null;

    input.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    if (input.xkb_context == null) {
        std.log.err("xkb_context_new: {s}", .{c.strerror(c.__errno_location().*)});
        return false;
    }

    return true;
}

/// Release input subsystem resources.
pub fn finish(input: *Input) void {
    if (input.libinput) |li| _ = c.libinput_unref(li);
    if (input.xkb_context) |ctx| c.xkb_context_unref(ctx);
    if (input.xkb_keymap) |km| c.xkb_keymap_unref(km);
    if (input.xkb_state) |st| c.xkb_state_unref(st);
}

/// Get the libinput file descriptor for event polling.
pub fn getFd(input: *Input) c_int {
    return c.libinput_get_fd(input.libinput);
}

/// Map a libinput button constant to a human-readable name.
fn pointerButtonName(button: u32) ?[:0]const u8 {
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

/// Allocate a zero-initialized keypress struct via the Zig memory pool.
/// Uses `keys.KeyList.createKeypress()` which manages the pool internally;
/// the returned pointer is cast to the C-compatible struct type for legacy
/// callsites that still go through the `c.*` bridge.
fn allocKeypress() !*Keypress {
    return @ptrCast(try keys.KeyList.createKeypress());
}

/// Handle a keyboard key event from libinput: translate the keycode
/// through xkbcommon and append the keypress to the display list.
fn handleKeyboardKeyEvent(app: *App, kbevent: ?*c.struct_libinput_event_keyboard, dirty: *bool) void {
    const input = &app.input;
    if (input.xkb_state == null) return;

    const keycode: u32 = c.libinput_event_keyboard_get_key(kbevent) + 8;
    const key_state = c.libinput_event_keyboard_get_key_state(kbevent);
    _ = c.xkb_state_update_key(
        input.xkb_state,
        keycode,
        if (key_state == c.LIBINPUT_KEY_STATE_RELEASED) c.XKB_KEY_UP else c.XKB_KEY_DOWN,
    );

    const keysym = c.xkb_state_key_get_one_sym(input.xkb_state, keycode);

    if (key_state != c.LIBINPUT_KEY_STATE_PRESSED) return;

    const keypress = allocKeypress() catch return;
    keypress.* = .{ .sym = keysym };

    _ = c.xkb_keysym_get_name(keysym, @ptrCast(&keypress.name), keypress.name.len);

    if (c.xkb_state_key_get_utf8(input.xkb_state, keycode, @ptrCast(&keypress.utf8), keypress.utf8.len) <= 0 or
        keypress.utf8[0] <= ' ')
    {
        keypress.utf8[0] = 0;
    }

    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    const key_list: *keys.KeyList = @ptrCast(&app.keys);
    key_list.append(@ptrCast(keypress), @intCast(app.config.max_keys), .{
        .tv_sec = now.tv_sec,
        .tv_nsec = now.tv_nsec,
    });
    dirty.* = true;
}

/// Append a named pointer event (button press or scroll) to the key list.
fn appendPointerEvent(app: *App, name: []const u8, dirty: *bool) void {
    const keypress = allocKeypress() catch return;
    keypress.sym = c.XKB_KEY_NoSymbol;
    keypress.utf8[0] = 0;

    const copy_len = @min(name.len, keypress.name.len - 1);
    @memcpy(keypress.name[0..copy_len], name[0..copy_len]);
    keypress.name[copy_len] = 0;

    var now: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &now);
    const key_list: *keys.KeyList = @ptrCast(&app.keys);
    key_list.append(@ptrCast(keypress), @intCast(app.config.max_keys), .{
        .tv_sec = now.tv_sec,
        .tv_nsec = now.tv_nsec,
    });
    dirty.* = true;
}

/// Handle a pointer button event from libinput.
fn handlePointerButtonEvent(app: *App, pevent: ?*c.struct_libinput_event_pointer, dirty: *bool) void {
    const button_state = c.libinput_event_pointer_get_button_state(pevent);
    if (button_state != c.LIBINPUT_BUTTON_STATE_PRESSED) return;

    const button = c.libinput_event_pointer_get_button(pevent);
    const name: []const u8 = if (pointerButtonName(button)) |n|
        n
    else blk: {
        var fallback: [32]u8 = undefined;
        break :blk std.fmt.bufPrint(&fallback, "Mouse 0x{x}", .{button}) catch unreachable;
    };

    appendPointerEvent(app, name, dirty);
}

/// Handle a scroll wheel event from libinput.
fn handlePointerScrollWheelEvent(app: *App, pevent: ?*c.struct_libinput_event_pointer, dirty: *bool) void {
    if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL) != 0) {
        const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
        if (value < 0.0) appendPointerEvent(app, "Mouse Wheel Up", dirty);
        if (value > 0.0) appendPointerEvent(app, "Mouse Wheel Down", dirty);
    }

    if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL) != 0) {
        const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL);
        if (value < 0.0) appendPointerEvent(app, "Mouse Wheel Left", dirty);
        if (value > 0.0) appendPointerEvent(app, "Mouse Wheel Right", dirty);
    }
}

/// Dispatch a libinput event to the appropriate handler function.
pub fn handleEvent(app: *App, event: ?*c.struct_libinput_event, dirty: *bool) void {
    switch (c.libinput_event_get_type(event)) {
        c.LIBINPUT_EVENT_KEYBOARD_KEY => handleKeyboardKeyEvent(app, c.libinput_event_get_keyboard_event(event), dirty),
        c.LIBINPUT_EVENT_POINTER_BUTTON => handlePointerButtonEvent(app, c.libinput_event_get_pointer_event(event), dirty),
        c.LIBINPUT_EVENT_POINTER_SCROLL_WHEEL => handlePointerScrollWheelEvent(app, c.libinput_event_get_pointer_event(event), dirty),
        else => {},
    }
}

/// Replace the xkb keymap and state on the input subsystem.
/// Previous keymap/state are unreferenced first.
fn setKeymap(input: *Input, keymap: ?*c.struct_xkb_keymap, xkb_state: ?*c.struct_xkb_state) void {
    if (input.xkb_keymap) |km| c.xkb_keymap_unref(km);
    if (input.xkb_state) |st| c.xkb_state_unref(st);
    input.xkb_keymap = keymap;
    input.xkb_state = xkb_state;
}

/// Set the keymap from a Wayland file descriptor.
/// Reads the keymap string via mmap and initialises xkbcommon state.
pub fn setKeymapFromFd(input: *Input, format: u32, fd: i32, size: u32) void {
    const map_shm = c.mmap(null, size, c.PROT_READ, c.MAP_SHARED, fd, 0);
    if (map_shm == c.MAP_FAILED) {
        _ = c.close(fd);
        std.log.err("Unable to mmap keymap: {s}", .{c.strerror(c.__errno_location().*)});
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
    setKeymap(input, keymap, xkb_state);
}
