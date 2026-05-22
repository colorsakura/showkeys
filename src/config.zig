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
    /// Animation duration in milliseconds for keypress entry effects.
    anim_duration: u32 = 200,
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

/// Errors that can occur during config parsing.
pub const ParseError = error{
    /// Usage was printed (caller should exit).
    Usage,
    /// A required argument value was missing.
    MissingValue,
    /// An integer argument could not be parsed.
    InvalidInteger,
    /// An anchor string was not recognised.
    InvalidAnchor,
    /// An unknown flag was encountered.
    UnknownFlag,
};

/// Parse command-line arguments (Zig slice) into the config.
pub fn parse(config: *Config, args: []const [:0]const u8) ParseError!void {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len < 2 or arg[0] != '-') {
            printUsage();
            return error.Usage;
        }
        switch (arg[1]) {
            'b' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.background = color.parse(args[i], 0xFFFFFFFF);
            },
            'f' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.foreground = color.parse(args[i], 0xFFFFFFFF);
            },
            's' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.specialfg = color.parse(args[i], 0xFFFFFFFF);
            },
            'F' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.font = args[i].ptr;
            },
            't' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.timeout = std.fmt.parseInt(i32, args[i], 10) catch {
                    std.log.err("Invalid timeout", .{});
                    return error.InvalidInteger;
                };
            },
            'n' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.max_keys = std.fmt.parseInt(i32, args[i], 10) catch {
                    std.log.err("Invalid max key count", .{});
                    return error.InvalidInteger;
                };
                if (config.max_keys < 1) {
                    std.log.err("Invalid max key count", .{});
                    return error.InvalidInteger;
                }
            },
            'a' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                const anchor_str = args[i];
                const anchor = parseAnchor(anchor_str) orelse {
                    std.log.err("Invalid anchor value '{s}'", .{anchor_str});
                    return error.InvalidAnchor;
                };
                config.anchor = anchor.toU32();
            },
            'm' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.margin = std.fmt.parseInt(i32, args[i], 10) catch {
                    std.log.err("Invalid margin", .{});
                    return error.InvalidInteger;
                };
            },
            'o' => {
                std.log.err("-o is unimplemented", .{});
                config.exit_after_parse = true;
                config.exit_code = 0;
                return;
            },
            'k' => {
                i += 1;
                if (i >= args.len) return error.MissingValue;
                config.key_svg_path = args[i].ptr;
            },
            'h' => {
                printUsage();
                return error.Usage;
            },
            else => {
                printUsage();
                return error.UnknownFlag;
            },
        }
    }
}
