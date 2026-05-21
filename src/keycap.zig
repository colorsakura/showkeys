const c = @import("c");

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

fn roundedRectangle(cairo: ?*c.cairo_t, x: f64, y: f64, w: f64, h: f64, radius: f64) void {
    var r = radius;
    if (r > w / 2.0) {
        r = w / 2.0;
    }
    if (r > h / 2.0) {
        r = h / 2.0;
    }

    c.cairo_new_sub_path(cairo);
    c.cairo_arc(cairo, x + w - r, y + r, r, -1.5707963267948966, 0.0);
    c.cairo_arc(cairo, x + w - r, y + h - r, r, 0.0, 1.5707963267948966);
    c.cairo_arc(cairo, x + r, y + h - r, r, 1.5707963267948966, 3.141592653589793);
    c.cairo_arc(cairo, x + r, y + r, r, 3.141592653589793, 4.71238898038469);
    c.cairo_close_path(cairo);
}

fn drawCairoKeycap(cairo: ?*c.cairo_t, layout: *allowzero const c.struct_keycap_layout, style: *const KeycapStyle, radius: c_int, border_width: c_int) void {
    roundedRectangle(
        cairo,
        @floatFromInt(layout.x),
        @floatFromInt(layout.y),
        @floatFromInt(layout.width),
        @floatFromInt(layout.height),
        @floatFromInt(radius),
    );
    c.wsk_cairo_set_source_u32(cairo, if (layout.special) style.special_bg else style.normal_bg);
    c.cairo_fill_preserve(cairo);

    if (border_width > 0) {
        c.cairo_set_line_width(cairo, @floatFromInt(border_width));
        c.wsk_cairo_set_source_u32(cairo, style.border);
        c.cairo_stroke(cairo);
    } else {
        c.cairo_new_path(cairo);
    }
}

fn drawSvgKeycap(cairo: ?*c.cairo_t, svg: ?*c.RsvgHandle, layout: *allowzero const c.struct_keycap_layout) bool {
    return c.wsk_svg_draw_to_rect(
        cairo,
        svg,
        @floatFromInt(layout.x),
        @floatFromInt(layout.y),
        @floatFromInt(layout.width),
        @floatFromInt(layout.height),
        "key",
    );
}

fn drawSvgIcon(cairo: ?*c.cairo_t, svg: ?*c.RsvgHandle, layout: *allowzero const c.struct_keycap_layout, icon_size: c_int) bool {
    return c.wsk_svg_draw_to_rect(
        cairo,
        svg,
        @floatFromInt(layout.icon_x),
        @floatFromInt(layout.icon_y),
        @floatFromInt(icon_size),
        @floatFromInt(icon_size),
        "icon",
    );
}

export fn wsk_measure_keycaps(
    cairo: ?*c.cairo_t,
    keys: [*c]const c.struct_wsk_keypress,
    config: *const c.struct_wsk_config,
    theme: *c.struct_wsk_theme,
    scale: c_int,
    width: *u32,
    height: *u32,
    out_layouts: *[*c]c.struct_keycap_layout,
) usize {
    width.* = 0;
    height.* = 0;
    out_layouts.* = null;

    var key_count: usize = 0;
    var key_iter = keys;
    while (key_iter) |key| {
        key_count += 1;
        key_iter = key[0].next;
    }
    if (key_count == 0) {
        return 0;
    }

    const raw_layouts = c.calloc(key_count, @sizeOf(c.struct_keycap_layout)) orelse return 0;
    const layouts: [*c]c.struct_keycap_layout = @ptrCast(@alignCast(raw_layouts));

    const style: KeycapStyle = .{
        .padding_x = 12,
        .padding_y = 6,
        .gap = 6,
        .radius = 8,
        .border_width = 1,
        .icon_size = 32,
    };

    const padding_x = style.padding_x * scale;
    const padding_y = style.padding_y * scale;
    const gap = style.gap * scale;
    const icon_size = style.icon_size * scale;

    var text_min_width: c_int = 0;
    var text_min_height: c_int = 0;
    var text_min_baseline: c_int = 0;
    c.get_text_size(cairo, config.font, &text_min_width, &text_min_height, &text_min_baseline, @floatFromInt(scale), "M");

    const min_content_width = if (icon_size > text_min_width) icon_size else text_min_width;
    const min_content_height = if (icon_size > text_min_height) icon_size else text_min_height;

    var i: usize = 0;
    var max_width: c_int = 0;
    var max_height: c_int = 0;
    key_iter = keys;
    while (key_iter) |key| {
        const layout = &layouts[i];
        i += 1;
        layout.key = key;
        layout.special = key[0].utf8[0] == 0;
        layout.label = if (layout.special) &key[0].name else &key[0].utf8;
        layout.icon_name = if (layout.special) c.wsk_special_icon_name(&key[0].name) else null;
        layout.icon_svg = c.wsk_icon_cache_get(&theme.icons, theme.base_dir, layout.icon_name);
        c.get_text_size(cairo, config.font, &layout.text_width, &layout.text_height, &layout.text_baseline, @floatFromInt(scale), "%s", layout.label);

        var content_width = if (layout.icon_svg != null) icon_size else layout.text_width;
        var content_height = if (layout.icon_svg != null) icon_size else layout.text_height;
        if (content_width < min_content_width) {
            content_width = min_content_width;
        }
        if (content_height < min_content_height) {
            content_height = min_content_height;
        }
        layout.width = content_width + padding_x * 2;
        layout.height = content_height + padding_y * 2;
        if (max_width < layout.width) {
            max_width = layout.width;
        }
        if (max_height < layout.height) {
            max_height = layout.height;
        }

        key_iter = key[0].next;
    }

    var popup_height = max_height;
    i = 0;
    while (i < key_count) : (i += 1) {
        const layout = &layouts[i];
        if ((layout.icon_svg != null or !layout.special) and layout.width > popup_height) {
            popup_height = layout.width;
        }
    }

    var total_width: usize = 0;
    i = 0;
    while (i < key_count) : (i += 1) {
        const layout = &layouts[i];
        layout.height = popup_height;
        if (layout.icon_svg != null or !layout.special) {
            layout.width = popup_height;
        } else {
            layout.width = max_width;
        }
        total_width += @intCast(layout.width);
    }

    width.* = @intCast(total_width + (key_count - 1) * @as(usize, @intCast(gap)));
    height.* = @intCast(popup_height);
    out_layouts.* = layouts;
    return key_count;
}

export fn wsk_render_keycaps(
    cairo: ?*c.cairo_t,
    layouts: [*c]c.struct_keycap_layout,
    key_count: usize,
    config: *const c.struct_wsk_config,
    theme: *c.struct_wsk_theme,
    scale: c_int,
    surface_width: u32,
    content_width: u32,
) void {
    const style: KeycapStyle = .{
        .padding_x = 12,
        .padding_y = 6,
        .gap = 6,
        .radius = 8,
        .border_width = 1,
        .icon_size = 32,
        .normal_bg = 0x222222CC,
        .normal_fg = config.foreground,
        .special_bg = 0x444444CC,
        .special_fg = config.specialfg,
        .border = 0xFFFFFF33,
    };

    const gap = style.gap * scale;
    const radius = style.radius * scale;
    const border_width = style.border_width * scale;
    const icon_size = style.icon_size * scale;

    var x: c_int = 0;
    if ((config.anchor & c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT) != 0 and
        (config.anchor & c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT) == 0 and
        surface_width > content_width)
    {
        x = @intCast(surface_width - content_width);
    } else if ((config.anchor & c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT) == 0 and
        (config.anchor & c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT) == 0 and
        surface_width > content_width)
    {
        x = @intCast((surface_width - content_width) / 2);
    }

    var i: usize = 0;
    while (i < key_count) : (i += 1) {
        const layout = &layouts[i];
        layout.x = x;
        layout.y = 0;
        x += layout.width + gap;

        if (theme.key_svg == null or theme.key_svg_failed or !drawSvgKeycap(cairo, theme.key_svg, layout)) {
            if (theme.key_svg != null and !theme.key_svg_failed) {
                _ = c.fprintf(c.stderr, "Falling back to Cairo keycap background\n");
                theme.key_svg_failed = true;
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
        c.wsk_cairo_set_source_u32(cairo, if (layout.special) style.special_fg else style.normal_fg);
        c.cairo_move_to(cairo, @floatFromInt(layout.text_x), @floatFromInt(layout.text_y));
        c.pango_printf(cairo, config.font, @floatFromInt(scale), "%s", layout.label);
    }
}

export fn wsk_render_keycaps_to_cairo(
    cairo: ?*c.cairo_t,
    keys: [*c]const c.struct_wsk_keypress,
    config: *const c.struct_wsk_config,
    theme: *c.struct_wsk_theme,
    scale: c_int,
    width: *u32,
    height: *u32,
) void {
    c.cairo_set_operator(cairo, c.CAIRO_OPERATOR_SOURCE);
    c.wsk_cairo_set_source_u32(cairo, config.background);
    c.cairo_paint(cairo);
    c.cairo_set_operator(cairo, c.CAIRO_OPERATOR_OVER);

    var layouts: [*c]c.struct_keycap_layout = null;
    const key_count = wsk_measure_keycaps(cairo, keys, config, theme, scale, width, height, &layouts);
    if (layouts != null) {
        wsk_render_keycaps(cairo, layouts, key_count, config, theme, scale, width.*, width.*);
        c.free(layouts);
    }
}
