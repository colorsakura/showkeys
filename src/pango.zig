const c = @import("c");

export fn get_pango_layout(cairo: ?*c.cairo_t, font: [*c]const u8, text: [*c]const u8, scale: f64) ?*c.PangoLayout {
    const layout = c.pango_cairo_create_layout(cairo) orelse return null;
    const attrs = c.pango_attr_list_new() orelse return layout;
    c.pango_layout_set_text(layout, text, -1);
    c.pango_attr_list_insert(attrs, c.pango_attr_scale_new(scale));
    const desc = c.pango_font_description_from_string(font);
    c.pango_layout_set_font_description(layout, desc);
    c.pango_layout_set_single_paragraph_mode(layout, 1);
    c.pango_layout_set_attributes(layout, attrs);
    c.pango_attr_list_unref(attrs);
    c.pango_font_description_free(desc);
    return layout;
}

fn allocFormatted(fmt: [*c]const u8, args: anytype) ?[*c]u8 {
    var length_args = @cVaCopy(args);
    defer @cVaEnd(&length_args);

    const printed = c.vsnprintf(null, 0, fmt, @ptrCast(&length_args));
    if (printed < 0) {
        return null;
    }

    const length: usize = @as(usize, @intCast(printed)) + 1;
    const allocation = c.malloc(length) orelse return null;
    const buf: [*c]u8 = @ptrCast(allocation);
    _ = c.vsnprintf(buf, length, fmt, @ptrCast(args));
    return buf;
}

export fn get_text_size(cairo: ?*c.cairo_t, font: [*c]const u8, width: *c_int, height: *c_int, baseline: ?*c_int, scale: f64, fmt: [*c]const u8, ...) callconv(.c) void {
    var args = @cVaStart();
    defer @cVaEnd(&args);

    const buf = allocFormatted(fmt, &args) orelse return;
    defer c.free(buf);

    const layout = get_pango_layout(cairo, font, buf, scale) orelse return;
    c.pango_cairo_update_layout(cairo, layout);
    c.pango_layout_get_pixel_size(layout, width, height);
    if (baseline) |out| {
        out.* = @divTrunc(c.pango_layout_get_baseline(layout), c.PANGO_SCALE);
    }
    c.g_object_unref(layout);
}

export fn pango_printf(cairo: ?*c.cairo_t, font: [*c]const u8, scale: f64, fmt: [*c]const u8, ...) callconv(.c) void {
    var args = @cVaStart();
    defer @cVaEnd(&args);

    const buf = allocFormatted(fmt, &args) orelse return;
    defer c.free(buf);

    const layout = get_pango_layout(cairo, font, buf, scale) orelse return;
    const fo = c.cairo_font_options_create();
    c.cairo_get_font_options(cairo, fo);
    c.pango_cairo_context_set_font_options(c.pango_layout_get_context(layout), fo);
    c.cairo_font_options_destroy(fo);
    c.pango_cairo_update_layout(cairo, layout);
    c.pango_cairo_show_layout(cairo, layout);
    c.g_object_unref(layout);
}
