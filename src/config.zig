const std = @import("std");
const c = @import("c");
const color = @import("color.zig");

// Anchor bit values matching zwlr_layer_surface_v1 anchor enum
pub const anchor_top: u32 = 1;
pub const anchor_bottom: u32 = 2;
pub const anchor_left: u32 = 4;
pub const anchor_right: u32 = 8;

/// Bitfield-compatible packed struct for layer-surface anchor.
/// Field order must be top(1), bottom(2), left(4), right(8) so that
/// @bitCast produces the same u32 value as the Wayland protocol enum.
pub const Anchor = packed struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,
    _: u28 = 0,

    pub fn toU32(self: Anchor) u32 {
        return @as(u32, @bitCast(self));
    }

    pub fn fromU32(v: u32) Anchor {
        return @as(Anchor, @bitCast(v));
    }
};

/// Config is the single source of truth — an `extern struct` whose layout
/// matches `struct wsk_config` from the original C header.
/// The pointer-cast in `app.zig` (`@ptrCast(&app.config)`) is safe because
/// `types.Config` and `config.Config` share the same extern layout.
pub const Config = extern struct {
    foreground: u32 = 0xFFFFFFFF,
    background: u32 = 0x00000000,
    specialfg: u32 = 0xAAAAAAFF,
    font: ?[*:0]const u8 = "monospace 24",
    timeout: i32 = 1,
    max_keys: i32 = 5,
    key_svg_path: ?[*:0]const u8 = null,
    anchor: u32 = @as(u32, @bitCast(Anchor{ .bottom = true, .right = true })),
    margin: i32 = 32,
    exit_after_parse: bool = false,
    exit_code: i32 = 0,
};

const usage =
    "usage: showkeys [-b|-f|-s #RRGGBB[AA]] [-F font] " ++
    "[-t timeout] [-n max-keys]\n\t" ++
    "[-a top|left|right|bottom] [-m margin] " ++
    "[-o output] [-k key.svg]\n";

/// Reset `config` to default values.
pub fn initDefaults(config: *Config) void {
    config.* = .{};
}

pub fn printUsage() void {
    std.log.info("{s}", .{usage});
}

/// Parse an anchor position string into an Anchor bitfield.
pub fn parseAnchor(text: []const u8) ?Anchor {
    if (std.mem.eql(u8, text, "top-right")) return Anchor{ .top = true, .right = true };
    if (std.mem.eql(u8, text, "top-center")) return Anchor{ .top = true };
    if (std.mem.eql(u8, text, "top-left")) return Anchor{ .top = true, .left = true };
    if (std.mem.eql(u8, text, "bottom-right")) return Anchor{ .bottom = true, .right = true };
    if (std.mem.eql(u8, text, "bottom-center")) return Anchor{ .bottom = true };
    if (std.mem.eql(u8, text, "bottom-left")) return Anchor{ .bottom = true, .left = true };
    if (std.mem.eql(u8, text, "center-right")) return Anchor{ .right = true };
    if (std.mem.eql(u8, text, "center-left")) return Anchor{ .left = true };
    if (std.mem.eql(u8, text, "center")) return Anchor{};
    return null;
}

/// Parse command-line arguments (C‑style argc/argv) into the config.
pub fn parse(config: *Config, argc: i32, argv: [*c][*c]u8) bool {
    var i: i32 = 1;
    while (i < argc) : (i += 1) {
        const arg = std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0);
        if (arg.len < 2 or arg[0] != '-') {
            printUsage();
            return false;
        }
        switch (arg[1]) {
            'b' => {
                i += 1;
                if (i >= argc) return false;
                config.background = color.parse(std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 0xFFFFFFFF);
            },
            'f' => {
                i += 1;
                if (i >= argc) return false;
                config.foreground = color.parse(std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 0xFFFFFFFF);
            },
            's' => {
                i += 1;
                if (i >= argc) return false;
                config.specialfg = color.parse(std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 0xFFFFFFFF);
            },
            'F' => {
                i += 1;
                if (i >= argc) return false;
                config.font = @ptrCast(argv[@as(usize, @intCast(i))]);
            },
            't' => {
                i += 1;
                if (i >= argc) return false;
                config.timeout = std.fmt.parseInt(i32, std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 10) catch {
                    std.log.err("Invalid timeout", .{});
                    return false;
                };
            },
            'n' => {
                i += 1;
                if (i >= argc) return false;
                config.max_keys = std.fmt.parseInt(i32, std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 10) catch {
                    std.log.err("Invalid max key count", .{});
                    return false;
                };
                if (config.max_keys < 1) {
                    std.log.err("Invalid max key count", .{});
                    return false;
                }
            },
            'a' => {
                i += 1;
                if (i >= argc) return false;
                const anchor_str = std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0);
                const anchor = parseAnchor(anchor_str) orelse {
                    std.log.err("Invalid anchor value '{s}'", .{anchor_str});
                    return false;
                };
                config.anchor = anchor.toU32();
            },
            'm' => {
                i += 1;
                if (i >= argc) return false;
                config.margin = std.fmt.parseInt(i32, std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0), 10) catch {
                    std.log.err("Invalid margin", .{});
                    return false;
                };
            },
            'o' => {
                std.log.err("-o is unimplemented", .{});
                config.exit_after_parse = true;
                config.exit_code = 0;
                return true;
            },
            'k' => {
                i += 1;
                if (i >= argc) return false;
                config.key_svg_path = @ptrCast(argv[@as(usize, @intCast(i))]);
            },
            'h' => {
                printUsage();
                return false;
            },
            else => {
                printUsage();
                return false;
            },
        }
    }

    return true;
}
