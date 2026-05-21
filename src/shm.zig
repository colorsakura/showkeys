const std = @import("std");
const c = @import("c");

/// Alias for the C pool_buffer struct, maintaining ABI compatibility.
/// Used by exported functions for seamless interop with render.zig via `c.*` calls.
const PoolBuffer = c.struct_pool_buffer;

/// Generates a random 6-character suffix for SHM file names using
/// high-resolution clock nanoseconds as the entropy source.
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
    /// Failed to create a unique SHM file after retries.
    ShmOpenFailed,
    /// Failed to set the file size via ftruncate.
    ShmFtruncateFailed,
};

/// Creates a unique SHM file with a random name under /wl_shm-XXXXXX.
/// Retries up to 100 times if the name collides (EEXIST).
/// Returns the file descriptor on success, or an error.
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
        if (retries == 0 or c.__errno_location().* != c.EEXIST) {
            return error.ShmOpenFailed;
        }
    }
}

/// Creates a SHM file and truncates it to the given size.
/// Returns the file descriptor on success, or an error.
fn allocateShmFile(size: usize) ShmError!std.posix.fd_t {
    const fd = try createShmFile();
    errdefer _ = c.close(fd);

    var ret: c_int = undefined;
    while (true) {
        ret = c.ftruncate(fd, @intCast(size));
        if (ret >= 0) break;
        if (c.__errno_location().* != c.EINTR) return error.ShmFtruncateFailed;
    }

    return fd;
}

/// Wayland buffer release callback — marks the buffer as available for reuse.
fn bufferRelease(data: ?*anyopaque, wl_buffer: ?*c.struct_wl_buffer) callconv(.c) void {
    _ = wl_buffer;
    const buffer: *PoolBuffer = @ptrCast(@alignCast(data.?));
    buffer.busy = false;
}

const buffer_listener: c.struct_wl_buffer_listener = .{
    .release = bufferRelease,
};

/// Creates a new SHM-backed buffer, setting up Cairo/Pango rendering
/// surfaces. Returns the buffer pointer, or null on failure.
fn createBuffer(
    shm: ?*c.struct_wl_shm,
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

    const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
    buf.buffer = c.wl_shm_pool_create_buffer(pool, 0, width, height, @intCast(stride), format);
    c.wl_shm_pool_destroy(pool);
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

    _ = c.wl_buffer_add_listener(buf.buffer, &buffer_listener, buf);
    return buf;
}

/// Destroys a pool buffer, releasing all associated resources:
/// Wayland buffer, Cairo surface/context, Pango context, and the mmap region.
/// The buffer struct is zeroed after cleanup.
export fn destroy_buffer(buffer: *PoolBuffer) void {
    if (buffer.buffer) |b| c.wl_buffer_destroy(b);
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
/// If the existing buffer has different dimensions, it is destroyed and
/// recreated. Returns null if both buffers are busy or creation fails.
export fn get_next_buffer(
    shm: ?*c.struct_wl_shm,
    pool: [*c]PoolBuffer,
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
        destroy_buffer(selected);
    }

    if (selected.buffer == null) {
        if (createBuffer(shm, selected, @intCast(width), @intCast(height), c.WL_SHM_FORMAT_ARGB8888) == null) {
            return null;
        }
    }
    selected.busy = true;
    return selected;
}
