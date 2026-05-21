const std = @import("std");

const c_sources = [_][]const u8{
    "devmgr.c",
    "input.c",
    "pango.c",
    "wayland.c",
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

    root_module.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &c_sources,
        .flags = cFlags(),
    });
    root_module.addIncludePath(b.path("include"));
    root_module.addCMacro("_POSIX_C_SOURCE", "200809L");
    root_module.addCMacro("INPUTDEVPATH", b.fmt("\"{s}\"", .{devpath}));

    for (pkg_config_deps) |dep| {
        root_module.linkSystemLibrary(dep, .{ .use_pkg_config = .force });
    }
    root_module.linkSystemLibrary("rt", .{});

    const wayland_scanner = b.findProgram(&.{"wayland-scanner"}, &.{}) catch @panic("wayland-scanner not found");
    const protocol_output_dir = generateProtocols(b, root_module, wayland_scanner);
    root_module.addIncludePath(protocol_output_dir);
    root_module.addImport("c", translateCBindings(b, target, optimize, devpath, protocol_output_dir));

    b.installArtifact(exe);
}

fn cFlags() []const []const u8 {
    return &.{
        "-std=c11",
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
    };
}

fn translateCBindings(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    devpath: []const u8,
    protocol_output_dir: std.Build.LazyPath,
) *std.Build.Module {
    const bindings = b.addWriteFiles();
    const header = bindings.add("showkeys-bindings.h",
        \\#include <stdbool.h>
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <string.h>
        \\#include <errno.h>
        \\#include <getopt.h>
        \\#include <sys/mman.h>
        \\#include <sys/types.h>
        \\#include <time.h>
        \\#include <unistd.h>
        \\#include <cairo/cairo.h>
        \\#include <wayland-client.h>
        \\#include "config.h"
        \\#include "keys.h"
        \\#include "wlr-layer-shell-unstable-v1-client-protocol.h"
        \\uint32_t wsk_color_parse(const char *text, uint32_t fallback);
        \\
        \\typedef unsigned int GQuark;
        \\typedef int gint;
        \\typedef int gboolean;
        \\typedef char gchar;
        \\typedef struct _GError {
        \\    GQuark domain;
        \\    gint code;
        \\    gchar *message;
        \\} GError;
        \\typedef struct _RsvgHandle RsvgHandle;
        \\typedef struct _PangoContext PangoContext;
        \\typedef unsigned long nfds_t;
        \\struct pollfd {
        \\    int fd;
        \\    short events;
        \\    short revents;
        \\};
        \\enum { POLLIN = 0x001 };
        \\int poll(struct pollfd *fds, nfds_t nfds, int timeout);
        \\struct udev;
        \\struct libinput;
        \\struct libinput_event;
        \\struct xkb_context;
        \\struct xkb_keymap;
        \\struct xkb_state;
        \\struct zxdg_output_manager_v1;
        \\struct zwlr_layer_shell_v1;
        \\struct zwlr_layer_surface_v1;
        \\typedef struct {
        \\    double x;
        \\    double y;
        \\    double width;
        \\    double height;
        \\} RsvgRectangle;
        \\struct wsk_icon_cache_entry {
        \\    char *icon_name;
        \\    RsvgHandle *svg;
        \\    bool failed;
        \\    struct wsk_icon_cache_entry *next;
        \\};
        \\struct wsk_icon_cache {
        \\    struct wsk_icon_cache_entry *entries;
        \\};
        \\struct wsk_theme {
        \\    const char *key_svg_path;
        \\    char *base_dir;
        \\    RsvgHandle *key_svg;
        \\    bool key_svg_failed;
        \\    struct wsk_icon_cache icons;
        \\};
        \\struct wsk_input {
        \\    struct udev *udev;
        \\    struct libinput *libinput;
        \\    struct xkb_context *xkb_context;
        \\    struct xkb_keymap *xkb_keymap;
        \\    struct xkb_state *xkb_state;
        \\};
        \\struct pool_buffer {
        \\    struct wl_buffer *buffer;
        \\    cairo_surface_t *surface;
        \\    cairo_t *cairo;
        \\    PangoContext *pango;
        \\    uint32_t width, height;
        \\    void *data;
        \\    size_t size;
        \\    bool busy;
        \\};
        \\struct wsk_output {
        \\    struct wl_output *output;
        \\    int scale;
        \\    enum wl_output_subpixel subpixel;
        \\    struct wsk_output *next;
        \\};
        \\struct wsk_wayland {
        \\    struct wl_display *display;
        \\    struct wl_registry *registry;
        \\    struct wl_compositor *compositor;
        \\    struct wl_shm *shm;
        \\    struct wl_seat *seat;
        \\    struct wl_keyboard *keyboard;
        \\    struct zxdg_output_manager_v1 *output_mgr;
        \\    struct zwlr_layer_shell_v1 *layer_shell;
        \\    struct wl_surface *surface;
        \\    struct zwlr_layer_surface_v1 *layer_surface;
        \\    uint32_t width, height;
        \\    bool layer_configured, layer_pending_configure, frame_scheduled, dirty;
        \\    struct wl_callback *frame_callback;
        \\    struct pool_buffer buffers[2];
        \\    struct pool_buffer *current_buffer;
        \\    struct wsk_output *output, *outputs;
        \\};
        \\struct wsk_app {
        \\    int devmgr;
        \\    pid_t devmgr_pid;
        \\    struct wsk_config config;
        \\    struct wsk_input input;
        \\    struct wsk_theme theme;
        \\    struct wsk_wayland wayland;
        \\    struct wsk_key_list keys;
        \\    bool run;
        \\};
        \\struct keycap_layout {
        \\    const struct wsk_keypress *key;
        \\    const char *label;
        \\    bool special;
        \\    const char *icon_name;
        \\    RsvgHandle *icon_svg;
        \\    int text_width;
        \\    int text_height;
        \\    int text_baseline;
        \\    int x;
        \\    int y;
        \\    int width;
        \\    int height;
        \\    int icon_x;
        \\    int icon_y;
        \\    int text_x;
        \\    int text_y;
        \\};
        \\RsvgHandle *rsvg_handle_new_from_file(const char *file_name, GError **error);
        \\gboolean rsvg_handle_render_document(RsvgHandle *handle, cairo_t *cr, const RsvgRectangle *viewport, GError **error);
        \\void g_error_free(GError *error);
        \\void g_object_unref(void *object);
        \\PangoContext *pango_cairo_create_context(cairo_t *cr);
        \\void get_text_size(cairo_t *cairo, const char *font, int *width, int *height, int *baseline, double scale, const char *fmt, ...);
        \\void pango_printf(cairo_t *cairo, const char *font, double scale, const char *fmt, ...);
        \\void wsk_cairo_set_source_u32(cairo_t *cr, uint32_t color);
        \\const char *wsk_special_icon_name(const char *key_name);
        \\RsvgHandle *wsk_icon_cache_get(struct wsk_icon_cache *cache, const char *base_dir, const char *icon_name);
        \\void wsk_icon_cache_finish(struct wsk_icon_cache *cache);
        \\bool wsk_theme_init(struct wsk_theme *theme, const char *key_svg_path);
        \\void wsk_theme_finish(struct wsk_theme *theme);
        \\bool wsk_svg_draw_to_rect(cairo_t *cr, RsvgHandle *svg, double x, double y, double width, double height, const char *description);
        \\struct pool_buffer *get_next_buffer(struct wl_shm *shm, struct pool_buffer pool[2], uint32_t width, uint32_t height);
        \\void wsk_wayland_destroy_layer_surface(struct wsk_wayland *wayland);
        \\extern const struct wl_callback_listener frame_listener;
        \\size_t wsk_measure_keycaps(cairo_t *cairo, const struct wsk_keypress *keys, const struct wsk_config *config, struct wsk_theme *theme, int scale, uint32_t *width, uint32_t *height, struct keycap_layout **out_layouts);
        \\void wsk_render_keycaps(cairo_t *cairo, struct keycap_layout *layouts, size_t key_count, const struct wsk_config *config, struct wsk_theme *theme, int scale, uint32_t surface_width, uint32_t content_width);
        \\int devmgr_start(int *fd, pid_t *pid, const char *devpath);
        \\void devmgr_finish(int sock, pid_t pid);
        \\bool wsk_input_init(struct wsk_input *input, struct wsk_app *app);
        \\void wsk_input_finish(struct wsk_input *input);
        \\int wsk_input_get_fd(struct wsk_input *input);
        \\void wsk_input_handle_libinput_event(struct wsk_app *app, struct libinput_event *event, bool *dirty);
        \\bool wsk_wayland_init(struct wsk_wayland *wayland, struct wsk_app *app);
        \\void wsk_wayland_finish(struct wsk_wayland *wayland);
        \\int wsk_wayland_get_fd(struct wsk_wayland *wayland);
        \\int wsk_wayland_dispatch(struct wsk_wayland *wayland, struct wsk_app *app);
        \\int wsk_wayland_flush(struct wsk_wayland *wayland);
        \\void wsk_wayland_set_dirty(struct wsk_app *app);
        \\int libinput_dispatch(struct libinput *libinput);
        \\struct libinput_event *libinput_get_event(struct libinput *libinput);
        \\void libinput_event_destroy(struct libinput_event *event);
        \\char *wsk_xstrdup(const char *str);
        \\char *wsk_path_dirname(const char *path);
        \\char *wsk_join_path3(const char *dir, const char *subdir, const char *file);
        \\
        \\struct wsk_app;
        \\bool wsk_app_init_privileged(struct wsk_app **app_ptr);
        \\bool wsk_app_init(struct wsk_app *app, int argc, char *argv[]);
        \\int wsk_app_run(struct wsk_app *app);
        \\void wsk_app_finish(struct wsk_app *app);
        \\
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("include"));
    translate_c.addIncludePath(protocol_output_dir);
    translate_c.defineCMacro("_POSIX_C_SOURCE", "200809L");
    translate_c.defineCMacro("INPUTDEVPATH", b.fmt("\"{s}\"", .{devpath}));

    for (pkg_config_deps) |dep| {
        translate_c.linkSystemLibrary(dep, .{ .use_pkg_config = .force });
    }
    translate_c.linkSystemLibrary("rt", .{});

    return translate_c.createModule();
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
