const std = @import("std");
const events = @import("event.zig");

// ---------------------------------------------------------------------------
// Module interface — each subsystem publishes an event handler so the main
// loop can dispatch events without knowing subsystem internals.
//
// Every module struct contains a pointer to the event bus, so it can
// publish events during its own processing.  The bus itself is owned by
// the App struct.
// ---------------------------------------------------------------------------

/// Opaque base that every module embeds.  Provides the `publish` helper.
pub const Module = struct {
    /// Event bus reference — set during module initialisation.
    event_bus: *events.EventBus = undefined,

    /// Convenience: publish an event on the bus.
    pub fn publish(self: *Module, event: events.Event) void {
        self.event_bus.publish(event);
    }
};
