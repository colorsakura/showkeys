const std = @import("std");

const c = @import("c");

comptime {
    _ = @import("app.zig");
    _ = @import("color.zig");
    _ = @import("config.zig");
    _ = @import("icons.zig");
    _ = @import("keycap.zig");
    _ = @import("keys.zig");
    _ = @import("render.zig");
    _ = @import("shm.zig");
    _ = @import("theme.zig");
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*c]u8, args.len + 1);
    for (args, 0..) |arg, i| {
        argv[i] = @constCast(arg.ptr);
    }
    argv[args.len] = null;

    var app: ?*c.struct_wsk_app = null;
    if (!c.wsk_app_init_privileged(&app)) {
        std.process.exit(1);
    }

    if (!c.wsk_app_init(app, @intCast(args.len), argv.ptr)) {
        c.wsk_app_finish(app);
        std.process.exit(1);
    }

    const ret = c.wsk_app_run(app);
    c.wsk_app_finish(app);

    std.process.exit(@intCast(ret));
}
