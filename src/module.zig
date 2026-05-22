const events = @import("event.zig");

// ---------------------------------------------------------------------------
// Module interface — a module is any struct that embeds ModuleBase and
// implements the required lifecycle methods.
//
// Usage:
//   pub const MyModule = struct {
//       base: ModuleBase(.MyModule) = .{},
//       ...
//   };
// ---------------------------------------------------------------------------

/// Minimal base that every module embeds.
/// Provides direct access to the event bus for publishing events.
/// The `name` parameter is used for compile-time diagnostics.
///
/// Example:
/// ```zig
/// pub const InputModule = struct {
///     base: ModuleBase(.input) = .{},
///     ...
/// };
/// ```
pub fn ModuleBase(comptime name: @TypeOf(.enum_literal)) type {
    _ = name;
    return struct {
        /// Event bus reference — set during module initialisation.
        event_bus: *events.EventBus = undefined,

        /// Convenience: publish an event on the bus.
        pub fn publish(self: *@This(), event: events.Event) void {
            self.event_bus.publish(event);
        }
    };
}

/// Alias for the default module base (backwards compatible).
pub const Module = ModuleBase(.generic);
