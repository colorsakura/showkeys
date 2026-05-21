const std = @import("std");
const color = @import("color.zig");
const c = @import("c");

const usage = "usage: showkeys [-b|-f|-s #RRGGBB[AA]] [-F font] " ++
    "[-t timeout] [-n max-keys]\n\t" ++
    "[-a top|left|right|bottom] [-m margin] " ++
    "[-o output] [-k key.svg]\n";

export fn wsk_config_init_defaults(config: *c.struct_wsk_config) void {
    config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    config.margin = 32;
    config.background = 0x00000000;
    config.specialfg = 0xAAAAAAFF;
    config.foreground = 0xFFFFFFFF;
    config.font = "monospace 24";
    config.timeout = 1;
    config.max_keys = 5;
    config.key_svg_path = null;
    config.exit_after_parse = false;
    config.exit_code = 0;
}

export fn wsk_config_print_usage(stream: ?*c.FILE) void {
    _ = c.fprintf(stream, usage);
}

export fn wsk_config_parse(config: *c.struct_wsk_config, argc: c_int, argv: [*c][*c]u8) bool {
    while (true) {
        const option = c.getopt(argc, argv, "hb:f:s:F:t:n:a:m:o:k:");
        if (option == -1) {
            break;
        }

        switch (option) {
            'b' => config.background = color.parse(std.mem.span(c.optarg), 0xFFFFFFFF),
            'f' => config.foreground = color.parse(std.mem.span(c.optarg), 0xFFFFFFFF),
            's' => config.specialfg = color.parse(std.mem.span(c.optarg), 0xFFFFFFFF),
            'F' => config.font = c.optarg,
            't' => config.timeout = c.atoi(c.optarg),
            'n' => {
                config.max_keys = c.atoi(c.optarg);
                if (config.max_keys < 1) {
                    _ = c.fprintf(c.stderr, "Invalid max key count '%s'\n", c.optarg);
                    return false;
                }
            },
            'a' => parseAnchor(config, c.optarg),
            'm' => config.margin = c.atoi(c.optarg),
            'o' => {
                _ = c.fprintf(c.stderr, "-o is unimplemented\n");
                config.exit_after_parse = true;
                config.exit_code = 0;
                return true;
            },
            'k' => config.key_svg_path = c.optarg,
            else => {
                wsk_config_print_usage(c.stderr);
                return false;
            },
        }
    }

    return true;
}

fn parseAnchor(config: *c.struct_wsk_config, optarg: [*c]const u8) void {
    if (c.strcmp(optarg, "top-right") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    } else if (c.strcmp(optarg, "top-center") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
    } else if (c.strcmp(optarg, "top-left") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
    } else if (c.strcmp(optarg, "bottom-right") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    } else if (c.strcmp(optarg, "bottom-center") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
    } else if (c.strcmp(optarg, "bottom-left") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
            c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
    } else if (c.strcmp(optarg, "center-right") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    } else if (c.strcmp(optarg, "center-left") == 0) {
        config.anchor = c.ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
    } else if (c.strcmp(optarg, "center") == 0) {
        config.anchor = 0;
    } else {
        _ = c.fprintf(c.stderr, "Invalid anchor value '%s'\n", optarg);
    }
}
