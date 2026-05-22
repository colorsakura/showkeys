const std = @import("std");
const app_module = @import("app.zig");
const types = @import("types.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var app_ptr: ?*types.App = null;
    app_module.initPrivileged(&app_ptr) catch |err| {
        std.log.err("initPrivileged failed: {}", .{err});
        std.process.exit(1);
    };
    const state = app_ptr orelse std.process.exit(1);

    app_module.init(state, args) catch |err| {
        std.log.err("init failed: {}", .{err});
        app_module.finish(state);
        std.process.exit(1);
    };

    const ret = app_module.run(state);
    app_module.finish(state);

    std.process.exit(@intCast(ret));
}
