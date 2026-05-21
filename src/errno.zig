const c = @import("c");

/// Return the current errno value set by the last failed C library call.
pub fn get() c_int {
    return c.__errno_location().*;
}

/// Set the errno value (used before a call that might fail).
pub fn set(value: c_int) void {
    c.__errno_location().* = value;
}

/// Check if `errno` equals `EAGAIN` (common retry condition).
pub fn isAgain() bool {
    return get() == c.EAGAIN;
}

/// Format the current errno as a string.
pub fn strerror() [*c]const u8 {
    return c.strerror(get());
}
