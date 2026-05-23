const std = @import("std");
const c = @import("c");
const devmgr = @import("devmgr.zig");
const errno = @import("errno.zig");

// ---------------------------------------------------------------------------
// Raw input subsystem — libinput context factory and C ABI bridge.
//
// This module owns the libinput udev context and its open_restricted
// / close_restricted callbacks (which delegate to the privileged device
// manager via a socket pair).
//
// It does NOT own xkb state, event dispatch, or the event bus — those
// are handled by InputModule (input_mod.zig).
// ---------------------------------------------------------------------------

/// libinput open_restricted callback — delegates to the privileged
/// device manager via the stored file descriptor.
fn libinputOpenRestricted(path: [*c]const u8, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
    const fd: *c_int = @ptrCast(@alignCast(data.?));
    return devmgr.open(fd.*, path);
}

/// libinput close_restricted callback.
fn libinputCloseRestricted(fd: c_int, _: ?*anyopaque) callconv(.c) void {
    _ = c.close(fd);
}

const libinput_impl: c.struct_libinput_interface = .{
    .open_restricted = libinputOpenRestricted,
    .close_restricted = libinputCloseRestricted,
};

/// Errors that can occur during input initialisation.
pub const InputError = error{
    UdevCreateFailed,
    LibinputCreateFailed,
    SeatAssignFailed,
};

/// Create a libinput context from udev.
pub fn createUdevContext(devmgr_fd: *c_int) InputError!*c.struct_libinput {
    const udev = c.udev_new() orelse {
        std.log.err("udev_create: {s}", .{errno.strerror()});
        return error.UdevCreateFailed;
    };
    errdefer _ = c.udev_unref(udev);

    const libinput = c.libinput_udev_create_context(&libinput_impl, devmgr_fd, udev) orelse {
        std.log.err("libinput_udev_create_context: {s}", .{errno.strerror()});
        return error.LibinputCreateFailed;
    };
    _ = c.udev_unref(udev);
    return libinput;
}

/// Assign a seat to the libinput context.
pub fn assignSeat(libinput: *c.struct_libinput) InputError!void {
    if (c.libinput_udev_assign_seat(libinput, "seat0") != 0) {
        std.log.err("Failed to assign libinput seat", .{});
        return error.SeatAssignFailed;
    }
}

/// Get the libinput file descriptor for event polling.
pub fn getFd(libinput: *c.struct_libinput) c_int {
    return c.libinput_get_fd(libinput);
}

/// Dispatch pending libinput events.  Returns 0 on success.
pub fn dispatch(libinput: *c.struct_libinput) c_int {
    return c.libinput_dispatch(libinput);
}

/// Get the next event from libinput's internal queue.
/// Returns null when the queue is empty.
pub fn getEvent(libinput: *c.struct_libinput) ?*c.struct_libinput_event {
    return c.libinput_get_event(libinput);
}

/// Destroy an event returned by getEvent.
pub fn destroyEvent(event: *c.struct_libinput_event) void {
    c.libinput_event_destroy(event);
}

/// Release the libinput context.
pub fn finish(libinput: *c.struct_libinput) void {
    _ = c.libinput_unref(libinput);
}
