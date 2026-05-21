const std = @import("std");
const linux = std.os.linux;

/// PATH_MAX — POSIX standard value for device path buffers.
const path_max = 4096;

/// Message type for the privileged child process protocol.
const MsgType = enum(u32) {
    open,
    end,
};

/// Message exchanged with the privileged device manager child.
const Msg = extern struct {
    msg_type: MsgType,
    path: [path_max]u8,
};

// ---------------------------------------------------------------------------
// Ancillary message helpers (CMSG)
// ---------------------------------------------------------------------------

fn cmsgAlign(comptime len: usize) usize {
    const alignment = @sizeOf(usize);
    return ((len + alignment - 1) / alignment) * alignment;
}

fn cmsgSpace(comptime len: usize) usize {
    return cmsgAlign(len) + cmsgAlign(@sizeOf(linux.cmsghdr));
}

fn cmsgLen(comptime len: usize) usize {
    return cmsgAlign(@sizeOf(linux.cmsghdr)) + len;
}

const cmsg_control_len = cmsgSpace(@sizeOf(i32));

/// Get a pointer to the data portion of a cmsghdr (where the file descriptor lives).
fn cmsgData(cmsg: *align(1) linux.cmsghdr) *i32 {
    const bytes: [*]u8 = @ptrCast(cmsg);
    return @ptrCast(@alignCast(bytes + cmsgAlign(@sizeOf(linux.cmsghdr))));
}

// ---------------------------------------------------------------------------
// Socket message helpers
// ---------------------------------------------------------------------------

/// Receive a message over a Unix socket, optionally receiving a file descriptor.
fn recvMsg(sock: i32, fd_out: ?*i32, buf: ?*anyopaque, buf_len: usize) isize {
    var control: [cmsg_control_len]u8 align(@alignOf(linux.cmsghdr)) = @splat(0);

    var message: linux.msghdr = std.mem.zeroes(linux.msghdr);

    if (buf != null) {
        var iovec = std.posix.iovec{
            .base = @as([*]u8, @ptrCast(buf.?)),
            .len = buf_len,
        };
        message.iov = @as([*]std.posix.iovec, @ptrCast(&iovec));
        message.iovlen = 1;
    }
    if (fd_out != null) {
        message.control = &control;
        message.controllen = control.len;
    }

    var ret: isize = undefined;
    while (true) {
        const rc = linux.recvmsg(sock, &message, @as(u32, linux.MSG.CMSG_CLOEXEC));
        const err = linux.errno(rc);
        if (err == .SUCCESS) {
            ret = @as(isize, @intCast(rc));
            break;
        }
        if (err != .INTR) {
            ret = -1;
            break;
        }
    }

    if (fd_out) |out| {
        out.* = if (message.controllen > 0)
            cmsgData(@as(*align(1) linux.cmsghdr, @ptrCast(&control))).*
        else
            -1;
    }

    return ret;
}

/// Send a message over a Unix socket, optionally sending a file descriptor.
fn sendMsg(sock: i32, fd: i32, buf: ?*anyopaque, buf_len: usize) void {
    var control: [cmsg_control_len]u8 align(@alignOf(linux.cmsghdr)) = @splat(0);

    var message: linux.msghdr = std.mem.zeroes(linux.msghdr);

    if (buf != null) {
        var iovec = std.posix.iovec{
            .base = @as([*]u8, @ptrCast(buf.?)),
            .len = buf_len,
        };
        message.iov = @as([*]std.posix.iovec, @ptrCast(&iovec));
        message.iovlen = 1;
    }
    if (fd >= 0) {
        message.control = &control;
        message.controllen = control.len;

        const cmsg = @as(*align(1) linux.cmsghdr, @ptrCast(&control));
        cmsg.* = .{
            .len = cmsgLen(@sizeOf(i32)),
            .level = @as(i32, @intCast(linux.SOL.SOCKET)),
            .type = @as(i32, @intCast(linux.SCM.RIGHTS)),
        };
        cmsgData(cmsg).* = fd;
    }

    // Build the const version of msghdr for sendmsg.
    var msg_const = linux.msghdr_const{
        .name = message.name,
        .namelen = message.namelen,
        .iov = @as([*]const std.posix.iovec_const, @ptrCast(message.iov)),
        .iovlen = message.iovlen,
        .control = message.control,
        .controllen = message.controllen,
        .flags = message.flags,
    };

    while (true) {
        const rc = linux.sendmsg(sock, &msg_const, 0);
        const err = linux.errno(rc);
        if (err == .SUCCESS) break;
        if (err != .INTR) break;
    }
}

// ---------------------------------------------------------------------------
// Privileged child process
// ---------------------------------------------------------------------------

/// The privileged child process event loop: waits for open/end messages
/// from the parent and opens device nodes on its behalf.
fn run(sock: i32, devpath: []const u8) noreturn {
    var msg: Msg = undefined;
    var fdin: i32 = -1;
    var running = true;

    while (running and recvMsg(sock, &fdin, &msg, @sizeOf(Msg)) > 0) {
        switch (msg.msg_type) {
            .open => {
                const path_slice = std.mem.sliceTo(&msg.path, 0);

                // Security: only allow paths under the compiled devpath prefix.
                if (!std.mem.startsWith(u8, path_slice, devpath)) {
                    // Path prefix mismatch — abort.
                    std.process.exit(1);
                }

                const flags: linux.O = .{
                    .ACCMODE = @enumFromInt(0), // O_RDONLY
                    .CLOEXEC = true,
                    .NONBLOCK = true,
                    .NOCTTY = true,
                };
                const fd = linux.open(@ptrCast(&msg.path), flags, 0);
                const err = linux.errno(fd);
                var ret_msg: i32 = @intFromEnum(err);
                const fd_to_send: i32 = if (err != .SUCCESS) -1 else @as(i32, @intCast(fd));
                sendMsg(sock, fd_to_send, &ret_msg, @sizeOf(i32));
                if (err == .SUCCESS) _ = linux.close(@as(linux.fd_t, @intCast(fd)));
            },
            .end => {
                running = false;
                sendMsg(sock, -1, null, 0);
            },
        }
    }

    std.process.exit(0);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Start the privileged device manager child process.
/// Returns 0 on success, 1 on privilege errors, -1 on system call failures.
pub fn start(fd: *i32, pid: *linux.pid_t, devpath: []const u8) i32 {
    if (linux.geteuid() != 0) {
        std.log.err("showkeys needs to be setuid to read input events", .{});
        return 1;
    }

    var sock: [2]i32 = undefined;
    {
        const rc = linux.socketpair(
            @as(u32, linux.AF.UNIX),
            @as(u32, linux.SOCK.SEQPACKET),
            0,
            &sock,
        );
        if (linux.errno(rc) != .SUCCESS) {
            std.log.err("devmgr: socketpair: {s}", .{strerrorFromErrno(linux.errno(rc))});
            return -1;
        }
    }

    const child = linux.fork();
    const fork_err = linux.errno(child);
    if (fork_err == .SUCCESS and child == 0) {
        // Child process
        _ = linux.close(@as(linux.fd_t, @intCast(sock[0])));
        run(sock[1], devpath);
    } else if (fork_err != .SUCCESS) {
        std.log.err("devmgr: fork: {s}", .{strerrorFromErrno(fork_err)});
        _ = linux.close(@as(linux.fd_t, @intCast(sock[0])));
        _ = linux.close(@as(linux.fd_t, @intCast(sock[1])));
        return 1;
    }

    // Parent process
    _ = linux.close(@as(linux.fd_t, @intCast(sock[1])));
    fd.* = sock[0];
    pid.* = @as(linux.pid_t, @intCast(child));

    // Drop privileges in the parent process.
    {
        const rc = linux.setgid(linux.getgid());
        if (linux.errno(rc) != .SUCCESS) {
            std.log.err("devmgr: setgid: {s}", .{strerrorFromErrno(linux.errno(rc))});
            return 1;
        }
    }
    {
        const rc = linux.setuid(linux.getuid());
        if (linux.errno(rc) != .SUCCESS) {
            std.log.err("devmgr: setuid: {s}", .{strerrorFromErrno(linux.errno(rc))});
            return 1;
        }
    }
    {
        const rc = linux.setuid(0);
        if (linux.errno(rc) == .SUCCESS) {
            std.log.err("devmgr: failed to drop root", .{});
            return 1;
        }
    }

    return 0;
}

/// Open a device node through the privileged child process.
/// Returns a file descriptor on success, or a negative errno on failure.
pub fn open(sockfd: i32, path: [*:0]const u8) i32 {
    var msg: Msg = .{
        .msg_type = .open,
        .path = @splat(0),
    };

    // Copy path into the fixed-size buffer with null terminator.
    const path_len = std.mem.len(path);
    const copy_len = @min(path_len, msg.path.len - 1);
    @memcpy(msg.path[0..copy_len], path[0..copy_len]);
    msg.path[copy_len] = 0;

    sendMsg(sockfd, -1, &msg, @sizeOf(Msg));

    var fd: i32 = -1;
    var err: i32 = 0;
    var retry: i32 = 0;
    while (true) {
        const ret = recvMsg(sockfd, &fd, &err, @sizeOf(i32));
        if (!(ret == 0 and retry < 3)) break;
        retry += 1;
    }

    return if (err != 0) -err else fd;
}

/// Shut down the device manager child process and wait for it to exit.
pub fn finish(sock: i32, pid: linux.pid_t) void {
    var msg: Msg = .{
        .msg_type = .end,
        .path = @splat(0),
    };

    sendMsg(sock, -1, &msg, @sizeOf(Msg));
    _ = recvMsg(sock, null, null, 0);
    var status: u32 = 0;
    _ = linux.waitpid(pid, &status, 0);
    _ = linux.close(@as(linux.fd_t, @intCast(sock)));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Return a string description for an errno E value (best-effort).
fn strerrorFromErrno(err: linux.E) []const u8 {
    return switch (err) {
        .SUCCESS => "success",
        .ACCES => "permission denied",
        .NOENT => "no such file or directory",
        .NOMEM => "out of memory",
        .INTR => "interrupted",
        .AGAIN => "resource temporarily unavailable",
        .BADF => "bad file descriptor",
        .FAULT => "bad address",
        .INVAL => "invalid argument",
        .SRCH => "no such process",
        else => "unknown error",
    };
}
