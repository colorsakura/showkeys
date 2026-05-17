#include "config.h"

#include "color.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#include <getopt.h>
#include <stdlib.h>
#include <string.h>

void wsk_config_init_defaults(struct wsk_config *config) {
    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                     ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
    config->margin = 32;
    config->background = 0x00000000;
    config->specialfg = 0xAAAAAAFF;
    config->foreground = 0xFFFFFFFF;
    config->font = "monospace 24";
    config->timeout = 1;
    config->max_keys = 5;
    config->key_svg_path = NULL;
    config->exit_after_parse = false;
    config->exit_code = 0;
}

void wsk_config_print_usage(FILE *stream) {
    fprintf(stream, "usage: wshowkeys [-b|-f|-s #RRGGBB[AA]] [-F font] "
            "[-t timeout] [-n max-keys]\n\t"
            "[-a top|left|right|bottom] [-m margin] "
            "[-o output] [-k key.svg]\n");
}

bool wsk_config_parse(struct wsk_config *config, int argc, char *argv[]) {
    int c;
    while ((c = getopt(argc, argv, "hb:f:s:F:t:n:a:m:o:k:")) != -1) {
        switch (c) {
            case 'b':
                config->background = wsk_color_parse(optarg, 0xFFFFFFFF);
                break;
            case 'f':
                config->foreground = wsk_color_parse(optarg, 0xFFFFFFFF);
                break;
            case 's':
                config->specialfg = wsk_color_parse(optarg, 0xFFFFFFFF);
                break;
            case 'F':
                config->font = optarg;
                break;
            case 't':
                config->timeout = atoi(optarg);
                break;
            case 'n':
                config->max_keys = atoi(optarg);
                if (config->max_keys < 1) {
                    fprintf(stderr, "Invalid max key count '%s'\n", optarg);
                    return false;
                }
                break;
            case 'a':
                if (strcmp(optarg, "top-right") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
                } else if (strcmp(optarg, "top-center") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
                } else if (strcmp(optarg, "top-left") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
                } else if (strcmp(optarg, "bottom-right") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
                } else if (strcmp(optarg, "bottom-center") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
                } else if (strcmp(optarg, "bottom-left") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                     ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
                } else if (strcmp(optarg, "center-right") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
                } else if (strcmp(optarg, "center-left") == 0) {
                    config->anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT;
                } else if (strcmp(optarg, "center") == 0) {
                    config->anchor = 0;
                } else {
                    fprintf(stderr, "Invalid anchor value '%s'\n", optarg);
                }
                break;
            case 'm':
                config->margin = atoi(optarg);
                break;
            case 'o':
                fprintf(stderr, "-o is unimplemented\n");
                config->exit_after_parse = true;
                config->exit_code = 0;
                return true;
            case 'k':
                config->key_svg_path = optarg;
                break;
            default:
                wsk_config_print_usage(stderr);
                return false;
        }
    }

    return true;
}
