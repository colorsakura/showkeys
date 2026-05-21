const std = @import("std");
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

pub const Config = struct {
    foreground: u32 = 0xFFFFFFFF,
    background: u32 = 0x00000000,
    specialfg: u32 = 0xAAAAAAFF,
    font: []const u8 = "monospace 24",
    timeout: u32 = 1,
    max_keys: u32 = 5,
    key_svg_path: ?[]const u8 = null,
    anchor: Anchor = .{ .bottom = true, .right = true },
    margin: u32 = 32,
    exit_after_parse: bool = false,
    exit_code: u32 = 0,
};

const usage =
    "usage: showkeys [-b|-f|-s #RRGGBB[AA]] [-F font] " ++
    "[-t timeout] [-n max-keys]\n\t" ++
    "[-a top|left|right|bottom] [-m margin] " ++
    "[-o output] [-k key.svg]\n";

pub fn printUsage() void {
    std.log.info("{s}", .{usage});
}

/// Parse an anchor position string into an Anchor bitfield.
/// Returns null on invalid input.
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

pub const ParseError = error{
    UnknownOption,
    UnknownArgument,
    InvalidArgument,
    HelpRequested,
};

/// Parse command-line arguments into a Config.
/// `args` should be the full argument list including argv[0] (the program name).
pub fn parse(args: [][]const u8) ParseError!Config {
    var self = Config{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len < 2 or arg[0] != '-') {
            printUsage();
            return error.UnknownArgument;
        }
        switch (arg[1]) {
            'b' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-b requires a color argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.background = color.parse(args[i], 0xFFFFFFFF);
            },
            'f' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-f requires a color argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.foreground = color.parse(args[i], 0xFFFFFFFF);
            },
            's' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-s requires a color argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.specialfg = color.parse(args[i], 0xFFFFFFFF);
            },
            'F' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-F requires a font argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.font = args[i];
            },
            't' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-t requires a timeout argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.timeout = std.fmt.parseInt(u32, args[i], 10) catch {
                    std.log.err("Invalid timeout '{s}'", .{args[i]});
                    return error.InvalidArgument;
                };
            },
            'n' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-n requires a number argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.max_keys = std.fmt.parseInt(u32, args[i], 10) catch {
                    std.log.err("Invalid max key count '{s}'", .{args[i]});
                    return error.InvalidArgument;
                };
                if (self.max_keys < 1) {
                    std.log.err("Invalid max key count '{s}'", .{args[i]});
                    return error.InvalidArgument;
                }
            },
            'a' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-a requires an anchor argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.anchor = parseAnchor(args[i]) orelse {
                    std.log.err("Invalid anchor value '{s}'", .{args[i]});
                    return error.InvalidArgument;
                };
            },
            'm' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-m requires a margin argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.margin = std.fmt.parseInt(u32, args[i], 10) catch {
                    std.log.err("Invalid margin '{s}'", .{args[i]});
                    return error.InvalidArgument;
                };
            },
            'o' => {
                std.log.err("-o is unimplemented", .{});
                self.exit_after_parse = true;
                self.exit_code = 0;
                return self;
            },
            'k' => {
                i += 1;
                if (i >= args.len) {
                    std.log.err("-k requires a path argument", .{});
                    printUsage();
                    return error.InvalidArgument;
                }
                self.key_svg_path = args[i];
            },
            'h' => {
                printUsage();
                return error.HelpRequested;
            },
            else => {
                std.log.err("Unknown option '-{c}'", .{arg[1]});
                printUsage();
                return error.UnknownOption;
            },
        }
    }
    return self;
}

// ---------------------------------------------------------------------------
// Backward-compatible C ABI bridge — used by app.zig and keycap.zig until
// they are migrated to the native Zig API.
// ---------------------------------------------------------------------------

/// Layout must match `struct wsk_config` in `include/config.h`.
/// `const char *` fields translate to `?[*:0]const u8`.
const CConfig = extern struct {
    foreground: u32,
    background: u32,
    specialfg: u32,
    font: ?[*:0]const u8,
    timeout: i32,
    max_keys: i32,
    key_svg_path: ?[*:0]const u8,
    anchor: u32,
    margin: i32,
    exit_after_parse: bool,
    exit_code: i32,
};

export fn wsk_config_init_defaults(config: *CConfig) void {
    const def = Config{};
    config.foreground = def.foreground;
    config.background = def.background;
    config.specialfg = def.specialfg;
    config.font = @as(?[*:0]const u8, @ptrCast(def.font.ptr));
    config.timeout = @intCast(def.timeout);
    config.max_keys = @intCast(def.max_keys);
    config.key_svg_path = null;
    config.anchor = def.anchor.toU32();
    config.margin = @intCast(def.margin);
    config.exit_after_parse = def.exit_after_parse;
    config.exit_code = @intCast(def.exit_code);
}

export fn wsk_config_print_usage(stream: ?*anyopaque) void {
    _ = stream;
    std.log.info("{s}", .{usage});
}

export fn wsk_config_parse(
    config: *CConfig,
    argc: i32,
    argv: [*c][*c]u8,
) bool {
    // Parse C-style args directly (the [*c] type layout is incompatible with
    // [][]const u8, so we cannot call the Zig parse() here).
    var i: i32 = 1;
    while (i < argc) : (i += 1) {
        const arg = std.mem.sliceTo(argv[@as(usize, @intCast(i))], 0);
        if (arg.len < 2 or arg[0] != '-') {
            wsk_config_print_usage(null);
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
                wsk_config_print_usage(null);
                return false;
            },
            else => {
                wsk_config_print_usage(null);
                return false;
            },
        }
    }

    return true;
}
