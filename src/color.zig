const std = @import("std");

pub fn setSourceU32(cairo_context: ?*anyopaque, color: u32) void {
    const r = @as(f64, @floatFromInt((color >> 24) & 0xFF)) / 255.0;
    const g = @as(f64, @floatFromInt((color >> 16) & 0xFF)) / 255.0;
    const b = @as(f64, @floatFromInt((color >> 8) & 0xFF)) / 255.0;
    const a = @as(f64, @floatFromInt(color & 0xFF)) / 255.0;
    if (cairo_context) |p| {
        cairo_set_source_rgba(p, r, g, b, a);
    }
}

pub fn parse(text: []const u8, fallback: u32) u32 {
    var trimmed = text;
    if (trimmed.len > 0 and trimmed[0] == '#') {
        trimmed = trimmed[1..];
    }

    if (trimmed.len != 6 and trimmed.len != 8) {
        std.log.warn("Invalid color '{s}', defaulting to 0x{X:0>8}", .{ trimmed, fallback });
        return fallback;
    }

    const color_val = std.fmt.parseInt(u32, trimmed, 16) catch {
        std.log.warn("Invalid color '{s}', defaulting to 0x{X:0>8}", .{ trimmed, fallback });
        return fallback;
    };

    if (trimmed.len == 6) {
        return (color_val << 8) | 0xFF;
    }
    return color_val;
}

extern "c" fn cairo_set_source_rgba(cr: *anyopaque, r: f64, g: f64, b: f64, a: f64) void;
