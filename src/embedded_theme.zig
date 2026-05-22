const std = @import("std");

// ---------------------------------------------------------------------------
// Embedded default theme — all SVG files are compiled into the binary
// via @embedFile so no filesystem access is needed at runtime.
//
// Each SVG is stored as a flat array of (filename, data) pairs.
// ---------------------------------------------------------------------------

/// A single embedded SVG file.
pub const EmbeddedSvg = struct {
    /// Filename, e.g. "key.svg", "escape.svg"
    name: []const u8,
    /// Raw SVG content bytes (including null terminator for C interop).
    data: [:0]const u8,
};

// ---------------------------------------------------------------------------
// key.svg
// ---------------------------------------------------------------------------

pub const key_svg = @embedFile("embedded_theme/key.svg");

// ---------------------------------------------------------------------------
// All embedded SVG files — icons + key background
// ---------------------------------------------------------------------------

/// Full list of all embedded SVGs.  Looks up by filename.
/// Built at compile time — zero runtime overhead.
pub const all = blk: {
    const key_svg_data: [:0]const u8 = @embedFile("embedded_theme/key.svg");

    const alt = @embedFile("embedded_theme/icons/alt.svg");
    const arrow_down = @embedFile("embedded_theme/icons/arrow-down.svg");
    const arrow_left = @embedFile("embedded_theme/icons/arrow-left.svg");
    const arrow_right = @embedFile("embedded_theme/icons/arrow-right.svg");
    const arrow_up = @embedFile("embedded_theme/icons/arrow-up.svg");
    const backspace = @embedFile("embedded_theme/icons/backspace.svg");
    const brightness = @embedFile("embedded_theme/icons/brightness.svg");
    const caps_lock = @embedFile("embedded_theme/icons/caps-lock.svg");
    const ctrl = @embedFile("embedded_theme/icons/ctrl.svg");
    const delete = @embedFile("embedded_theme/icons/delete.svg");
    const end = @embedFile("embedded_theme/icons/end.svg");
    const enter = @embedFile("embedded_theme/icons/enter.svg");
    const escape = @embedFile("embedded_theme/icons/escape.svg");
    const fn_svg = @embedFile("embedded_theme/icons/fn.svg");
    const home = @embedFile("embedded_theme/icons/home.svg");
    const insert = @embedFile("embedded_theme/icons/insert.svg");
    const keypad = @embedFile("embedded_theme/icons/keypad.svg");
    const media_next = @embedFile("embedded_theme/icons/media-next.svg");
    const media_play = @embedFile("embedded_theme/icons/media-play.svg");
    const media_prev = @embedFile("embedded_theme/icons/media-prev.svg");
    const media_stop = @embedFile("embedded_theme/icons/media-stop.svg");
    const menu = @embedFile("embedded_theme/icons/menu.svg");
    const mouse_back = @embedFile("embedded_theme/icons/mouse-back.svg");
    const mouse_extra = @embedFile("embedded_theme/icons/mouse-extra.svg");
    const mouse_forward = @embedFile("embedded_theme/icons/mouse-forward.svg");
    const mouse_left = @embedFile("embedded_theme/icons/mouse-left.svg");
    const mouse_middle = @embedFile("embedded_theme/icons/mouse-middle.svg");
    const mouse_right = @embedFile("embedded_theme/icons/mouse-right.svg");
    const mouse_side = @embedFile("embedded_theme/icons/mouse-side.svg");
    const mouse_wheel_down = @embedFile("embedded_theme/icons/mouse-wheel-down.svg");
    const mouse_wheel_left = @embedFile("embedded_theme/icons/mouse-wheel-left.svg");
    const mouse_wheel_right = @embedFile("embedded_theme/icons/mouse-wheel-right.svg");
    const mouse_wheel_up = @embedFile("embedded_theme/icons/mouse-wheel-up.svg");
    const num_lock = @embedFile("embedded_theme/icons/num-lock.svg");
    const page_down = @embedFile("embedded_theme/icons/page-down.svg");
    const page_up = @embedFile("embedded_theme/icons/page-up.svg");
    const pause = @embedFile("embedded_theme/icons/pause.svg");
    const print_screen = @embedFile("embedded_theme/icons/print-screen.svg");
    const scroll_lock = @embedFile("embedded_theme/icons/scroll-lock.svg");
    const shift = @embedFile("embedded_theme/icons/shift.svg");
    const space = @embedFile("embedded_theme/icons/space.svg");
    const super_svg = @embedFile("embedded_theme/icons/super.svg");
    const tab = @embedFile("embedded_theme/icons/tab.svg");
    const volume_down = @embedFile("embedded_theme/icons/volume-down.svg");
    const volume_mute = @embedFile("embedded_theme/icons/volume-mute.svg");
    const volume_up = @embedFile("embedded_theme/icons/volume-up.svg");

    const result: []const EmbeddedSvg = &.{
        .{ .name = "key.svg", .data = key_svg_data },
        .{ .name = "alt.svg", .data = alt },
        .{ .name = "arrow-down.svg", .data = arrow_down },
        .{ .name = "arrow-left.svg", .data = arrow_left },
        .{ .name = "arrow-right.svg", .data = arrow_right },
        .{ .name = "arrow-up.svg", .data = arrow_up },
        .{ .name = "backspace.svg", .data = backspace },
        .{ .name = "brightness.svg", .data = brightness },
        .{ .name = "caps-lock.svg", .data = caps_lock },
        .{ .name = "ctrl.svg", .data = ctrl },
        .{ .name = "delete.svg", .data = delete },
        .{ .name = "end.svg", .data = end },
        .{ .name = "enter.svg", .data = enter },
        .{ .name = "escape.svg", .data = escape },
        .{ .name = "fn.svg", .data = fn_svg },
        .{ .name = "home.svg", .data = home },
        .{ .name = "insert.svg", .data = insert },
        .{ .name = "keypad.svg", .data = keypad },
        .{ .name = "media-next.svg", .data = media_next },
        .{ .name = "media-play.svg", .data = media_play },
        .{ .name = "media-prev.svg", .data = media_prev },
        .{ .name = "media-stop.svg", .data = media_stop },
        .{ .name = "menu.svg", .data = menu },
        .{ .name = "mouse-back.svg", .data = mouse_back },
        .{ .name = "mouse-extra.svg", .data = mouse_extra },
        .{ .name = "mouse-forward.svg", .data = mouse_forward },
        .{ .name = "mouse-left.svg", .data = mouse_left },
        .{ .name = "mouse-middle.svg", .data = mouse_middle },
        .{ .name = "mouse-right.svg", .data = mouse_right },
        .{ .name = "mouse-side.svg", .data = mouse_side },
        .{ .name = "mouse-wheel-down.svg", .data = mouse_wheel_down },
        .{ .name = "mouse-wheel-left.svg", .data = mouse_wheel_left },
        .{ .name = "mouse-wheel-right.svg", .data = mouse_wheel_right },
        .{ .name = "mouse-wheel-up.svg", .data = mouse_wheel_up },
        .{ .name = "num-lock.svg", .data = num_lock },
        .{ .name = "page-down.svg", .data = page_down },
        .{ .name = "page-up.svg", .data = page_up },
        .{ .name = "pause.svg", .data = pause },
        .{ .name = "print-screen.svg", .data = print_screen },
        .{ .name = "scroll-lock.svg", .data = scroll_lock },
        .{ .name = "shift.svg", .data = shift },
        .{ .name = "space.svg", .data = space },
        .{ .name = "super.svg", .data = super_svg },
        .{ .name = "tab.svg", .data = tab },
        .{ .name = "volume-down.svg", .data = volume_down },
        .{ .name = "volume-mute.svg", .data = volume_mute },
        .{ .name = "volume-up.svg", .data = volume_up },
    };

    break :blk result;
};

/// Look up an embedded SVG by filename.
/// Returns null if the file is not embedded.
pub fn find(name: []const u8) ?EmbeddedSvg {
    for (all) |svg| {
        if (std.mem.eql(u8, svg.name, name)) return svg;
    }
    return null;
}
