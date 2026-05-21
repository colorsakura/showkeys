const c = @import("c");

const IconMapEntry = struct {
    key_name: [*:0]const u8,
    icon_name: [*:0]const u8,
};

const icon_map = [_]IconMapEntry{
    .{ .key_name = "Escape", .icon_name = "escape.svg" },
    .{ .key_name = "Tab", .icon_name = "tab.svg" },
    .{ .key_name = "ISO_Left_Tab", .icon_name = "tab.svg" },
    .{ .key_name = "Enter", .icon_name = "enter.svg" },
    .{ .key_name = "Return", .icon_name = "enter.svg" },
    .{ .key_name = "KP_Enter", .icon_name = "enter.svg" },
    .{ .key_name = "BackSpace", .icon_name = "backspace.svg" },
    .{ .key_name = "Delete", .icon_name = "delete.svg" },
    .{ .key_name = "KP_Delete", .icon_name = "delete.svg" },
    .{ .key_name = "Insert", .icon_name = "insert.svg" },
    .{ .key_name = "KP_Insert", .icon_name = "insert.svg" },
    .{ .key_name = "Home", .icon_name = "home.svg" },
    .{ .key_name = "KP_Home", .icon_name = "home.svg" },
    .{ .key_name = "End", .icon_name = "end.svg" },
    .{ .key_name = "KP_End", .icon_name = "end.svg" },
    .{ .key_name = "Page_Up", .icon_name = "page-up.svg" },
    .{ .key_name = "KP_Page_Up", .icon_name = "page-up.svg" },
    .{ .key_name = "Page_Down", .icon_name = "page-down.svg" },
    .{ .key_name = "KP_Page_Down", .icon_name = "page-down.svg" },
    .{ .key_name = "Caps_Lock", .icon_name = "caps-lock.svg" },
    .{ .key_name = "Num_Lock", .icon_name = "num-lock.svg" },
    .{ .key_name = "Scroll_Lock", .icon_name = "scroll-lock.svg" },
    .{ .key_name = "Pause", .icon_name = "pause.svg" },
    .{ .key_name = "Break", .icon_name = "pause.svg" },
    .{ .key_name = "Print", .icon_name = "print-screen.svg" },
    .{ .key_name = "Sys_Req", .icon_name = "print-screen.svg" },
    .{ .key_name = "Menu", .icon_name = "menu.svg" },
    .{ .key_name = "XF86MenuKB", .icon_name = "menu.svg" },
    .{ .key_name = "space", .icon_name = "space.svg" },
    .{ .key_name = "KP_Space", .icon_name = "space.svg" },
    .{ .key_name = "Shift_L", .icon_name = "shift.svg" },
    .{ .key_name = "Shift_R", .icon_name = "shift.svg" },
    .{ .key_name = "Control_L", .icon_name = "ctrl.svg" },
    .{ .key_name = "Control_R", .icon_name = "ctrl.svg" },
    .{ .key_name = "Alt_L", .icon_name = "alt.svg" },
    .{ .key_name = "Alt_R", .icon_name = "alt.svg" },
    .{ .key_name = "Meta_L", .icon_name = "alt.svg" },
    .{ .key_name = "Meta_R", .icon_name = "alt.svg" },
    .{ .key_name = "Super_L", .icon_name = "super.svg" },
    .{ .key_name = "Super_R", .icon_name = "super.svg" },
    .{ .key_name = "Hyper_L", .icon_name = "super.svg" },
    .{ .key_name = "Hyper_R", .icon_name = "super.svg" },
    .{ .key_name = "Left", .icon_name = "arrow-left.svg" },
    .{ .key_name = "KP_Left", .icon_name = "arrow-left.svg" },
    .{ .key_name = "Right", .icon_name = "arrow-right.svg" },
    .{ .key_name = "KP_Right", .icon_name = "arrow-right.svg" },
    .{ .key_name = "Up", .icon_name = "arrow-up.svg" },
    .{ .key_name = "KP_Up", .icon_name = "arrow-up.svg" },
    .{ .key_name = "Down", .icon_name = "arrow-down.svg" },
    .{ .key_name = "KP_Down", .icon_name = "arrow-down.svg" },
    .{ .key_name = "KP_Begin", .icon_name = "keypad.svg" },
    .{ .key_name = "KP_Add", .icon_name = "keypad.svg" },
    .{ .key_name = "KP_Subtract", .icon_name = "keypad.svg" },
    .{ .key_name = "KP_Multiply", .icon_name = "keypad.svg" },
    .{ .key_name = "KP_Divide", .icon_name = "keypad.svg" },
    .{ .key_name = "XF86AudioPlay", .icon_name = "media-play.svg" },
    .{ .key_name = "XF86AudioPause", .icon_name = "pause.svg" },
    .{ .key_name = "XF86AudioStop", .icon_name = "media-stop.svg" },
    .{ .key_name = "XF86AudioPrev", .icon_name = "media-prev.svg" },
    .{ .key_name = "XF86AudioNext", .icon_name = "media-next.svg" },
    .{ .key_name = "XF86AudioRaiseVolume", .icon_name = "volume-up.svg" },
    .{ .key_name = "XF86AudioLowerVolume", .icon_name = "volume-down.svg" },
    .{ .key_name = "XF86AudioMute", .icon_name = "volume-mute.svg" },
    .{ .key_name = "XF86MonBrightnessUp", .icon_name = "brightness.svg" },
    .{ .key_name = "XF86MonBrightnessDown", .icon_name = "brightness.svg" },
    .{ .key_name = "XF86KbdBrightnessUp", .icon_name = "brightness.svg" },
    .{ .key_name = "XF86KbdBrightnessDown", .icon_name = "brightness.svg" },
    .{ .key_name = "XF86Fn", .icon_name = "fn.svg" },
    .{ .key_name = "XF86Fn_Esc", .icon_name = "fn.svg" },
    .{ .key_name = "Mouse Left", .icon_name = "mouse-left.svg" },
    .{ .key_name = "Mouse Right", .icon_name = "mouse-right.svg" },
    .{ .key_name = "Mouse Middle", .icon_name = "mouse-middle.svg" },
    .{ .key_name = "Mouse Wheel Up", .icon_name = "mouse-wheel-up.svg" },
    .{ .key_name = "Mouse Wheel Down", .icon_name = "mouse-wheel-down.svg" },
    .{ .key_name = "Mouse Wheel Left", .icon_name = "mouse-wheel-left.svg" },
    .{ .key_name = "Mouse Wheel Right", .icon_name = "mouse-wheel-right.svg" },
    .{ .key_name = "Mouse Side", .icon_name = "mouse-side.svg" },
    .{ .key_name = "Mouse Extra", .icon_name = "mouse-extra.svg" },
    .{ .key_name = "Mouse Forward", .icon_name = "mouse-forward.svg" },
    .{ .key_name = "Mouse Back", .icon_name = "mouse-back.svg" },
};

export fn wsk_special_icon_name(key_name: [*c]const u8) [*c]const u8 {
    for (icon_map) |entry| {
        if (c.strcmp(key_name, entry.key_name) == 0) {
            return entry.icon_name;
        }
    }
    return null;
}

export fn wsk_icon_cache_get(
    cache: *c.struct_wsk_icon_cache,
    base_dir: [*c]const u8,
    icon_name: [*c]const u8,
) ?*c.RsvgHandle {
    if (base_dir == null or icon_name == null) {
        return null;
    }

    var current = cache.entries;
    while (current) |entry| {
        if (c.strcmp(entry[0].icon_name, icon_name) == 0) {
            return if (entry[0].failed) null else entry[0].svg;
        }
        current = entry[0].next;
    }

    const allocation = c.calloc(1, @sizeOf(c.struct_wsk_icon_cache_entry)) orelse return null;
    const entry: *c.struct_wsk_icon_cache_entry = @ptrCast(@alignCast(allocation));

    entry.icon_name = c.wsk_xstrdup(icon_name);
    if (entry.icon_name == null) {
        c.free(entry);
        return null;
    }

    const path = c.wsk_join_path3(base_dir, "icons", icon_name);
    if (path == null) {
        entry.failed = true;
    } else {
        var error_ptr: ?*c.GError = null;
        entry.svg = c.rsvg_handle_new_from_file(path, &error_ptr);
        if (entry.svg == null) {
            entry.failed = true;
            if (error_ptr != null) {
                c.g_error_free(error_ptr);
            }
        }
        c.free(path);
    }

    entry.next = cache.entries;
    cache.entries = entry;
    return if (entry.failed) null else entry.svg;
}

export fn wsk_icon_cache_finish(cache: *c.struct_wsk_icon_cache) void {
    var icons = cache.entries;
    while (icons) |entry| {
        const next = entry[0].next;
        if (entry[0].svg != null) {
            c.g_object_unref(entry[0].svg);
        }
        c.free(entry[0].icon_name);
        c.free(entry);
        icons = next;
    }
    cache.entries = null;
}
