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
        \\#include <xkbcommon/xkbcommon.h>
        \\
        \\/* ---- GLib / librsvg / Pango opaque type declarations ---- */
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
        \\typedef struct {
        \\    double x;
        \\    double y;
        \\    double width;
        \\    double height;
        \\} RsvgRectangle;
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
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
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
