const std = @import("std");
const zig_wayland = @import("wayland");

const default_devpath = "/dev/input/";
const posix_c_source = "200809L";

const pkg_config_deps = [_][]const u8{
    "cairo",
    "libinput",
    "librsvg-2.0",
    "pango",
    "pangocairo",
    "libudev",
    "wayland-client",
    "xkbcommon",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const devpath = b.option([]const u8, "devpath", "Input device path prefix compiled into the privileged device manager") orelse default_devpath;

    // --- zig-wayland: generate protocol bindings ---
    const scanner = zig_wayland.Scanner.create(b, .{});
    scanner.addSystemProtocol("unstable/xdg-output/xdg-output-unstable-v1.xml");
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-unstable-v1.xml"));
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 5);
    scanner.generate("wl_output", 3);
    scanner.generate("zxdg_output_manager_v1", 1);
    scanner.generate("zwlr_layer_shell_v1", 1);

    const wayland_module = b.createModule(.{
        .root_source_file = scanner.result,
        .target = target,
        .optimize = optimize,
    });

    // --- executable ---
    const exe = b.addExecutable(.{
        .name = "showkeys",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .use_llvm = true,
        .use_lld = true,
    });
    exe.use_new_linker = false;

    const root_module = exe.root_module;
    root_module.addImport("wayland", wayland_module);
    root_module.addImport("c", translateCBindings(b, target, optimize, devpath));

    configureModule(b, root_module, devpath);

    b.installArtifact(exe);
}

fn configureModule(b: *std.Build, module: *std.Build.Module, devpath: []const u8) void {
    module.addCMacro("_POSIX_C_SOURCE", posix_c_source);
    module.addCMacro("INPUTDEVPATH", cStringLiteral(b, devpath));
    linkSystemLibraries(module);
}

fn linkSystemLibraries(linker: anytype) void {
    for (pkg_config_deps) |dep| {
        linker.linkSystemLibrary(dep, .{ .use_pkg_config = .force });
    }
    linker.linkSystemLibrary("rt", .{});
}

fn cStringLiteral(b: *std.Build, value: []const u8) []const u8 {
    return b.fmt("\"{s}\"", .{value});
}

fn translateCBindings(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    devpath: []const u8,
) *std.Build.Module {
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.defineCMacro("_POSIX_C_SOURCE", posix_c_source);
    translate_c.defineCMacro("INPUTDEVPATH", cStringLiteral(b, devpath));

    for (pkg_config_deps) |dep| {
        translate_c.linkSystemLibrary(dep, .{ .use_pkg_config = .force });
    }
    translate_c.linkSystemLibrary("rt", .{});

    return translate_c.createModule();
}
