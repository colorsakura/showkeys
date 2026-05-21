const std = @import("std");
const c = @import("c");

const IconCache = c.struct_wsk_icon_cache;
const IconCacheEntry = c.struct_wsk_icon_cache_entry;

const IconMapEntry = struct {
    key_name: []const u8,
    icon_name: [:0]const u8,
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

pub fn specialIconName(key_name: []const u8) ?[:0]const u8 {
    for (icon_map) |entry| {
        if (std.mem.eql(u8, key_name, entry.key_name)) {
            return entry.icon_name;
        }
    }
    return null;
}

export fn wsk_special_icon_name(key_name: [*c]const u8) [*c]const u8 {
    if (key_name == null) {
        return null;
    }

    const key_name_bytes = std.mem.sliceTo(key_name, 0);
    const icon_name = specialIconName(key_name_bytes) orelse return null;
    return icon_name.ptr;
}

export fn wsk_icon_cache_get(
    cache: *IconCache,
    base_dir: [*c]const u8,
    icon_name: [*c]const u8,
) ?*c.RsvgHandle {
    if (base_dir == null) {
        return null;
    }
    if (icon_name == null) {
        return null;
    }

    const icon_name_bytes = std.mem.sliceTo(icon_name, 0);
    if (findIconCacheEntry(cache, icon_name_bytes)) |entry| {
        return if (entry.failed) null else entry.svg;
    }

    const entry = createIconCacheEntry(icon_name) orelse return null;
    errdefer destroyIconCacheEntry(entry);

    const path = c.wsk_join_path3(base_dir, "icons", icon_name);
    if (path == null) {
        entry.failed = true;
    } else {
        defer c.free(path);
        entry.svg = loadSvg(path, &entry.failed);
    }

    entry.next = cache.entries;
    cache.entries = entry;
    return if (entry.failed) null else entry.svg;
}

export fn wsk_icon_cache_finish(cache: *IconCache) void {
    var icon = cache.entries;
    while (icon) |entry| {
        const next = entry[0].next;
        destroyIconCacheEntry(@ptrCast(@alignCast(&entry[0])));
        icon = next;
    }
    cache.entries = null;
}

fn findIconCacheEntry(cache: *const IconCache, icon_name: []const u8) ?*IconCacheEntry {
    var current = cache.entries;
    while (current) |entry| {
        const cached_name = std.mem.sliceTo(entry[0].icon_name, 0);
        if (std.mem.eql(u8, cached_name, icon_name)) {
            return @ptrCast(@alignCast(&entry[0]));
        }
        current = entry[0].next;
    }
    return null;
}

fn createIconCacheEntry(icon_name: [*c]const u8) ?*IconCacheEntry {
    const allocation = c.malloc(@sizeOf(IconCacheEntry)) orelse return null;
    const entry: *IconCacheEntry = @ptrCast(@alignCast(allocation));
    entry.* = .{
        .icon_name = null,
        .svg = null,
        .failed = false,
        .next = null,
    };

    entry.icon_name = c.wsk_xstrdup(icon_name);
    if (entry.icon_name == null) {
        c.free(entry);
        return null;
    }
    return entry;
}

fn destroyIconCacheEntry(entry: *IconCacheEntry) void {
    if (entry.svg) |svg| {
        c.g_object_unref(svg);
    }
    c.free(entry.icon_name);
    c.free(entry);
}

fn loadSvg(path: [*c]const u8, failed: *bool) ?*c.RsvgHandle {
    var error_ptr: ?*c.GError = null;
    const svg = c.rsvg_handle_new_from_file(path, &error_ptr);
    if (svg == null) {
        failed.* = true;
        if (error_ptr) |err| {
            c.g_error_free(err);
        }
        return null;
    }

    failed.* = false;
    return svg;
}
