const std = @import("std");
const c = @import("c");
const color = @import("color.zig");
const shm = @import("shm.zig");
const keycap = @import("keycap.zig");
const wl_mod = @import("wayland.zig");

// ---------------------------------------------------------------------------
// Font options helpers
// ---------------------------------------------------------------------------

fn toCairoSubpixelOrder(subpixel: c.enum_wl_output_subpixel) c.cairo_subpixel_order_t {
    return switch (subpixel) {
        c.WL_OUTPUT_SUBPIXEL_HORIZONTAL_RGB => c.CAIRO_SUBPIXEL_ORDER_RGB,
        c.WL_OUTPUT_SUBPIXEL_HORIZONTAL_BGR => c.CAIRO_SUBPIXEL_ORDER_BGR,
        c.WL_OUTPUT_SUBPIXEL_VERTICAL_RGB => c.CAIRO_SUBPIXEL_ORDER_VRGB,
        c.WL_OUTPUT_SUBPIXEL_VERTICAL_BGR => c.CAIRO_SUBPIXEL_ORDER_VBGR,
        else => c.CAIRO_SUBPIXEL_ORDER_DEFAULT,
    };
}

fn setupFontOptions(cairo: ?*c.cairo_t, wl: *c.struct_wsk_wayland) void {
    c.cairo_set_antialias(cairo, c.CAIRO_ANTIALIAS_BEST);
    const fo = c.cairo_font_options_create();
    c.cairo_font_options_set_hint_style(fo, c.CAIRO_HINT_STYLE_FULL);
    c.cairo_font_options_set_antialias(fo, c.CAIRO_ANTIALIAS_SUBPIXEL);
    if (wl.output) |output| {
        c.cairo_font_options_set_subpixel_order(fo, toCairoSubpixelOrder(output[0].subpixel));
    }
    c.cairo_set_font_options(cairo, fo);
    c.cairo_font_options_destroy(fo);
}

// ---------------------------------------------------------------------------
// Frame rendering — C ABI
// ---------------------------------------------------------------------------

/// Render a single frame: measure keycaps, resize if needed,
/// acquire an SHM buffer, draw keycaps, and commit to the surface.
pub fn renderFrame(app: *c.struct_wsk_app) void {
    const wl = &app.wayland;
    const scale: c_int = if (wl.output) |output| output[0].scale else 1;
    var width: u32 = 0;
    var height: u32 = 0;

    // Phase 1: measure keycap sizes using a temporary Cairo context.
    const tmp_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
    const cairo = c.cairo_create(tmp_surface);
    defer {
        c.cairo_destroy(cairo);
        c.cairo_surface_destroy(tmp_surface);
    }
    setupFontOptions(cairo, wl);

    var layouts: [*c]c.struct_keycap_layout = null;
    const key_count = keycap.measureKeycaps(
        cairo,
        app.keys.head,
        &app.config,
        &app.theme,
        scale,
        &width,
        &height,
        &layouts,
    );

    const target_width = width / @as(u32, @intCast(scale));
    const target_height = height / @as(u32, @intCast(scale));
    const reserved_width = target_width * @as(u32, @intCast(app.config.max_keys));
    const surface_too_small = target_width > wl.width or target_height > wl.height;
    const surface_too_large = target_height != wl.height or wl.width > reserved_width or wl.width == 0;

    if (surface_too_small or surface_too_large) {
        defer c.free(layouts);
        if (key_count == 0 or width == 0 or height == 0) {
            wl_mod.destroyLayerSurface(wl);
        } else {
            c.zwlr_layer_surface_v1_set_size(wl.layer_surface, reserved_width, target_height);
        }
        if (wl.surface != null) c.wl_surface_commit(wl.surface);
        return;
    }

    if (key_count == 0 or height == 0) {
        c.free(layouts);
        return;
    }

    // Phase 2: acquire an SHM buffer and render.
    wl.current_buffer = shm.getNextBuffer(
        wl.shm,
        &wl.buffers,
        wl.width * @as(u32, @intCast(scale)),
        wl.height * @as(u32, @intCast(scale)),
    );
    if (wl.current_buffer == null) {
        c.free(layouts);
        return;
    }
    const cairo_ctx: ?*c.cairo_t = wl.current_buffer[0].cairo;

    c.cairo_save(cairo_ctx);
    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_paint(cairo_ctx);
    c.cairo_restore(cairo_ctx);

    setupFontOptions(cairo_ctx, wl);

    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_SOURCE);
    color.setSourceU32(cairo_ctx, app.config.background);
    c.cairo_paint(cairo_ctx);
    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_OVER);

    keycap.renderKeycaps(
        cairo_ctx,
        layouts,
        key_count,
        &app.config,
        &app.theme,
        scale,
        wl.width * @as(u32, @intCast(scale)),
        width,
    );
    c.free(layouts);

    c.cairo_surface_flush(wl.current_buffer[0].surface);

    c.wl_surface_set_buffer_scale(wl.surface, scale);
    c.wl_surface_attach(wl.surface, wl.current_buffer[0].buffer, 0, 0);
    c.wl_surface_damage_buffer(
        wl.surface,
        0,
        0,
        @intCast(wl.width * @as(u32, @intCast(scale))),
        @intCast(wl.height * @as(u32, @intCast(scale))),
    );

    wl.frame_callback = c.wl_surface_frame(wl.surface);
    _ = c.wl_callback_add_listener(wl.frame_callback, &c.frame_listener, app);
    wl.frame_scheduled = true;

    c.wl_surface_commit(wl.surface);
}
