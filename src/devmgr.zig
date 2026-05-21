const std = @import("std");

const c = @import("c");

const MsgType = enum(c_int) {
    open,
    end,
};

const Msg = extern struct {
    msg_type: MsgType,
    path: [c.PATH_MAX]u8,
};

fn errno() c_int {
    return std.c._errno().*;
}

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
        if (!(ret < 0 and errno() == c.EINTR)) {
            break;
        }
    }

    if (fd_out) |out| {
        if (c.CMSG_FIRSTHDR(&message)) |cmsg| {
            out.* = cmsgData(cmsg).*;
        } else {
            out.* = -1;
        }
    }

    return ret;
}

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
        if (!(ret < 0 and errno() == c.EINTR)) {
            break;
        }
    }
}

fn run(sock: c_int, devpath: [*c]const u8) noreturn {
    var msg: Msg = undefined;
    var fdin: c_int = -1;
    var running = true;

    while (running and recvMsg(sock, &fdin, &msg, @sizeOf(Msg)) > 0) {
        switch (msg.msg_type) {
            .open => {
                std.c._errno().* = 0;
                const path: [*c]u8 = @ptrCast(&msg.path);
                if (c.strstr(path, devpath) != path) {
                    c.exit(1);
                }

                const fd = c.open(path, c.O_RDONLY | c.O_CLOEXEC | c.O_NOCTTY | c.O_NONBLOCK);
                const ret = errno();
                var ret_msg = ret;
                sendMsg(sock, if (ret != 0) -1 else fd, &ret_msg, @sizeOf(c_int));
                if (fd >= 0) {
                    _ = c.close(fd);
                }
            },
            .end => {
                running = false;
                sendMsg(sock, -1, null, 0);
            },
        }
    }

    c.exit(0);
}

export fn devmgr_start(fd: *c_int, pid: *c.pid_t, devpath: [*c]const u8) c_int {
    if (c.geteuid() != 0) {
        _ = c.fprintf(c.stderr, "showkeys needs to be setuid to read input events\n");
        return 1;
    }

    var sock: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_SEQPACKET, 0, &sock) < 0) {
        _ = c.fprintf(c.stderr, "devmgr: socketpair: %s", c.strerror(errno()));
        return -1;
    }

    const child = c.fork();
    if (child < 0) {
        _ = c.fprintf(c.stderr, "devmgr: fork: %s", c.strerror(errno()));
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

    if (c.setgid(c.getgid()) != 0) {
        _ = c.fprintf(c.stderr, "devmgr: setgid: %s\n", c.strerror(errno()));
        return 1;
    }
    if (c.setuid(c.getuid()) != 0) {
        _ = c.fprintf(c.stderr, "devmgr: setuid: %s\n", c.strerror(errno()));
        return 1;
    }
    if (c.setuid(0) != -1) {
        _ = c.fprintf(c.stderr, "devmgr: failed to drop root\n");
        return 1;
    }

    return 0;
}

export fn devmgr_open(sockfd: c_int, path: [*c]const u8) c_int {
    var msg: Msg = std.mem.zeroes(Msg);
    msg.msg_type = .open;
    _ = c.snprintf(@ptrCast(&msg.path), msg.path.len, "%s", path);

    sendMsg(sockfd, -1, &msg, @sizeOf(Msg));

    var fd: c_int = -1;
    var err: c_int = 0;
    var ret: isize = undefined;
    var retry: c_int = 0;
    while (true) {
        ret = recvMsg(sockfd, &fd, &err, @sizeOf(c_int));
        if (!(ret == 0 and retry < 3)) {
            break;
        }
        retry += 1;
    }

    return if (err != 0) -err else fd;
}

export fn devmgr_finish(sock: c_int, pid: c.pid_t) void {
    var msg: Msg = std.mem.zeroes(Msg);
    msg.msg_type = .end;

    sendMsg(sock, -1, &msg, @sizeOf(Msg));
    _ = recvMsg(sock, null, null, 0);
    _ = c.waitpid(pid, null, 0);
    _ = c.close(sock);
}
