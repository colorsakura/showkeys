const std = @import("std");
const c = @import("c");

/// Alias for the C wsk_theme struct, maintaining ABI compatibility.
/// Used by exported functions for seamless interop with app.zig via `c.*` calls.
const Theme = c.struct_wsk_theme;

/// Initialize theme state by loading the key SVG and setting up
/// the icon cache base directory.
export fn wsk_theme_init(theme: *Theme, key_svg_path: [*c]const u8) bool {
    theme.* = .{};
    theme.key_svg_path = key_svg_path;

    if (key_svg_path) |path| {
        theme.base_dir = pathDirname(path);
        if (theme.base_dir == null) {
            std.log.err("Unable to allocate icon directory path", .{});
        }

        var error_ptr: ?*c.GError = null;
        theme.key_svg = c.rsvg_handle_new_from_file(path, &error_ptr);
        if (theme.key_svg == null) {
            const message: []const u8 = if (error_ptr) |err|
                std.mem.sliceTo(err.message, 0)
            else
                "unknown error";
            std.log.err("Unable to load key SVG '{s}': {s}", .{ path, message });
            if (error_ptr) |err| {
                c.g_error_free(err);
            }
            theme.key_svg_failed = true;
        }
    }
    return true;
}

/// Release theme resources: icon cache, base directory string,
/// and the key SVG handle.
export fn wsk_theme_finish(theme: *Theme) void {
    c.wsk_icon_cache_finish(&theme.icons);
    c.free(theme.base_dir);
    if (theme.key_svg) |svg| {
        c.g_object_unref(svg);
    }
}

/// Duplicate a C string into a new heap-allocated C string.
/// The caller is responsible for freeing the result with `c.free`.
export fn wsk_xstrdup(str: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(str, 0);
    return allocCopyZ(bytes);
}

/// Extract the directory portion of a path.
/// Returns a newly allocated C string (caller must free with `c.free`).
/// Returns null on allocation failure.
fn pathDirname(path: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(path, 0);
    const slash_index = std.mem.lastIndexOfScalar(u8, bytes, '/') orelse return allocCopyZ(".");
    if (slash_index == 0) {
        return allocCopyZ("/");
    }
    return allocCopyZ(bytes[0..slash_index]);
}

/// Join three path components with separators.
/// Returns a newly allocated C string (caller must free with `c.free`).
/// Returns null on allocation failure.
export fn wsk_join_path3(
    dir: [*c]const u8,
    subdir: [*c]const u8,
    file: [*c]const u8,
) [*c]u8 {
    const dir_bytes = std.mem.sliceTo(dir, 0);
    const subdir_bytes = std.mem.sliceTo(subdir, 0);
    const file_bytes = std.mem.sliceTo(file, 0);

    const sep1: []const u8 = if (dir_bytes.len > 0 and dir_bytes[dir_bytes.len - 1] == '/') "" else "/";
    const sep2: []const u8 = if (subdir_bytes.len > 0 and subdir_bytes[subdir_bytes.len - 1] == '/') "" else "/";

    const total_len = dir_bytes.len + sep1.len + subdir_bytes.len + sep2.len + file_bytes.len + 1;
    const buf = c.malloc(total_len) orelse return null;
    const buf_slice = @as([*]u8, @ptrCast(buf))[0..total_len];
    var offset: usize = 0;

    @memcpy(buf_slice[offset..][0..dir_bytes.len], dir_bytes);
    offset += dir_bytes.len;
    @memcpy(buf_slice[offset..][0..sep1.len], sep1);
    offset += sep1.len;
    @memcpy(buf_slice[offset..][0..subdir_bytes.len], subdir_bytes);
    offset += subdir_bytes.len;
    @memcpy(buf_slice[offset..][0..sep2.len], sep2);
    offset += sep2.len;
    @memcpy(buf_slice[offset..][0..file_bytes.len], file_bytes);
    offset += file_bytes.len;

    buf_slice[offset] = 0;
    return @ptrCast(buf);
}

/// Render an SVG document into a Cairo context within the given bounding rectangle.
/// Logs errors via `std.log.err` on failure.
/// Returns true on success, false on failure.
export fn wsk_svg_draw_to_rect(
    cr: ?*c.cairo_t,
    svg: ?*c.RsvgHandle,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    description: [*c]const u8,
) bool {
    var viewport: c.RsvgRectangle = .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
    };
    var error_ptr: ?*c.GError = null;
    const ok = c.rsvg_handle_render_document(svg, cr, &viewport, &error_ptr);
    if (ok == 0) {
        const desc = std.mem.sliceTo(description, 0);
        if (error_ptr) |err| {
            const msg = std.mem.sliceTo(err.message, 0);
            std.log.err("Unable to render {s} SVG: {s}", .{ desc, msg });
            c.g_error_free(err);
        } else {
            std.log.err("Unable to render {s} SVG", .{desc});
        }
        return false;
    }
    return true;
}

/// Allocate a null-terminated copy of the given byte slice.
/// The caller is responsible for freeing the result with `c.free`.
/// Returns null on allocation failure.
fn allocCopyZ(bytes: []const u8) [*c]u8 {
    const len = bytes.len + 1;
    const buf = c.malloc(len) orelse return null;
    const dest = @as([*]u8, @ptrCast(buf));
    @memcpy(dest[0..bytes.len], bytes);
    dest[bytes.len] = 0;
    return dest;
}
