const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const wl = wl_mod.client.wl;
const zwlr = wl_mod.client.zwlr;
const types = @import("types.zig");
const color = @import("color.zig");
const shm = @import("shm.zig");
const keycap = @import("keycap.zig");

const App = types.App;
const KeycapLayout = types.KeycapLayout;

// ---------------------------------------------------------------------------
// Font options helpers
// ---------------------------------------------------------------------------

fn toCairoSubpixelOrder(subpixel: i32) c.cairo_subpixel_order_t {
    return switch (subpixel) {
        0 => c.CAIRO_SUBPIXEL_ORDER_DEFAULT,
        1 => c.CAIRO_SUBPIXEL_ORDER_RGB,
        2 => c.CAIRO_SUBPIXEL_ORDER_BGR,
        3 => c.CAIRO_SUBPIXEL_ORDER_VRGB,
        4 => c.CAIRO_SUBPIXEL_ORDER_VBGR,
        else => c.CAIRO_SUBPIXEL_ORDER_DEFAULT,
    };
}

fn setupFontOptions(cairo: ?*c.cairo_t, wl_state: *types.Wayland) void {
    c.cairo_set_antialias(cairo, c.CAIRO_ANTIALIAS_BEST);
    const fo = c.cairo_font_options_create();
    c.cairo_font_options_set_hint_style(fo, c.CAIRO_HINT_STYLE_FULL);
    c.cairo_font_options_set_antialias(fo, c.CAIRO_ANTIALIAS_SUBPIXEL);
    if (wl_state.output) |output| {
        c.cairo_font_options_set_subpixel_order(fo, toCairoSubpixelOrder(output.subpixel));
    }
    c.cairo_set_font_options(cairo, fo);
    c.cairo_font_options_destroy(fo);
}

// ---------------------------------------------------------------------------
// Destroy the layer surface (no circular dep — standalone logic)
// ---------------------------------------------------------------------------

pub fn destroyLayerSurface(wayland: *types.Wayland) void {
    if (wayland.frame_callback) |callback| {
        callback.destroy();
        wayland.frame_callback = null;
    }
    wayland.frame_scheduled = false;
    if (wayland.layer_surface) |layer_surface| {
        layer_surface.destroy();
        wayland.layer_surface = null;
    }
    if (wayland.surface) |surface| {
        surface.destroy();
        wayland.surface = null;
    }
    wayland.output = null;
    wayland.width = 0;
    wayland.height = 0;
    wayland.layer_configured = false;
    wayland.layer_pending_configure = false;
}

// ---------------------------------------------------------------------------
// Frame callback listener (called from wayland.zig via export)
// ---------------------------------------------------------------------------

/// Frame-done callback — called when the compositor has processed the
/// committed surface state.  Triggers a redraw if the app is dirty.
fn frameListener(callback: *wl.Callback, event: wl.Callback.Event, data: *App) void {
    switch (event) {
        .done => {
            const wayland = &data.wayland;
            callback.destroy();
            wayland.frame_callback = null;
            wayland.frame_scheduled = false;

            if (wayland.dirty and wayland.layer_configured and wayland.surface != null) {
                wayland.dirty = false;
                renderFrame(data);
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Main render entry point
// ---------------------------------------------------------------------------

/// Render a single frame: measure keycaps, resize if needed,
/// acquire an SHM buffer, draw keycaps, and commit to the surface.
pub fn renderFrame(app: *App) void {
    const wl_state = &app.wayland;
    const scale: c_int = if (wl_state.output) |output| output.scale else 1;
    var width: u32 = 0;
    var height: u32 = 0;

    // Phase 1: measure keycap sizes using a temporary Cairo context.
    const tmp_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
    const cairo = c.cairo_create(tmp_surface);
    defer {
        c.cairo_destroy(cairo);
        c.cairo_surface_destroy(tmp_surface);
    }
    setupFontOptions(cairo, wl_state);

    var layouts: []KeycapLayout = &.{};
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
    const surface_too_small = target_width > wl_state.width or target_height > wl_state.height;
    const surface_too_large = target_height != wl_state.height or wl_state.width > reserved_width or wl_state.width == 0;

    if (surface_too_small or surface_too_large) {
        if (key_count == 0 or width == 0 or height == 0) {
            destroyLayerSurface(wl_state);
        } else if (wl_state.layer_surface) |layer_surface| {
            layer_surface.setSize(reserved_width, target_height);
        }
        if (wl_state.surface) |surface| surface.commit();
        return;
    }

    if (key_count == 0 or height == 0) {
        return;
    }

    // Phase 2: acquire an SHM buffer and render.
    wl_state.current_buffer = shm.getNextBuffer(
        wl_state.shm orelse return,
        &wl_state.buffers,
        wl_state.width * @as(u32, @intCast(scale)),
        wl_state.height * @as(u32, @intCast(scale)),
    );
    const current_buffer = wl_state.current_buffer orelse return;
    const cairo_ctx: ?*c.cairo_t = current_buffer.cairo;

    c.cairo_save(cairo_ctx);
    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_CLEAR);
    c.cairo_paint(cairo_ctx);
    c.cairo_restore(cairo_ctx);

    setupFontOptions(cairo_ctx, wl_state);

    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_SOURCE);
    color.setSourceU32(cairo_ctx, app.config.background);
    c.cairo_paint(cairo_ctx);
    c.cairo_set_operator(cairo_ctx, c.CAIRO_OPERATOR_OVER);

    keycap.renderKeycaps(
        cairo_ctx,
        layouts.ptr,
        key_count,
        &app.config,
        &app.theme,
        scale,
        wl_state.width * @as(u32, @intCast(scale)),
        width,
    );

    c.cairo_surface_flush(current_buffer.surface);

    const surface = wl_state.surface orelse return;
    surface.setBufferScale(scale);
    surface.attach(current_buffer.buffer, 0, 0);
    surface.damageBuffer(
        0,
        0,
        @intCast(wl_state.width * @as(u32, @intCast(scale))),
        @intCast(wl_state.height * @as(u32, @intCast(scale))),
    );

    wl_state.frame_callback = surface.frame() catch return;
    wl_state.frame_callback.?.setListener(*App, frameListener, app);
    wl_state.frame_scheduled = true;

    surface.commit();
}
