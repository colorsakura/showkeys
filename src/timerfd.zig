const std = @import("std");
const c = @import("c");
const linux = std.os.linux;

// ---------------------------------------------------------------------------
// timerfd helpers — Linux timerfd_create / timerfd_settime wrappers.
//
// Uses direct Linux syscalls to avoid dependency on struct layout details
// that vary between Zig versions.
// ---------------------------------------------------------------------------

/// Create a new timerfd (CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK).
/// Returns the file descriptor, or a negative errno on failure.
pub fn create() c_int {
    const SYS = linux.SYS.timerfd_create;

    const rc = linux.syscall3(SYS, @as(usize, 1), @as(usize, 0o2000000 | 0o4000), @as(usize, 0));
    const err = linux.errno(rc);
    if (err != .SUCCESS) {
        return -@as(c_int, @intCast(@intFromEnum(err)));
    }
    return @as(c_int, @intCast(rc));
}

/// Internal representation of `struct itimerspec` passed to the kernel.
/// Uses the kernel's native layout (two `struct timespec`).
const KernelTimeSpec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

const KernelItimerSpec = extern struct {
    it_interval: KernelTimeSpec,
    it_value: KernelTimeSpec,
};

/// Arm (or disarm) a timerfd with the given interval in nanoseconds.
/// The initial expiration equals the interval (fires after interval_ns).
/// Passing 0 disarms the timer.
pub fn setInterval(fd: c_int, interval_ns: u64) void {
    const SYS = linux.SYS.timerfd_settime;

    var spec = KernelItimerSpec{
        .it_interval = .{ .tv_sec = @as(i64, @intCast(interval_ns / 1_000_000_000)), .tv_nsec = @as(i64, @intCast(interval_ns % 1_000_000_000)) },
        .it_value = .{ .tv_sec = @as(i64, @intCast(interval_ns / 1_000_000_000)), .tv_nsec = @as(i64, @intCast(interval_ns % 1_000_000_000)) },
    };

    _ = linux.syscall4(SYS, @as(usize, @intCast(fd)), @as(usize, 0), @as(usize, @intCast(@intFromPtr(&spec))), @as(usize, 0));
}

/// Read the number of expirations from a timerfd (non-blocking).
/// Returns the number of expirations, or 0 if none, or a negative errno.
pub fn readExpirations(fd: c_int) i64 {
    var buf: u64 = 0;
    const rc = linux.read(@as(linux.fd_t, @intCast(fd)), @as([*]u8, @ptrCast(&buf)), @sizeOf(u64));
    const err = linux.errno(rc);
    if (err == .SUCCESS) {
        return @as(i64, @intCast(buf));
    }
    if (err == .AGAIN) {
        return 0;
    }
    return -@as(i64, @intFromEnum(err));
}

/// Disarm a timerfd.
pub fn disarm(fd: c_int) void {
    setInterval(fd, 0);
}

/// Close a timerfd.
pub fn close(fd: c_int) void {
    _ = linux.close(@as(linux.fd_t, @intCast(fd)));
}
