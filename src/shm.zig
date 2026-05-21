const c = @import("c");

const O_RDWR: c_int = 0o2;
const O_CREAT: c_int = 0o100;
const O_EXCL: c_int = 0o200;

fn errnoValue() c_int {
    return c.__errno_location().*;
}

fn randname(buf: [*]u8) void {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);
    var r = ts.tv_nsec;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        buf[i] = @intCast('A' + (r & 15) + (r & 16) * 2);
        r >>= 5;
    }
}

export fn create_shm_file() c_int {
    var retries: c_int = 100;
    while (true) {
        var name = [_:0]u8{ '/', 'w', 'l', '_', 's', 'h', 'm', '-', 'X', 'X', 'X', 'X', 'X', 'X' };
        randname(name[8..14].ptr);

        retries -= 1;
        const fd = c.shm_open(&name, O_RDWR | O_CREAT | O_EXCL, 0o600);
        if (fd >= 0) {
            _ = c.shm_unlink(&name);
            return fd;
        }
        if (!(retries > 0 and errnoValue() == c.EEXIST)) {
            break;
        }
    }
    return -1;
}

export fn allocate_shm_file(size: usize) c_int {
    const fd = create_shm_file();
    if (fd < 0) {
        return -1;
    }

    var ret: c_int = undefined;
    while (true) {
        ret = c.ftruncate(fd, @intCast(size));
        if (!(ret < 0 and errnoValue() == c.EINTR)) {
            break;
        }
    }
    if (ret < 0) {
        _ = c.close(fd);
        return -1;
    }

    return fd;
}

fn bufferRelease(data: ?*anyopaque, wl_buffer: ?*c.struct_wl_buffer) callconv(.c) void {
    _ = wl_buffer;
    const buffer: *c.struct_pool_buffer = @ptrCast(@alignCast(data.?));
    buffer.busy = false;
}

const buffer_listener: c.struct_wl_buffer_listener = .{
    .release = bufferRelease,
};

fn createBuffer(
    shm: ?*c.struct_wl_shm,
    buf: *c.struct_pool_buffer,
    width: i32,
    height: i32,
    format: u32,
) ?*c.struct_pool_buffer {
    const stride: u32 = @intCast(width * 4);
    const size: usize = @as(usize, @intCast(stride)) * @as(usize, @intCast(height));

    const fd = allocate_shm_file(size);
    if (fd == -1) {
        @panic("allocate_shm_file failed");
    }
    const data = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
    const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
    buf.buffer = c.wl_shm_pool_create_buffer(pool, 0, width, height, @intCast(stride), format);
    c.wl_shm_pool_destroy(pool);
    _ = c.close(fd);

    buf.size = size;
    buf.width = @intCast(width);
    buf.height = @intCast(height);
    buf.data = data;
    buf.surface = c.cairo_image_surface_create_for_data(@ptrCast(data), c.CAIRO_FORMAT_ARGB32, width, height, @intCast(stride));
    buf.cairo = c.cairo_create(buf.surface);
    buf.pango = c.pango_cairo_create_context(buf.cairo);

    _ = c.wl_buffer_add_listener(buf.buffer, &buffer_listener, buf);
    return buf;
}

export fn destroy_buffer(buffer: *c.struct_pool_buffer) void {
    if (buffer.buffer != null) {
        c.wl_buffer_destroy(buffer.buffer);
    }
    if (buffer.cairo != null) {
        c.cairo_destroy(buffer.cairo);
    }
    if (buffer.surface != null) {
        c.cairo_surface_destroy(buffer.surface);
    }
    if (buffer.pango != null) {
        c.g_object_unref(buffer.pango);
    }
    if (buffer.data != null) {
        _ = c.munmap(buffer.data, buffer.size);
    }
    _ = c.memset(buffer, 0, @sizeOf(c.struct_pool_buffer));
}

export fn get_next_buffer(
    shm: ?*c.struct_wl_shm,
    pool: [*c]c.struct_pool_buffer,
    width: u32,
    height: u32,
) ?*c.struct_pool_buffer {
    var buffer: ?*c.struct_pool_buffer = null;

    var i: usize = 0;
    while (i < 2) : (i += 1) {
        if (pool[i].busy) {
            continue;
        }
        buffer = &pool[i];
        break;
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
