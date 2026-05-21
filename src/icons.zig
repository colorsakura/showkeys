const std = @import("std");
const c = @import("c");
const theme = @import("theme.zig");

// ---------------------------------------------------------------------------
// Module-level icon cache (global — only one theme at a time)
// ---------------------------------------------------------------------------

var icon_cache: std.StringHashMap(?*c.RsvgHandle) = undefined;
var icon_cache_initialized = false;

fn ensureCache() void {
    if (!icon_cache_initialized) {
        icon_cache = std.StringHashMap(?*c.RsvgHandle).init(std.heap.page_allocator);
        icon_cache_initialized = true;
    }
}

pub fn deinitCache() void {
    if (icon_cache_initialized) {
        var it = icon_cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.*) |svg| c.g_object_unref(svg);
        }
        icon_cache.deinit();
        icon_cache_initialized = false;
    }
}

// ---------------------------------------------------------------------------
// Icon name mapping
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Icon name map (HashMap for O(1) lookup)
// ---------------------------------------------------------------------------

var icon_name_map: std.StringHashMap([:0]const u8) = undefined;
var icon_name_map_initialized = false;

fn ensureNameMap() void {
    if (!icon_name_map_initialized) {
        icon_name_map = std.StringHashMap([:0]const u8).init(std.heap.page_allocator);
        for (icon_map) |entry| {
            icon_name_map.put(entry.key_name, entry.icon_name) catch {};
        }
        icon_name_map_initialized = true;
    }
}

/// Look up the icon filename for a special key name.
pub fn specialIconName(key_name: []const u8) ?[:0]const u8 {
    ensureNameMap();
    return icon_name_map.get(key_name);
}

/// C ABI wrapper for specialIconName.
pub fn specialIconNameC(key_name: [*c]const u8) [*c]const u8 {
    const key_name_bytes = std.mem.sliceTo(key_name orelse return null, 0);
    const icon_name = specialIconName(key_name_bytes) orelse return null;
    return icon_name.ptr;
}

/// Find or load an SVG icon for the given icon name.
pub fn cacheGet(base_dir: [*c]const u8, icon_name: [*c]const u8) ?*c.RsvgHandle {
    if (base_dir == null or icon_name == null) return null;

    ensureCache();

    const name = std.mem.sliceTo(icon_name, 0);

    // Check the Zig hash map first.
    if (icon_cache.get(name)) |cached| return cached;

    // Not cached — load the SVG file.
    const path = theme.joinPath3(base_dir, "icons", icon_name);
    if (path == null) {
        icon_cache.put(name, null) catch {};
        return null;
    }

    var error_ptr: ?*c.GError = null;
    const svg = c.rsvg_handle_new_from_file(path, &error_ptr);
    const result: ?*c.RsvgHandle = if (svg) |s|
        s
    else brk: {
        if (error_ptr) |err| c.g_error_free(err);
        break :brk null;
    };

    // Cache the result (null = failure, avoid retrying).
    icon_cache.put(name, result) catch {};
    return result;
}

/// Free all entries in the icon cache and the icon name map.
pub fn cacheFinish() void {
    deinitCache();
    if (icon_name_map_initialized) {
        icon_name_map.deinit();
        icon_name_map_initialized = false;
    }
}
