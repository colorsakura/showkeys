const std = @import("std");

const c_sources = [_][]const u8{
    "src/devmgr.c",
    "src/main.c",
    "src/pango.c",
    "src/shm.c",
};

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

const protocols = [_]Protocol{
    .{ .package = "wayland-protocols", .relative_path = "unstable/xdg-output/xdg-output-unstable-v1.xml" },
    .{ .package = "wayland-protocols", .relative_path = "stable/xdg-shell/xdg-shell.xml" },
    .{ .path = "protocols/wlr-layer-shell-unstable-v1.xml" },
};

const Protocol = struct {
    package: ?[]const u8 = null,
    relative_path: []const u8 = "",
    path: ?[]const u8 = null,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const devpath = b.option([]const u8, "devpath", "Input device path prefix compiled into the privileged device manager") orelse "/dev/input/";

    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    module.addCSourceFiles(.{
        .files = &c_sources,
        .flags = cFlags(b, devpath),
    });
    module.addIncludePath(b.path("src"));

    for (pkg_config_deps) |dep| {
        module.linkSystemLibrary(dep, .{ .use_pkg_config = .force });
    }
    module.linkSystemLibrary("rt", .{});

    const wayland_scanner = b.findProgram(&.{"wayland-scanner"}, &.{}) catch @panic("wayland-scanner not found");
    const protocol_output_dir = generateProtocols(b, module, wayland_scanner);
    module.addIncludePath(protocol_output_dir);

    const exe = b.addExecutable(.{
        .name = "showkeys",
        .root_module = module,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run showkeys");
    run_step.dependOn(&run_cmd.step);
}

fn cFlags(b: *std.Build, devpath: []const u8) []const []const u8 {
    return b.dupeStrings(&.{
        "-std=c23",
        "-D_POSIX_C_SOURCE=200809L",
        b.fmt("-DINPUTDEVPATH=\"{s}\"", .{devpath}),
        "-Wall",
        "-Wextra",
        "-Wundef",
        "-Wmissing-include-dirs",
        "-Wold-style-definition",
        "-Wpointer-arith",
        "-Winit-self",
        "-Wstrict-prototypes",
        "-Wimplicit-fallthrough",
        "-Wendif-labels",
        "-Wstrict-aliasing=2",
        "-Woverflow",
        "-Werror",
        "-Wno-missing-braces",
        "-Wno-missing-field-initializers",
        "-Wno-unused-parameter",
    });
}

fn generateProtocols(b: *std.Build, module: *std.Build.Module, wayland_scanner: []const u8) std.Build.LazyPath {
    const output = b.addWriteFiles();

    for (protocols) |protocol| {
        const xml = protocolXmlPath(b, protocol);
        const basename = std.fs.path.basename(xml);
        const stem = if (std.mem.endsWith(u8, basename, ".xml")) basename[0 .. basename.len - 4] else basename;

        const header_path = b.fmt("{s}-client-protocol.h", .{stem});
        const source_path = b.fmt("{s}-protocol.c", .{stem});

        const header = runWaylandScanner(b, wayland_scanner, "client-header", xml, header_path);
        const source = runWaylandScanner(b, wayland_scanner, "private-code", xml, source_path);

        _ = output.addCopyFile(header, header_path);
        _ = output.addCopyFile(source, source_path);
        module.addCSourceFile(.{ .file = source, .flags = &.{} });
    }

    return output.getDirectory();
}

fn protocolXmlPath(b: *std.Build, protocol: Protocol) []const u8 {
    if (protocol.path) |path| return path;

    const pkg = protocol.package orelse @panic("protocol needs either .path or .package");
    const pkgdatadir = pkgConfigVariable(b, pkg, "pkgdatadir");
    return b.pathJoin(&.{ pkgdatadir, protocol.relative_path });
}

fn pkgConfigVariable(b: *std.Build, package: []const u8, variable: []const u8) []const u8 {
    const argv = &.{ "pkg-config", b.fmt("--variable={s}", .{variable}), package };
    return std.mem.trim(u8, b.run(argv), " \t\r\n");
}

fn runWaylandScanner(
    b: *std.Build,
    wayland_scanner: []const u8,
    command: []const u8,
    input: []const u8,
    output_name: []const u8,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ wayland_scanner, command });
    run.addFileArg(.{ .cwd_relative = input });
    return run.addOutputFileArg(output_name);
}
