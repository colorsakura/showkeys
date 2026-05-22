const std = @import("std");
const keys = @import("keys.zig");
const wl_mod = @import("wayland");
const wl = wl_mod.client.wl;

const Keypress = keys.Keypress;

// ---------------------------------------------------------------------------
// Event — global event type for the application event bus.
//
// Every module publishes events to the bus; other modules subscribe and
// react.  This replaces the implicit dirty-flag / inline-callback wiring
// between input, wayland, render, and the main loop.
// ---------------------------------------------------------------------------

/// Scroll direction for pointer axis events.
pub const ScrollDirection = enum(u8) {
    up,
    down,
    left,
    right,
};

/// Top-level event discriminated by tag.  Each variant carries the minimum
/// data the receiver needs; no module receives a raw `*App` pointer.
pub const Event = union(enum) {
    // ── Input events ─────────────────────────────────────────────────
    /// A keyboard key was pressed.  Ownership of `keypress` transfers
    /// to the subscriber (it must eventually be freed via KeyList).
    key_pressed: *Keypress,

    /// A pointer button was pressed.
    pointer_button: []const u8,

    /// A scroll wheel event occurred.
    pointer_scroll: ScrollDirection,

    /// A new xkb keymap was received from the compositor.
    keymap_updated: struct {
        format: u32,
        fd: i32,
        size: u32,
    },

    // ── Wayland events ───────────────────────────────────────────────
    /// The layer surface has been configured with the given dimensions.
    layer_configured: struct { width: u32, height: u32, serial: u32 },

    /// The layer surface was closed by the compositor.
    layer_closed,

    /// The surface entered an output.
    surface_entered_output: ?*wl.Output,

    /// A frame was completed — the compositor has presented the last
    /// committed buffer.
    frame_done,

    // ── Timing events ────────────────────────────────────────────────
    /// Periodic tick used for animation progression and expiry checks.
    /// Published by the main loop when the animation/expiry timer fires.
    tick: struct {
        /// Current monotonic time in nanoseconds.
        now_ns: i64,
    },

    /// The most recent keypress has exceeded its display timeout.
    key_expired,

    // ── Application-lifecycle events ─────────────────────────────────
    /// Signal that the event loop should exit.
    quit,

    /// Request a render pass on the next frame.
    ///
    /// Unlike `frame_done`, this is an *internal* request that the
    /// main loop should schedule a frame callback and draw.
    request_render,
};

// ---------------------------------------------------------------------------
// ModuleId — unique identifier for each subscriber
// ---------------------------------------------------------------------------

pub const ModuleId = enum(u8) {
    app_mod,
    input_mod,
    wayland_mod,
    render_mod,
    _,
};

// ---------------------------------------------------------------------------
// EventBus — simple publish/subscribe dispatcher
//
// Design decisions:
//   - Contiguous array of (module_id, callback) pairs so iteration
//     stays cache-friendly on the publish path.
//   - No dynamic filtering per subscriber; every subscriber receives
//     every event and filters by tag in the callback.
//   - No allocation during publish (only during subscribe).
//   - Callback takes a generic `*anyopaque` context pointer so each
//     module can pass its own state struct without a global.
// ---------------------------------------------------------------------------

/// Callback signature for event subscribers.
pub const Callback = *const fn (ctx: *anyopaque, event: Event) void;

/// A single subscriber entry.
const Subscription = struct {
    module_id: ModuleId,
    ctx: *anyopaque,
    callback: Callback,
};

/// Maximum number of subscribers the bus can hold (fixed at init time).
/// This avoids dynamic resizing during publish.
pub const max_subscribers: u8 = 8;

pub const EventBus = struct {
    subscriptions: [max_subscribers]Subscription = undefined,
    subscriber_count: u8 = 0,

    /// Subscribe a module to all events.
    /// The `ctx` pointer is passed back on every callback invocation.
    pub fn subscribe(self: *EventBus, module_id: ModuleId, ctx: *anyopaque, callback: Callback) void {
        std.debug.assert(self.subscriber_count < max_subscribers);
        const idx = self.subscriber_count;
        self.subscriber_count += 1;
        self.subscriptions[idx] = .{
            .module_id = module_id,
            .ctx = ctx,
            .callback = callback,
        };
    }

    /// Publish an event to all subscribers, in subscription order.
    pub fn publish(self: *EventBus, event: Event) void {
        var i: u8 = 0;
        while (i < self.subscriber_count) : (i += 1) {
            const sub = &self.subscriptions[i];
            sub.callback(sub.ctx, event);
        }
    }
};
