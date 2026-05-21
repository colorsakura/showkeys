const std = @import("std");
const c = @import("c");

export fn wsk_theme_init(theme: *c.struct_wsk_theme, key_svg_path: [*c]const u8) bool {
    _ = c.memset(theme, 0, @sizeOf(c.struct_wsk_theme));
    theme.key_svg_path = key_svg_path;

    if (key_svg_path != null) {
        theme.base_dir = wsk_path_dirname(key_svg_path);
        if (theme.base_dir == null) {
            _ = c.fprintf(c.stderr, "Unable to allocate icon directory path\n");
        }

        var error_ptr: ?*c.GError = null;
        theme.key_svg = c.rsvg_handle_new_from_file(key_svg_path, &error_ptr);
        if (theme.key_svg == null) {
            const message: [*c]const u8 = if (error_ptr) |err| err.message else "unknown error";
            _ = c.fprintf(c.stderr, "Unable to load key SVG '%s': %s\n", key_svg_path, message);
            if (error_ptr) |err| {
                c.g_error_free(err);
            }
            theme.key_svg_failed = true;
        }
    }
    return true;
}

export fn wsk_theme_finish(theme: *c.struct_wsk_theme) void {
    c.wsk_icon_cache_finish(&theme.icons);
    c.free(theme.base_dir);
    if (theme.key_svg) |svg| {
        c.g_object_unref(svg);
    }
}

export fn wsk_xstrdup(str: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(str, 0);
    return allocCopyZ(bytes);
}

export fn wsk_path_dirname(path: [*c]const u8) [*c]u8 {
    const bytes = std.mem.sliceTo(path, 0);
    const slash_index = std.mem.lastIndexOfScalar(u8, bytes, '/') orelse return allocCopyZ(".");
    if (slash_index == 0) {
        return allocCopyZ("/");
    }
    return allocCopyZ(bytes[0..slash_index]);
}

export fn wsk_join_path3(dir: [*c]const u8, subdir: [*c]const u8, file: [*c]const u8) [*c]u8 {
    const dir_bytes = std.mem.sliceTo(dir, 0);
    const subdir_bytes = std.mem.sliceTo(subdir, 0);
    const file_bytes = std.mem.sliceTo(file, 0);
    const sep1: [*:0]const u8 = if (dir_bytes.len > 0 and dir_bytes[dir_bytes.len - 1] == '/') "" else "/";
    const sep2: [*:0]const u8 = if (subdir_bytes.len > 0 and subdir_bytes[subdir_bytes.len - 1] == '/') "" else "/";
    const len = dir_bytes.len + std.mem.len(sep1) + subdir_bytes.len + std.mem.len(sep2) + file_bytes.len + 1;
    const path = c.malloc(len) orelse return null;
    const path_c: [*c]u8 = @ptrCast(path);
    _ = c.snprintf(path_c, len, "%s%s%s%s%s", dir, sep1, subdir, sep2, file);
    return path_c;
}

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
        if (error_ptr) |err| {
            _ = c.fprintf(c.stderr, "Unable to render %s SVG: %s\n", description, err.message);
            c.g_error_free(err);
        } else {
            _ = c.fprintf(c.stderr, "Unable to render %s SVG\n", description);
        }
        return false;
    }
    return true;
}

fn allocCopyZ(bytes: []const u8) [*c]u8 {
    const len = bytes.len + 1;
    const allocation = c.malloc(len) orelse return null;
    const copy: [*]u8 = @ptrCast(allocation);
    @memcpy(copy[0..bytes.len], bytes);
    copy[bytes.len] = 0;
    return copy;
}
