const std = @import("std");
const c = @import("c");
const events = @import("event.zig");
const module = @import("module.zig");
const errno = @import("errno.zig");

const Event = events.Event;
const EventBus = events.EventBus;

// ---------------------------------------------------------------------------
// InputModule — wraps the raw input subsystem and publishes input events
// to the event bus.
//
// Responsibilities:
//   - Dispatch libinput events → publish `key_pressed`, `pointer_button`,
//     `pointer_scroll` to the bus.
//   - Manage xkb state (keymap, compose state).
//   - Ownership of keypress structs is transferred to the subscriber
//     via `key_pressed`; the subscriber must free them via KeyList.
//
// Does NOT hold a reference to `*App` — communicates solely via EventBus.
// ---------------------------------------------------------------------------

/// State held by the input module.
pub const InputModule = struct {
    /// Embedded module base (provides `publish` convenience).
    base: module.ModuleBase(.input_mod) = .{},

    /// xkb context — long-lived, owns keymap/state factories.
    xkb_context: ?*c.struct_xkb_context = null,

    /// Current xkb keymap (set from Wayland keymap event).
    xkb_keymap: ?*c.struct_xkb_keymap = null,

    /// Current xkb state (updated on every keyboard key event).
    xkb_state: ?*c.struct_xkb_state = null,

    // ── Public API ───────────────────────────────────────────────────

    /// Initialise input state.  Does NOT start libinput (that is done
    /// by the privileged child + the caller via `input.zig`).
    /// Registers the module on the event bus.
    pub fn init(self: *InputModule, event_bus: *EventBus) !void {
        self.base.event_bus = event_bus;

        self.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
        if (self.xkb_context == null) {
            std.log.err("xkb_context_new: {s}", .{errno.strerror()});
            return error.XkbContextCreateFailed;
        }
    }

    /// Release xkb resources and close the libinput context.
    pub fn finish(self: *InputModule, libinput: ?*c.struct_libinput) void {
        if (libinput) |li| _ = c.libinput_unref(li);
        if (self.xkb_context) |ctx| c.xkb_context_unref(ctx);
        if (self.xkb_keymap) |km| c.xkb_keymap_unref(km);
        if (self.xkb_state) |st| c.xkb_state_unref(st);
    }

    /// Dispatch a single libinput event and publish the appropriate
    /// event to the bus when a key is pressed or a pointer button
    /// is clicked.
    pub fn handleEvent(self: *InputModule, event: ?*c.struct_libinput_event) void {
        const event_type = c.libinput_event_get_type(event);

        switch (event_type) {
            c.LIBINPUT_EVENT_KEYBOARD_KEY => {
                self.handleKeyboardKeyEvent(c.libinput_event_get_keyboard_event(event));
            },
            c.LIBINPUT_EVENT_POINTER_BUTTON => {
                self.handlePointerButtonEvent(c.libinput_event_get_pointer_event(event));
            },
            c.LIBINPUT_EVENT_POINTER_SCROLL_WHEEL => {
                self.handlePointerScrollWheelEvent(c.libinput_event_get_pointer_event(event));
            },
            else => {},
        }
    }

    /// Replace the xkb keymap and state.  Called when the compositor
    /// sends a new keymap via the Wayland keyboard.
    pub fn setKeymap(self: *InputModule, new_keymap: ?*c.struct_xkb_keymap, new_state: ?*c.struct_xkb_state) void {
        if (self.xkb_keymap) |km| c.xkb_keymap_unref(km);
        if (self.xkb_state) |st| c.xkb_state_unref(st);
        self.xkb_keymap = new_keymap;
        self.xkb_state = new_state;
    }

    /// Set the keymap from a Wayland file descriptor.
    pub fn setKeymapFromFd(self: *InputModule, format: u32, fd: i32, size: u32) void {
        const map_shm = c.mmap(null, size, c.PROT_READ, c.MAP_SHARED, fd, 0);
        if (map_shm == c.MAP_FAILED) {
            _ = c.close(fd);
            std.log.err("Unable to mmap keymap: {s}", .{errno.strerror()});
            return;
        }

        if (format != 1) { // WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1
            _ = c.munmap(map_shm, size);
            _ = c.close(fd);
            return;
        }

        const keymap = c.xkb_keymap_new_from_string(
            self.xkb_context,
            @ptrCast(map_shm),
            c.XKB_KEYMAP_FORMAT_TEXT_V1,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        );
        _ = c.munmap(map_shm, size);
        _ = c.close(fd);

        const xkb_state = c.xkb_state_new(keymap);
        self.setKeymap(keymap, xkb_state);
    }

    // ── Internal helpers ─────────────────────────────────────────────

    /// Handle a keyboard key event from libinput.
    fn handleKeyboardKeyEvent(self: *InputModule, kbevent: ?*c.struct_libinput_event_keyboard) void {
        if (self.xkb_state == null) return;

        const keycode: u32 = c.libinput_event_keyboard_get_key(kbevent) + 8;
        const key_state = c.libinput_event_keyboard_get_key_state(kbevent);
        _ = c.xkb_state_update_key(
            self.xkb_state,
            keycode,
            if (key_state == c.LIBINPUT_KEY_STATE_RELEASED) c.XKB_KEY_UP else c.XKB_KEY_DOWN,
        );

        const keysym = c.xkb_state_key_get_one_sym(self.xkb_state, keycode);

        // We only publish on press (not release).
        if (key_state != c.LIBINPUT_KEY_STATE_PRESSED) return;

        // Allocate a keypress via the global pool.
        const keypress = allocKeypress() catch return;
        keypress.* = .{ .sym = @intCast(keysym) };

        _ = c.xkb_keysym_get_name(keysym, @ptrCast(&keypress.name), keypress.name.len);

        if (c.xkb_state_key_get_utf8(self.xkb_state, keycode, @ptrCast(&keypress.utf8), keypress.utf8.len) <= 0 or
            keypress.utf8[0] <= ' ')
        {
            keypress.utf8[0] = 0;
        }

        self.base.publish(.{ .key_pressed = keypress });
    }

    /// Handle a pointer button event from libinput.
    fn handlePointerButtonEvent(self: *InputModule, pevent: ?*c.struct_libinput_event_pointer) void {
        const button_state = c.libinput_event_pointer_get_button_state(pevent);
        if (button_state != c.LIBINPUT_BUTTON_STATE_PRESSED) return;

        const button = c.libinput_event_pointer_get_button(pevent);

        if (pointerButtonName(button)) |n| {
            self.base.publish(.{ .pointer_button = n });
        } else {
            // Fallback: allocate a keypress for unnamed buttons.
            const keypress = allocKeypress() catch return;
            const fallback_slice = std.fmt.bufPrint(&keypress.name, "Mouse 0x{x}", .{button}) catch return;
            if (fallback_slice.len < keypress.name.len) {
                keypress.name[fallback_slice.len] = 0;
            }
            keypress.utf8[0] = 0;
            keypress.sym = @intCast(c.XKB_KEY_NoSymbol);
            self.base.publish(.{ .key_pressed = keypress });
        }
    }

    /// Handle a scroll wheel event from libinput.
    fn handlePointerScrollWheelEvent(self: *InputModule, pevent: ?*c.struct_libinput_event_pointer) void {
        if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL) != 0) {
            const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
            if (value < 0.0) self.base.publish(.{ .pointer_scroll = .up });
            if (value > 0.0) self.base.publish(.{ .pointer_scroll = .down });
        }

        if (c.libinput_event_pointer_has_axis(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL) != 0) {
            const value = c.libinput_event_pointer_get_scroll_value(pevent, c.LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL);
            if (value < 0.0) self.base.publish(.{ .pointer_scroll = .left });
            if (value > 0.0) self.base.publish(.{ .pointer_scroll = .right });
        }
    }
};

// ---------------------------------------------------------------------------
// Module-level helpers (no self)
// ---------------------------------------------------------------------------

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
fn allocKeypress() !*@import("keys.zig").Keypress {
    return try @import("keys.zig").KeyList.createKeypress();
}
