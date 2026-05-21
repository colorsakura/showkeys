const std = @import("std");

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
    const devpath = b.option([]const u8, "devpath", "Input device path prefix compiled into the privileged device manager") orelse default_devpath;

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
    configureCModule(b, root_module, devpath);

    const wayland_scanner = b.findProgram(&.{"wayland-scanner"}, &.{}) catch @panic("wayland-scanner not found");
    const protocol_output_dir = generateProtocols(b, root_module, wayland_scanner);
    root_module.addIncludePath(protocol_output_dir);
    root_module.addImport("c", translateCBindings(b, target, optimize, devpath, protocol_output_dir));

    b.installArtifact(exe);
}

fn configureCModule(b: *std.Build, module: *std.Build.Module, devpath: []const u8) void {
    module.addCMacro("_POSIX_C_SOURCE", posix_c_source);
    module.addCMacro("INPUTDEVPATH", cStringLiteral(b, devpath));
    linkSystemLibraries(module);
}

fn configureTranslateC(b: *std.Build, translate_c: *std.Build.Step.TranslateC, devpath: []const u8, protocol_output_dir: std.Build.LazyPath) void {
    translate_c.addIncludePath(protocol_output_dir);
    translate_c.defineCMacro("_POSIX_C_SOURCE", posix_c_source);
    translate_c.defineCMacro("INPUTDEVPATH", cStringLiteral(b, devpath));

    linkSystemLibraries(translate_c);
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
        \\#include <fcntl.h>
        \\#include <limits.h>
        \\#include <sys/mman.h>
        \\#include <sys/socket.h>
        \\#include <sys/wait.h>
        \\#include <sys/types.h>
        \\#include <time.h>
        \\#include <unistd.h>
        \\#include <cairo/cairo.h>
        \\#include <libinput.h>
        \\#include <libudev.h>
        \\#include <linux/input-event-codes.h>
        \\#include <wayland-client.h>
        \\#include <xkbcommon/xkbcommon.h>
        \\#include "xdg-output-unstable-v1-client-protocol.h"
        \\#include "wlr-layer-shell-unstable-v1-client-protocol.h"
        \\
        \\/* ---- project struct definitions (C source files removed) ---- */
        \\struct wsk_config {
        \\    uint32_t foreground;
        \\    uint32_t background;
        \\    uint32_t specialfg;
        \\    const char *font;
        \\    int timeout;
        \\    int max_keys;
        \\    const char *key_svg_path;
        \\    uint32_t anchor;
        \\    int margin;
        \\    bool exit_after_parse;
        \\    int exit_code;
        \\};
        \\struct wsk_keypress {
        \\    xkb_keysym_t sym;
        \\    char name[128];
        \\    char utf8[128];
        \\    struct wsk_keypress *next;
        \\};
        \\struct wsk_key_list {
        \\    struct wsk_keypress *head;
        \\    struct timespec last_key;
        \\};
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
        \\typedef struct _PangoLayout PangoLayout;
        \\typedef struct _PangoAttrList PangoAttrList;
        \\typedef struct _PangoAttribute PangoAttribute;
        \\typedef struct _PangoFontDescription PangoFontDescription;
        \\enum { PANGO_SCALE = 1024 };
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
        \\PangoLayout *pango_cairo_create_layout(cairo_t *cr);
        \\void pango_cairo_update_layout(cairo_t *cr, PangoLayout *layout);
        \\void pango_cairo_show_layout(cairo_t *cr, PangoLayout *layout);
        \\void pango_cairo_context_set_font_options(PangoContext *context, const cairo_font_options_t *options);
        \\PangoAttrList *pango_attr_list_new(void);
        \\void pango_attr_list_insert(PangoAttrList *list, PangoAttribute *attr);
        \\void pango_attr_list_unref(PangoAttrList *list);
        \\PangoAttribute *pango_attr_scale_new(double scale_factor);
        \\PangoFontDescription *pango_font_description_from_string(const char *str);
        \\void pango_font_description_free(PangoFontDescription *desc);
        \\void pango_layout_set_text(PangoLayout *layout, const char *text, int length);
        \\void pango_layout_set_font_description(PangoLayout *layout, const PangoFontDescription *desc);
        \\void pango_layout_set_single_paragraph_mode(PangoLayout *layout, gboolean setting);
        \\void pango_layout_set_attributes(PangoLayout *layout, PangoAttrList *attrs);
        \\void pango_layout_get_pixel_size(PangoLayout *layout, int *width, int *height);
        \\int pango_layout_get_baseline(PangoLayout *layout);
        \\PangoContext *pango_layout_get_context(PangoLayout *layout);
        \\extern const struct wl_callback_listener frame_listener;
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureTranslateC(b, translate_c, devpath, protocol_output_dir);

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
