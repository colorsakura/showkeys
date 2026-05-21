const std = @import("std");
const c = @import("c");
const icons = @import("icons.zig");

/// Alias for the C wsk_theme struct, maintaining ABI compatibility.
const Theme = c.struct_wsk_theme;

/// Arena for path string allocations.  Freed when `finish()` is called.
var path_arena: std.heap.ArenaAllocator = undefined;
var path_arena_initialized = false;

fn ensurePathArena() void {
    if (!path_arena_initialized) {
        path_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        path_arena_initialized = true;
    }
}

/// Initialize theme state by loading the key SVG and setting up
/// the icon cache base directory.
pub fn init(theme: *Theme, key_svg_path: [*c]const u8) bool {
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

/// Release theme resources: icon cache, path arena, and the key SVG handle.
pub fn finish(theme: *Theme) void {
    icons.cacheFinish(&theme.icons);
    if (path_arena_initialized) {
        path_arena.deinit();
        path_arena_initialized = false;
    }
    if (theme.key_svg) |svg| {
        c.g_object_unref(svg);
    }
}

/// Duplicate a C string into a new C string from the path arena.
pub fn xstrdup(str: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(str, 0);
    return allocCopyZ(bytes);
}

/// Extract the directory portion of a path from the path arena.
fn pathDirname(path: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(path, 0);
    const slash_index = std.mem.lastIndexOfScalar(u8, bytes, '/') orelse return allocCopyZ(".");
    if (slash_index == 0) {
        return allocCopyZ("/");
    }
    return allocCopyZ(bytes[0..slash_index]);
}

/// Join three path components with separators from the path arena.
pub fn joinPath3(
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
    ensurePathArena();
    const allocator = path_arena.allocator();
    const buf_slice = allocator.alloc(u8, total_len) catch return null;
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
    return @ptrCast(buf_slice.ptr);
}

/// Render an SVG document into a Cairo context within the given bounding rectangle.
pub fn svgDrawToRect(
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

/// Allocate a null-terminated copy of the given byte slice from the path arena.
fn allocCopyZ(bytes: []const u8) [*c]u8 {
    ensurePathArena();
    const allocator = path_arena.allocator();
    const buf = allocator.alloc(u8, bytes.len + 1) catch return null;
    @memcpy(buf[0..bytes.len], bytes);
    buf[bytes.len] = 0;
    return @ptrCast(buf.ptr);
}
