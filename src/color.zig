const std = @import("std");

const c = @import("c");

export fn wsk_cairo_set_source_u32(cr: ?*c.cairo_t, color: u32) void {
    const r = @as(f64, @floatFromInt((color >> 24) & 0xFF)) / 255.0;
    const g = @as(f64, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
    const b = @as(f64, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
    const a = @as(f64, @floatFromInt(color & 0xFF)) / 255.0;
    c.cairo_set_source_rgba(cr, r, g, b, a);
}

export fn wsk_color_parse(text_c: [*:0]const u8, fallback: u32) u32 {
    var text = std.mem.sliceTo(text_c, 0);
    if (text.len > 0 and text[0] == '#') {
        text = text[1..];
    }

    if (text.len != 6 and text.len != 8) {
        std.log.warn("Invalid color {s}, defaulting to 0x{X:0>8}", .{ text, fallback });
        return fallback;
    }

    const color_val = std.fmt.parseInt(u32, text, 16) catch {
        std.log.warn("Invalid color {s}, defaulting to 0x{X:0>8}", .{ text, fallback });
        return fallback;
    };

    if (text.len == 6) {
        return (color_val << 8) | 0xFF;
    }
    return color_val;
}
