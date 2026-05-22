const std = @import("std");
const c = @import("c");
const wl_mod = @import("wayland");
const wl = wl_mod.client.wl;
const types = @import("types.zig");
const errno = @import("errno.zig");

const PoolBuffer = types.PoolBuffer;

/// Generates a random 6-character suffix for SHM file names using
/// monotonic clock nanoseconds as the entropy source.
fn randname(buf: []u8) void {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);
    var r: u64 = @bitCast(ts.tv_nsec);
    for (0..6) |i| {
        buf[i] = @intCast('A' + (r & 15) + (r & 16) * 2);
        r >>= 5;
    }
}

/// Errors that can occur during SHM file creation.
const ShmError = error{
    ShmOpenFailed,
    ShmFtruncateFailed,
};

/// Creates a unique SHM file with a random name under /wl_shm-XXXXXX.
fn createShmFile() ShmError!std.posix.fd_t {
    var retries: u32 = 100;
    while (true) {
        var name: [14]u8 = "/wl_shm-XXXXXX".*;
        randname(name[8..14]);

        retries -|= 1;
        const fd = c.shm_open(&name, c.O_RDWR | c.O_CREAT | c.O_EXCL, @as(c.mode_t, 0o600));
        if (fd >= 0) {
            _ = c.shm_unlink(&name);
            return @intCast(fd);
        }
        if (retries == 0 or errno.get() != c.EEXIST) {
            return error.ShmOpenFailed;
        }
    }
}

/// Creates a SHM file and truncates it to the given size.
fn allocateShmFile(size: usize) ShmError!std.posix.fd_t {
    const fd = try createShmFile();
    errdefer _ = c.close(fd);

    var ret: c_int = undefined;
    while (true) {
        ret = c.ftruncate(fd, @intCast(size));
        if (ret >= 0) break;
        if (errno.get() != c.EINTR) return error.ShmFtruncateFailed;
    }

    return fd;
}

/// Wayland buffer release callback — marks the buffer as available for reuse.
fn bufferListener(buffer: *wl.Buffer, event: wl.Buffer.Event, data: *PoolBuffer) void {
    switch (event) {
        .release => {
            data.busy = false;
        },
    }
    _ = buffer;
}

/// Creates a new SHM-backed buffer, setting up Cairo/Pango rendering
/// surfaces. Returns the buffer pointer, or null on failure.
fn createBuffer(
    shm: *wl.Shm,
    buf: *PoolBuffer,
    width: i32,
    height: i32,
    format: u32,
) ?*PoolBuffer {
    const stride: u32 = @intCast(width * 4);
    const size: usize = @as(usize, @intCast(stride)) * @as(usize, @intCast(height));

    const fd = allocateShmFile(size) catch return null;
    errdefer _ = c.close(fd);

    const mapping = std.posix.mmap(
        null,
        size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED },
        fd,
        0,
    ) catch return null;

    const pool = shm.createPool(fd, @intCast(size)) catch {
        _ = c.close(fd);
        return null;
    };
    buf.buffer = pool.createBuffer(0, width, height, @intCast(stride), @as(wl.Shm.Format, @enumFromInt(format))) catch {
        pool.destroy();
        _ = c.close(fd);
        return null;
    };
    pool.destroy();
    _ = c.close(fd);

    buf.size = size;
    buf.width = @intCast(width);
    buf.height = @intCast(height);
    buf.data = @ptrCast(mapping.ptr);
    buf.surface = c.cairo_image_surface_create_for_data(
        @ptrCast(mapping.ptr),
        c.CAIRO_FORMAT_ARGB32,
        width,
        height,
        @intCast(stride),
    );
    buf.cairo = c.cairo_create(buf.surface);
    buf.pango = c.pango_cairo_create_context(buf.cairo);

    buf.buffer.?.setListener(*PoolBuffer, bufferListener, buf);
    return buf;
}

/// Destroys a pool buffer, releasing all associated resources.
pub fn destroyBuffer(buffer: *PoolBuffer) void {
    if (buffer.buffer) |b| b.destroy();
    if (buffer.cairo) |cr| c.cairo_destroy(cr);
    if (buffer.surface) |s| c.cairo_surface_destroy(s);
    if (buffer.pango) |ctx| c.g_object_unref(ctx);
    if (buffer.data) |data_ptr| {
        const page_size = std.heap.page_size_min;
        const mmap_slice: []align(page_size) const u8 = @alignCast(
            @as([*]const u8, @ptrCast(data_ptr))[0..buffer.size],
        );
        std.posix.munmap(mmap_slice);
    }
    buffer.* = .{};
}

/// Returns the next available (non-busy) buffer from the pool of two.
pub fn getNextBuffer(
    shm: *wl.Shm,
    pool: []PoolBuffer,
    width: u32,
    height: u32,
) ?*PoolBuffer {
    var buffer: ?*PoolBuffer = null;

    for (0..2) |i| {
        if (!pool[i].busy) {
            buffer = &pool[i];
            break;
        }
    }

    const selected = buffer orelse return null;

    if (selected.width != width or selected.height != height) {
        destroyBuffer(selected);
    }

    if (selected.buffer == null) {
        if (createBuffer(shm, selected, @intCast(width), @intCast(height), @intFromEnum(wl.Shm.Format.argb8888)) == null) {
            return null;
        }
    }
    selected.busy = true;
    return selected;
}
