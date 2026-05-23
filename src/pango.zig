const c = @import("c");

/// Scratch buffer for temporary formatted strings (avoids heap allocation).
var format_buffer: [2048]u8 = undefined;

fn getPangoLayout(cairo: ?*c.cairo_t, font: [*c]const u8, text: [*c]const u8, scale: f64) ?*c.PangoLayout {
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

/// Format a printf-style string into the static scratch buffer.
/// Returns a pointer to the NUL-terminated result, or null on truncation.
fn fmtScratch(fmt: [*c]const u8, args: anytype) ?[*c]u8 {
    const printed = c.vsnprintf(&format_buffer, format_buffer.len, fmt, @ptrCast(args));
    if (printed < 0 or @as(usize, @intCast(printed)) >= format_buffer.len) return null;
    return &format_buffer;
}

pub fn getTextSize(cairo: ?*c.cairo_t, font: [*c]const u8, width: *c_int, height: *c_int, baseline: ?*c_int, scale: f64, fmt: [*c]const u8, ...) callconv(.c) void {
    var args = @cVaStart();
    defer @cVaEnd(&args);

    const buffer = fmtScratch(fmt, &args) orelse return;

    const layout = getPangoLayout(cairo, font, buffer, scale) orelse return;
    c.pango_cairo_update_layout(cairo, layout);
    c.pango_layout_get_pixel_size(layout, width, height);
    if (baseline) |out| {
        out.* = @divTrunc(c.pango_layout_get_baseline(layout), c.PANGO_SCALE);
    }
    c.g_object_unref(layout);
}

pub fn printf(cairo: ?*c.cairo_t, font: [*c]const u8, scale: f64, fmt: [*c]const u8, ...) callconv(.c) void {
    var args = @cVaStart();
    defer @cVaEnd(&args);

    const buffer = fmtScratch(fmt, &args) orelse return;

    const layout = getPangoLayout(cairo, font, buffer, scale) orelse return;
    const font_options = c.cairo_font_options_create();
    c.cairo_get_font_options(cairo, font_options);
    c.pango_cairo_context_set_font_options(c.pango_layout_get_context(layout), font_options);
    c.cairo_font_options_destroy(font_options);
    c.pango_cairo_update_layout(cairo, layout);
    c.pango_cairo_show_layout(cairo, layout);
    c.g_object_unref(layout);
}
