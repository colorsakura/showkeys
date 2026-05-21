const std = @import("std");
const c = @import("c");
const errno = @import("errno.zig");

/// Message type for the privileged child process protocol.
const MsgType = enum(c_int) {
    open,
    end,
};

/// Message exchanged with the privileged device manager child.
const Msg = extern struct {
    msg_type: MsgType,
    path: [c.PATH_MAX]u8,
};

/// Maximum PATH_MAX characters for device paths.
const path_max = c.PATH_MAX;

// ---------------------------------------------------------------------------
// Ancillary message helpers (CMSG)
// ---------------------------------------------------------------------------

fn cmsgAlign(comptime len: usize) usize {
    const alignment = @sizeOf(usize);
    return ((len + alignment - 1) / alignment) * alignment;
}

fn cmsgSpace(comptime len: usize) usize {
    return cmsgAlign(len) + cmsgAlign(@sizeOf(c.struct_cmsghdr));
}

fn cmsgLen(comptime len: usize) usize {
    return cmsgAlign(@sizeOf(c.struct_cmsghdr)) + len;
}

const cmsg_control_len = cmsgSpace(@sizeOf(c_int));

fn cmsgData(cmsg: [*c]c.struct_cmsghdr) *c_int {
    const bytes: [*]u8 = @ptrCast(cmsg);
    return @ptrCast(@alignCast(bytes + cmsgAlign(@sizeOf(c.struct_cmsghdr))));
}

// ---------------------------------------------------------------------------
// Socket message helpers
// ---------------------------------------------------------------------------

/// Receive a message over a Unix socket, optionally receiving a file descriptor.
fn recvMsg(sock: c_int, fd_out: ?*c_int, buf: ?*anyopaque, buf_len: usize) isize {
    var control: [cmsg_control_len]u8 align(@alignOf(c.struct_cmsghdr)) = .{0} ** cmsg_control_len;
    var iovec: c.struct_iovec = .{
        .iov_base = buf,
        .iov_len = buf_len,
    };
    var message: c.struct_msghdr = .{};

    if (buf != null) {
        message.msg_iov = &iovec;
        message.msg_iovlen = 1;
    }
    if (fd_out != null) {
        message.msg_control = &control;
        message.msg_controllen = control.len;
    }

    var ret: isize = undefined;
    while (true) {
        ret = c.recvmsg(sock, &message, c.MSG_CMSG_CLOEXEC);
        if (!(ret < 0 and errno.get() == c.EINTR)) break;
    }

    if (fd_out) |out| {
        out.* = if (c.CMSG_FIRSTHDR(&message)) |cmsg|
            cmsgData(cmsg).*
        else
            -1;
    }

    return ret;
}

/// Send a message over a Unix socket, optionally sending a file descriptor.
fn sendMsg(sock: c_int, fd: c_int, buf: ?*anyopaque, buf_len: usize) void {
    var control: [cmsg_control_len]u8 align(@alignOf(c.struct_cmsghdr)) = .{0} ** cmsg_control_len;
    var iovec: c.struct_iovec = .{
        .iov_base = buf,
        .iov_len = buf_len,
    };
    var message: c.struct_msghdr = .{};

    if (buf != null) {
        message.msg_iov = &iovec;
        message.msg_iovlen = 1;
    }
    if (fd >= 0) {
        message.msg_control = &control;
        message.msg_controllen = control.len;

        const cmsg = c.CMSG_FIRSTHDR(&message);
        cmsg[0] = .{
            .cmsg_len = cmsgLen(@sizeOf(c_int)),
            .cmsg_level = c.SOL_SOCKET,
            .cmsg_type = c.SCM_RIGHTS,
        };
        cmsgData(cmsg).* = fd;
    }

    var ret: isize = undefined;
    while (true) {
        ret = c.sendmsg(sock, &message, 0);
        if (!(ret < 0 and errno.get() == c.EINTR)) break;
    }
}

// ---------------------------------------------------------------------------
// Privileged child process
// ---------------------------------------------------------------------------

/// The privileged child process event loop: waits for open/end messages
/// from the parent and opens device nodes on its behalf.
fn run(sock: c_int, devpath: [*c]const u8) noreturn {
    var msg: Msg = undefined;
    var fdin: c_int = -1;
    var running = true;

    while (running and recvMsg(sock, &fdin, &msg, @sizeOf(Msg)) > 0) {
        switch (msg.msg_type) {
            .open => {
                errno.set(0);
                const path: [*c]u8 = @ptrCast(&msg.path);

                // Security: only allow paths under the compiled devpath prefix.
                if (c.strstr(path, devpath) != path) {
                    c.exit(1);
                }

                const fd = c.open(path, c.O_RDONLY | c.O_CLOEXEC | c.O_NOCTTY | c.O_NONBLOCK);
                const ret = errno.get();
                var ret_msg = ret;
                sendMsg(sock, if (ret != 0) -1 else fd, &ret_msg, @sizeOf(c_int));
                if (fd >= 0) _ = c.close(fd);
            },
            .end => {
                running = false;
                sendMsg(sock, -1, null, 0);
            },
        }
    }

    c.exit(0);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Start the privileged device manager child process.
/// Returns 0 on success, 1 on privilege errors, -1 on system call failures.
pub fn start(fd: *c_int, pid: *c.pid_t, devpath: [*c]const u8) c_int {
    if (c.geteuid() != 0) {
        std.log.err("showkeys needs to be setuid to read input events", .{});
        return 1;
    }

    var sock: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_SEQPACKET, 0, &sock) < 0) {
        std.log.err("devmgr: socketpair: {s}", .{errno.strerror()});
        return -1;
    }

    const child = c.fork();
    if (child < 0) {
        std.log.err("devmgr: fork: {s}", .{errno.strerror()});
        _ = c.close(sock[0]);
        _ = c.close(sock[1]);
        return 1;
    } else if (child == 0) {
        _ = c.close(sock[0]);
        run(sock[1], devpath);
    }

    _ = c.close(sock[1]);
    fd.* = sock[0];
    pid.* = child;

    // Drop privileges in the parent process.
    if (c.setgid(c.getgid()) != 0) {
        std.log.err("devmgr: setgid: {s}", .{errno.strerror()});
        return 1;
    }
    if (c.setuid(c.getuid()) != 0) {
        std.log.err("devmgr: setuid: {s}", .{errno.strerror()});
        return 1;
    }
    if (c.setuid(0) != -1) {
        std.log.err("devmgr: failed to drop root", .{});
        return 1;
    }

    return 0;
}

/// Open a device node through the privileged child process.
/// Returns a file descriptor on success, or a negative errno on failure.
pub fn open(sockfd: c_int, path: [*c]const u8) c_int {
    var msg: Msg = .{
        .msg_type = .open,
        .path = @as([path_max]u8, @splat(0)),
    };
    _ = c.snprintf(@ptrCast(&msg.path), msg.path.len, "%s", path);

    sendMsg(sockfd, -1, &msg, @sizeOf(Msg));

    var fd: c_int = -1;
    var err: c_int = 0;
    var ret: isize = undefined;
    var retry: c_int = 0;
    while (true) {
        ret = recvMsg(sockfd, &fd, &err, @sizeOf(c_int));
        if (!(ret == 0 and retry < 3)) break;
        retry += 1;
    }

    return if (err != 0) -err else fd;
}

/// Shut down the device manager child process and wait for it to exit.
pub fn finish(sock: c_int, pid: c.pid_t) void {
    var msg: Msg = .{
        .msg_type = .end,
        .path = @as([path_max]u8, @splat(0)),
    };

    sendMsg(sock, -1, &msg, @sizeOf(Msg));
    _ = recvMsg(sock, null, null, 0);
    _ = c.waitpid(pid, null, 0);
    _ = c.close(sock);
}
