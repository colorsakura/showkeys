const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const events = @import("event.zig");
const module = @import("module.zig");
const types = @import("types.zig");
const color = @import("color.zig");
const shm = @import("shm.zig");
const keycap = @import("keycap.zig");

const wl = wl_mod.client.wl;

const App = types.App;
const KeycapLayout = types.KeycapLayout;

// ---------------------------------------------------------------------------
// RenderModule — manages frame scheduling and rendering.
//
// Responsibilities:
//   - Subscribe to `request_render` and `frame_done` events.
//   - On `request_render`: measure keycaps, acquire SHM buffer, draw,
//     commit surface, schedule frame callback.
//   - On `frame_done`: check if a new render is pending, if so render again.
//   - Manage the frame callback lifecycle to avoid over-committing.
//
// References:
//   - Wayland surface + layer surface (owned by wayland.zig / Wayland struct)
//   - SHM pool + buffers (owned by wayland.zig / Wayland struct)
//   - Key list + config (owned by App)
//   - Theme (owned by App)
//
// RenderModule does NOT own any Wayland objects — it borrows them from
// the App struct via the context pointer.
// ---------------------------------------------------------------------------

/// Opaque context alias for the rendering state.
/// Points to `types.App`, but RenderModule accesses only the fields it needs.
const RenderCtx = types.App;

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
    const font_options = c.cairo_font_options_create();
    c.cairo_font_options_set_hint_style(font_options, c.CAIRO_HINT_STYLE_FULL);
    c.cairo_font_options_set_antialias(font_options, c.CAIRO_ANTIALIAS_SUBPIXEL);
    if (wl_state.output) |output| {
        c.cairo_font_options_set_subpixel_order(font_options, toCairoSubpixelOrder(output.subpixel));
    }
    c.cairo_set_font_options(cairo, font_options);
    c.cairo_font_options_destroy(font_options);
}

// ---------------------------------------------------------------------------
// Frame callback listener
// ---------------------------------------------------------------------------

/// Frame-done callback — called by the compositor when it has finished
/// processing the committed surface state.
fn frameCallback(_: *wl.Callback, event: wl.Callback.Event, data: *App) void {
    switch (event) {
        .done => {
            const app = data;
            app.render_mod.frame_callback = null;
            app.render_mod.frame_scheduled = false;
            app.event_bus.publish(.frame_done);
        },
    }
}

// ---------------------------------------------------------------------------
// Public API — called via event bus or directly from main loop
// ---------------------------------------------------------------------------

/// Event handler for the render module.
pub fn handleEvent(ctx: *anyopaque, event: events.Event) void {
    const app: *App = @ptrCast(@alignCast(ctx));

    switch (event) {
        .request_render => {
            requestRender(app);
        },
        .frame_done => {
            handleFrameDone(app);
        },
        .layer_configured => {
            // The Wayland state is already updated in the listener;
            // nothing extra needed here.  If we had a pending render,
            // it will be picked up by the next request_render.
        },
        else => {},
    }
}

/// Called when a render is requested (e.g. after a keypress or
/// layer configure).  Schedules a frame if one is not already in flight.
fn requestRender(app: *App) void {
    const wl_state = &app.wayland;
    const rmod = &app.render_mod;

    if (!wl_state.layer_configured or wl_state.surface == null) {
        // Not ready yet — mark pending and return.
        // The caller (app.zig :: requestRender) should have already
        // called wl.requestLayerConfigure; if not, do it here.
        rmod.pending_render = true;
        return;
    }

    if (rmod.frame_scheduled) {
        // A frame is already in flight — defer until frame_done.
        rmod.pending_render = true;
        return;
    }

    // Ready to render now.
    rmod.pending_render = false;
    renderFrame(app);
}

/// Called when the compositor signals that a frame has been presented.
fn handleFrameDone(app: *App) void {
    const rmod = &app.render_mod;

    // If a render was requested while the last frame was in flight,
    // render again immediately.
    if (rmod.pending_render and app.wayland.layer_configured and app.wayland.surface != null) {
        rmod.pending_render = false;
        renderFrame(app);
    }
}

// ---------------------------------------------------------------------------
// Core render logic
// ---------------------------------------------------------------------------

/// Render a single frame: measure keycaps, resize if needed,
/// acquire an SHM buffer, draw keycaps, and commit to the surface.
fn renderFrame(app: *App) void {
    const wl_state = &app.wayland;
    const rmod = &app.render_mod;
    const scale: c_int = if (wl_state.output) |output| output.scale else 1;
    var width: u32 = 0;
    var height: u32 = 0;

    // Phase 1: measure keycap sizes using a persistent Cairo context.
    ensureMeasureSurface(rmod);
    ensureLayoutArena(rmod);
    _ = rmod.layout_arena.reset(.retain_capacity);
    setupFontOptions(rmod.measure_cairo, wl_state);

    var layouts: []KeycapLayout = &.{};
    const key_count = keycap.measureKeycaps(
        rmod.layout_arena.allocator(),
        rmod.measure_cairo,
        app.keys.head,
        &app.config,
        &app.theme,
        scale,
        &width,
        &height,
        &layouts,
    );

    const target_width = if (key_count > 0) width / @as(u32, @intCast(scale)) else 0;
    const target_height = height / @as(u32, @intCast(scale));

    // ── Compute the reserved width for max_keys ──────────────────────────
    const gap_scaled: u32 = @intCast(@as(c_int, @intCast(keycap.default_gap)) * scale);
    const key_count_u32: u32 = @intCast(key_count);
    const max_keys_u32: u32 = @intCast(@max(app.config.max_keys, 0));
    const key_width_sum = if (key_count > 0) width - (key_count_u32 - 1) * gap_scaled else 0;
    const avg_key_width = if (key_count > 0) key_width_sum / key_count_u32 else 0;
    const reserved_scaled = avg_key_width * max_keys_u32 + (max_keys_u32 - 1) * gap_scaled;
    const reserved_width = reserved_scaled / @as(u32, @intCast(scale));
    const surface_fits = target_width <= wl_state.width and target_height <= wl_state.height;
    const surface_matches = target_height == wl_state.height and wl_state.width <= reserved_width and wl_state.width > 0;

    if (!surface_fits or !surface_matches) {
        if (key_count == 0 or width == 0 or height == 0) {
            resetSurfaceState(app);
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

    rmod.shift_active = keycap.renderKeycaps(
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

    // Schedule the next frame callback via the render module.
    _ = requestFrameCallback(rmod, surface, app);

    surface.commit();
}

// ---------------------------------------------------------------------------
// RenderModule resource management
// ---------------------------------------------------------------------------

/// Lazily initialise the persistent measure surface and Cairo context.
fn ensureMeasureSurface(rmod: *types.RenderModState) void {
    if (rmod.measure_surface == null) {
        rmod.measure_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
        rmod.measure_cairo = c.cairo_create(rmod.measure_surface);
    }
}

/// Lazily initialise the layout arena for transient keycap layout arrays.
fn ensureLayoutArena(rmod: *types.RenderModState) void {
    if (!rmod.layout_arena_initialized) {
        rmod.layout_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        rmod.layout_arena_initialized = true;
    }
}

// ---------------------------------------------------------------------------
// RenderModule methods (operate on the render_mod field of App)
// ---------------------------------------------------------------------------

/// Request a frame callback on the given surface.
/// Returns true if a callback was created.
fn requestFrameCallback(rmod: *types.RenderModState, surface: *wl.Surface, app: *App) bool {
    if (rmod.frame_scheduled) return false;
    rmod.frame_callback = surface.frame() catch return false;
    rmod.frame_callback.?.setListener(*App, frameCallback, app);
    rmod.frame_scheduled = true;
    return true;
}

/// Reset layer surface state (e.g. when the surface is destroyed).
fn resetSurfaceState(app: *App) void {
    @import("wayland.zig").destroyLayerSurface(app);
}
