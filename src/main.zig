const std = @import("std");
const app = @import("app.zig");
const types = @import("types.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*c]u8, args.len + 1);
    for (args, 0..) |arg, i| {
        argv[i] = @constCast(arg.ptr);
    }
    argv[args.len] = null;

    var app_ptr: ?*types.App = null;
    if (!app.initPrivileged(&app_ptr)) {
        std.process.exit(1);
    }
    const state = app_ptr orelse std.process.exit(1);

    if (!app.init(state, @intCast(args.len), argv.ptr)) {
        app.finish(state);
        std.process.exit(1);
    }

    const ret = app.run(state);
    app.finish(state);

    std.process.exit(@intCast(ret));
}
