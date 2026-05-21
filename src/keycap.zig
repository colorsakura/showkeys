const std = @import("std");
const c = @import("c");
const types = @import("types.zig");
const keys_mod = @import("keys.zig");
const color = @import("color.zig");
const thm = @import("theme.zig");
const pango = @import("pango.zig");
const icons = @import("icons.zig");

const Keypress = keys_mod.Keypress;
const KeycapLayout = types.KeycapLayout;
const Config = types.Config;
const Theme = types.Theme;

/// Arena for transient layout arrays. Reset on every `measureKeycaps` call.
var layout_arena: std.heap.ArenaAllocator = undefined;
var layout_arena_initialized = false;

fn ensureLayoutArena() void {
    if (!layout_arena_initialized) {
        layout_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        layout_arena_initialized = true;
    }
}

// ---------------------------------------------------------------------------
// Constants & types
// ---------------------------------------------------------------------------

const KeycapStyle = struct {
    padding_x: c_int = 0,
    padding_y: c_int = 0,
    gap: c_int = 0,
    radius: c_int = 0,
    border_width: c_int = 0,
    icon_size: c_int = 0,
    normal_bg: u32 = 0,
    normal_fg: u32 = 0,
    special_bg: u32 = 0,
    special_fg: u32 = 0,
    border: u32 = 0,
};

const keycap_style: KeycapStyle = .{
    .padding_x = 12,
    .padding_y = 6,
    .gap = 6,
    .radius = 8,
    .border_width = 1,
    .icon_size = 32,
};

const keycap_style_filled: KeycapStyle = .{
    .padding_x = 12,
    .padding_y = 6,
    .gap = 6,
    .radius = 8,
    .border_width = 1,
    .icon_size = 32,
    .normal_bg = 0x222222CC,
    .special_bg = 0x444444CC,
    .border = 0xFFFFFF33,
};

const tau: f64 = 6.283185307179586;
const half_pi: f64 = 1.5707963267948966;

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------

fn roundedRectangle(cairo: ?*c.cairo_t, x: f64, y: f64, w: f64, h: f64, radius: f64) void {
    var r = radius;
    if (r > w / 2.0) r = w / 2.0;
    if (r > h / 2.0) r = h / 2.0;

    c.cairo_new_sub_path(cairo);
    c.cairo_arc(cairo, x + w - r, y + r, r, -half_pi, 0.0);
    c.cairo_arc(cairo, x + w - r, y + h - r, r, 0.0, half_pi);
    c.cairo_arc(cairo, x + r, y + h - r, r, half_pi, tau * 0.5);
    c.cairo_arc(cairo, x + r, y + r, r, tau * 0.75, tau);
    c.cairo_close_path(cairo);
}

fn drawCairoKeycap(cairo: ?*c.cairo_t, layout: *const KeycapLayout, style: *const KeycapStyle, radius: c_int, border_width: c_int) void {
    roundedRectangle(
        cairo,
        @floatFromInt(layout.x),
        @floatFromInt(layout.y),
        @floatFromInt(layout.width),
        @floatFromInt(layout.height),
        @floatFromInt(radius),
    );
    color.setSourceU32(cairo, if (layout.special) style.special_bg else style.normal_bg);
    c.cairo_fill_preserve(cairo);

    if (border_width > 0) {
        c.cairo_set_line_width(cairo, @floatFromInt(border_width));
        color.setSourceU32(cairo, style.border);
        c.cairo_stroke(cairo);
    } else {
        c.cairo_new_path(cairo);
    }
}

fn drawSvgKeycap(cairo: ?*c.cairo_t, svg: ?*c.RsvgHandle, layout: *const KeycapLayout) bool {
    return thm.svgDrawToRect(
        cairo,
        svg,
        @floatFromInt(layout.x),
        @floatFromInt(layout.y),
        @floatFromInt(layout.width),
        @floatFromInt(layout.height),
        "key",
    );
}

fn drawSvgIcon(cairo: ?*c.cairo_t, svg: ?*c.RsvgHandle, layout: *const KeycapLayout, icon_size: c_int) bool {
    return thm.svgDrawToRect(
        cairo,
        svg,
        @floatFromInt(layout.icon_x),
        @floatFromInt(layout.icon_y),
        @floatFromInt(icon_size),
        @floatFromInt(icon_size),
        "icon",
    );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Measure keycap layouts: compute dimensions for each visible keypress
/// and return an array of keycap_layout structs.
pub fn measureKeycaps(
    cairo: ?*c.cairo_t,
    keys: ?*const Keypress,
    config: *const Config,
    theme: *const Theme,
    scale: c_int,
    width: *u32,
    height: *u32,
    out_layouts: *[]KeycapLayout,
) usize {
    width.* = 0;
    height.* = 0;
    out_layouts.* = &.{};

    var key_count: usize = 0;
    var key_iter = keys;
    while (key_iter) |key| {
        key_count += 1;
        key_iter = key.next;
    }
    if (key_count == 0) return 0;

    ensureLayoutArena();
    _ = layout_arena.reset(.retain_capacity);
    const allocator = layout_arena.allocator();
    const layouts = allocator.alloc(KeycapLayout, key_count) catch return 0;

    const s = &keycap_style;
    const padding_x = s.padding_x * scale;
    const padding_y = s.padding_y * scale;
    const gap = s.gap * scale;
    const icon_size = s.icon_size * scale;

    var text_min_width: c_int = 0;
    var text_min_height: c_int = 0;
    var text_min_baseline: c_int = 0;
    pango.getTextSize(cairo, config.font, &text_min_width, &text_min_height, &text_min_baseline, @floatFromInt(scale), "M");

    const min_content_width = @max(icon_size, text_min_width);
    const min_content_height = @max(icon_size, text_min_height);

    var i: usize = 0;
    var max_width: c_int = 0;
    var max_height: c_int = 0;
    key_iter = keys;
    while (key_iter) |key| {
        const layout = &layouts[i];
        i += 1;
        layout.key = key;
        layout.special = key.utf8[0] == 0;
        layout.label = if (layout.special) @as([*:0]const u8, @ptrCast(&key.name)) else @as([*:0]const u8, @ptrCast(&key.utf8));
        layout.icon_name = if (layout.special) icons.specialIconNameC(&key.name) else null;
        layout.icon_svg = icons.cacheGet(theme.base_dir, layout.icon_name);
        pango.getTextSize(cairo, config.font, &layout.text_width, &layout.text_height, &layout.text_baseline, @floatFromInt(scale), "%s", layout.label);

        var content_width = if (layout.icon_svg != null) icon_size else layout.text_width;
        var content_height = if (layout.icon_svg != null) icon_size else layout.text_height;
        if (content_width < min_content_width) content_width = min_content_width;
        if (content_height < min_content_height) content_height = min_content_height;
        layout.width = content_width + padding_x * 2;
        layout.height = content_height + padding_y * 2;
        if (max_width < layout.width) max_width = layout.width;
        if (max_height < layout.height) max_height = layout.height;

        key_iter = key.next;
    }

    var popup_height = max_height;
    for (0..key_count) |idx| {
        const layout = &layouts[idx];
        if ((layout.icon_svg != null or !layout.special) and layout.width > popup_height) {
            popup_height = layout.width;
        }
    }

    var total_width: usize = 0;
    for (0..key_count) |idx| {
        const layout = &layouts[idx];
        layout.height = popup_height;
        layout.width = if (layout.icon_svg != null or !layout.special) popup_height else max_width;
        total_width += @intCast(layout.width);
    }

    width.* = @intCast(total_width + (key_count - 1) * @as(usize, @intCast(gap)));
    height.* = @intCast(popup_height);
    out_layouts.* = layouts;
    return key_count;
}

/// Render measured keycap layouts onto the Cairo context.
pub fn renderKeycaps(
    cairo: ?*c.cairo_t,
    layouts: [*]KeycapLayout,
    key_count: usize,
    config: *const Config,
    theme: *const Theme,
    scale: c_int,
    surface_width: u32,
    content_width: u32,
) void {
    var style = keycap_style_filled;
    style.normal_fg = config.foreground;
    style.special_fg = config.specialfg;

    const gap = style.gap * scale;
    const radius = style.radius * scale;
    const border_width = style.border_width * scale;
    const icon_size = style.icon_size * scale;

    var x: c_int = 0;
    const anchored_right = (config.anchor & 8) != 0;  // ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT = 8
    const anchored_left = (config.anchor & 4) != 0;   // ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT = 4
    if (!anchored_left and surface_width > content_width) {
        x = if (anchored_right)
            @intCast(surface_width - content_width)
        else
            @intCast((surface_width - content_width) / 2);
    }

    for (0..key_count) |i| {
        const layout = &layouts[i];
        layout.x = x;
        layout.y = 0;
        x += layout.width + gap;

        const svg_ok = theme.key_svg != null and !theme.key_svg_failed and drawSvgKeycap(cairo, theme.key_svg, layout);
        if (!svg_ok) {
            if (theme.key_svg != null and !theme.key_svg_failed) {
                std.log.err("Falling back to Cairo keycap background", .{});
                @constCast(theme).key_svg_failed = true;
            }
            drawCairoKeycap(cairo, layout, &style, radius, border_width);
        }

        if (layout.icon_svg != null) {
            layout.icon_x = layout.x + @divTrunc(layout.width - icon_size, 2);
            layout.icon_y = layout.y + @divTrunc(layout.height - icon_size, 2);
            _ = drawSvgIcon(cairo, layout.icon_svg, layout, icon_size);
            continue;
        }

        layout.text_x = layout.x + @divTrunc(layout.width - layout.text_width, 2);
        layout.text_y = layout.y + @divTrunc(layout.height - layout.text_height, 2);
        color.setSourceU32(cairo, if (layout.special) style.special_fg else style.normal_fg);
        c.cairo_move_to(cairo, @floatFromInt(layout.text_x), @floatFromInt(layout.text_y));
        pango.printf(cairo, config.font, @floatFromInt(scale), "%s", layout.label);
    }
}

/// Render keycaps directly to a Cairo context (convenience wrapper).
pub fn renderKeycapsToCairo(
    cairo: ?*c.cairo_t,
    keys: ?*const Keypress,
    config: *const Config,
    theme_param: *const Theme,
    scale: c_int,
    width: *u32,
    height: *u32,
) void {
    c.cairo_set_operator(cairo, c.CAIRO_OPERATOR_SOURCE);
    color.setSourceU32(cairo, config.background);
    c.cairo_paint(cairo);
    c.cairo_set_operator(cairo, c.CAIRO_OPERATOR_OVER);

    var layouts: []KeycapLayout = &.{};
    const key_count = measureKeycaps(cairo, keys, config, theme_param, scale, width, height, &layouts);
    if (layouts.len > 0) {
        renderKeycaps(cairo, layouts.ptr, key_count, config, theme_param, scale, width.*, width.*);
    }
}
