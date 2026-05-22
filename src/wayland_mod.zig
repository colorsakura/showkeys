const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const events = @import("event.zig");
const module = @import("module.zig");

const wl = wl_mod.client.wl;
const zwlr = wl_mod.client.zwlr;

const Event = events.Event;
const EventBus = events.EventBus;

// ---------------------------------------------------------------------------
// WaylandModule — wraps the Wayland protocol state and publishes
// compositor events (layer surface, frame, output) to the event bus.
//
// Does NOT hold a reference to `*App` — communicates solely via EventBus.
//
// Owns:
//   - Frame callback lifecycle (surface.frame() / callback.destroy())
//   - Layer surface geometry tracking (width, height, configured flags)
//   - Output tracking (entered output for HiDPI scale)
// ---------------------------------------------------------------------------

pub const WaylandModule = struct {
    /// Embedded module base (provides `publish` convenience).
    base: module.Module = .{},

    // ── Layer surface state ──────────────────────────────────────────
    /// Cached surface dimensions (logical pixels).
    width: u32 = 0,
    height: u32 = 0,
    /// Whether the layer surface has been configured at least once.
    layer_configured: bool = false,
    /// Whether a configure request has been sent and we await a response.
    layer_pending_configure: bool = false,

    // ── Frame scheduling state ───────────────────────────────────────
    /// True between `surface.frame()` commit and the frame_done callback.
    frame_scheduled: bool = false,
    /// True when rendering is pending (new keypress arrived during a
    /// frame callback flight).
    pending_render: bool = false,
    /// Pointer to the active frame callback (destroyed on done).
    frame_callback: ?*wl.Callback = null,

    // ── Output tracking ──────────────────────────────────────────────
    /// HiDPI scale factor of the current output (default 1).
    current_scale: i32 = 1,
    /// Subpixel order of the current output (default 0 = DEFAULT).
    current_subpixel: i32 = 0,

    // ── Public API ───────────────────────────────────────────────────

    /// Initialise the module and register on the event bus.
    pub fn init(self: *WaylandModule, event_bus: *EventBus) void {
        self.base.event_bus = event_bus;
    }

    /// Called when the layer surface receives a configure event.
    pub fn onLayerConfigured(self: *WaylandModule, width: u32, height: u32, serial: u32) void {
        self.width = width;
        self.height = height;
        self.layer_configured = true;
        self.layer_pending_configure = false;
        self.base.publish(.{ .layer_configured = .{
            .width = width,
            .height = height,
            .serial = serial,
        } });
    }

    /// Called when the layer surface is closed.
    pub fn onLayerClosed(self: *WaylandModule) void {
        self.base.publish(.quit);
    }

    /// Called when the surface enters an output.
    pub fn onSurfaceEnteredOutput(self: *WaylandModule, output: ?*wl.Output) void {
        self.base.publish(.{ .surface_entered_output = output });
    }

    /// Called when the frame callback fires (done).
    pub fn onFrameDone(self: *WaylandModule) void {
        self.frame_callback = null;
        self.frame_scheduled = false;
        self.base.publish(.frame_done);
    }

    /// Update output scale information.
    pub fn setOutputScale(self: *WaylandModule, scale: i32) void {
        self.current_scale = scale;
    }

    /// Update output subpixel information.
    pub fn setOutputSubpixel(self: *WaylandModule, subpixel: i32) void {
        self.current_subpixel = subpixel;
    }

    /// Request a frame callback on the given surface and store it.
    /// Returns true if a callback was created.
    pub fn requestFrameCallback(self: *WaylandModule, surface: *wl.Surface, listener_ctx: *anyopaque, listener: events.Callback) bool {
        if (self.frame_scheduled) return false;
        self.frame_callback = surface.frame() catch return false;
        self.frame_callback.?.setListener(*anyopaque, listener, listener_ctx);
        self.frame_scheduled = true;
        return true;
    }

    /// Destroy the current frame callback if one exists.
    pub fn destroyFrameCallback(self: *WaylandModule) void {
        if (self.frame_callback) |cb| {
            cb.destroy();
            self.frame_callback = null;
        }
        self.frame_scheduled = false;
    }

    /// Reset layer surface state (e.g. when the surface is destroyed).
    pub fn resetSurfaceState(self: *WaylandModule) void {
        self.destroyFrameCallback();
        self.width = 0;
        self.height = 0;
        self.layer_configured = false;
        self.layer_pending_configure = false;
        self.current_scale = 1;
        self.current_subpixel = 0;
    }
};
