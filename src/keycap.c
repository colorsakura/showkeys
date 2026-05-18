#include "keycap.h"

#include "color.h"
#include "pango.h"
#include "theme.h"

#include <stdio.h>
#include <stdlib.h>

struct keycap_style {
    int padding_x;
    int padding_y;
    int gap;
    int radius;
    int border_width;
    int icon_size;
    uint32_t normal_bg;
    uint32_t normal_fg;
    uint32_t special_bg;
    uint32_t special_fg;
    uint32_t border;
};

static void rounded_rectangle(cairo_t *cairo, double x, double y, double w,
                              double h, double r) {
    if (r > w / 2.0) {
        r = w / 2.0;
    }
    if (r > h / 2.0) {
        r = h / 2.0;
    }

    cairo_new_sub_path(cairo);
    cairo_arc(cairo, x + w - r, y + r, r, -1.5707963267948966, 0.0);
    cairo_arc(cairo, x + w - r, y + h - r, r, 0.0, 1.5707963267948966);
    cairo_arc(cairo, x + r, y + h - r, r, 1.5707963267948966,
              3.141592653589793);
    cairo_arc(cairo, x + r, y + r, r, 3.141592653589793,
              4.71238898038469);
    cairo_close_path(cairo);
}

static void draw_cairo_keycap(cairo_t *cairo, const struct keycap_layout *layout,
                              const struct keycap_style *style, int radius,
                              int border_width) {
    rounded_rectangle(cairo, layout->x, layout->y, layout->width, layout->height,
                      radius);
    wsk_cairo_set_source_u32(cairo, layout->special
                                        ? style->special_bg
                                        : style->normal_bg);
    cairo_fill_preserve(cairo);

    if (border_width > 0) {
        cairo_set_line_width(cairo, border_width);
        wsk_cairo_set_source_u32(cairo, style->border);
        cairo_stroke(cairo);
    } else {
        cairo_new_path(cairo);
    }
}

static bool draw_svg_keycap(cairo_t *cairo, RsvgHandle *svg,
                            const struct keycap_layout *layout) {
    return wsk_svg_draw_to_rect(cairo, svg, layout->x, layout->y, layout->width,
                                layout->height, "key");
}

static bool draw_svg_icon(cairo_t *cairo, RsvgHandle *svg,
                          const struct keycap_layout *layout,
                          int icon_size) {
    return wsk_svg_draw_to_rect(cairo, svg, layout->icon_x, layout->icon_y,
                                icon_size, icon_size, "icon");
}

size_t wsk_measure_keycaps(cairo_t *cairo, const struct wsk_keypress *keys,
                           const struct wsk_config *config,
                           struct wsk_theme *theme, int scale,
                           uint32_t *width, uint32_t *height,
                           struct keycap_layout **out_layouts) {
    *width = 0;
    *height = 0;
    *out_layouts = NULL;

    size_t key_count = 0;
    for (const struct wsk_keypress *key = keys; key; key = key->next) {
        ++key_count;
    }
    if (key_count == 0) {
        return 0;
    }

    struct keycap_layout *layouts = calloc(key_count, sizeof(*layouts));
    if (!layouts) {
        return 0;
    }

    const struct keycap_style style = {
        .padding_x = 12,
        .padding_y = 6,
        .gap = 6,
        .radius = 8,
        .border_width = 1,
        .icon_size = 32,
    };

    const int padding_x = style.padding_x * scale;
    const int padding_y = style.padding_y * scale;
    const int gap = style.gap * scale;
    const int icon_size = style.icon_size * scale;

    int text_min_width = 0;
    int text_min_height = 0;
    int text_min_baseline = 0;
    get_text_size(cairo, config->font, &text_min_width, &text_min_height,
                  &text_min_baseline, scale, "M");

    const int min_content_width =
            icon_size > text_min_width ? icon_size : text_min_width;
    const int min_content_height =
            icon_size > text_min_height ? icon_size : text_min_height;

    size_t i = 0;
    int max_width = 0;
    int max_height = 0;
    for (const struct wsk_keypress *key = keys; key; key = key->next) {
        struct keycap_layout *layout = &layouts[i++];
        layout->key = key;
        layout->special = key->utf8[0] == '\0';
        layout->label = layout->special ? key->name : key->utf8;
        layout->icon_name = layout->special ? wsk_special_icon_name(key->name) : NULL;
        layout->icon_svg = wsk_icon_cache_get(&theme->icons, theme->base_dir,
                                              layout->icon_name);
        get_text_size(cairo, config->font, &layout->text_width,
                      &layout->text_height, &layout->text_baseline, scale, "%s",
                      layout->label);
        int content_width = layout->icon_svg ? icon_size : layout->text_width;
        int content_height = layout->icon_svg ? icon_size : layout->text_height;
        if (content_width < min_content_width) {
            content_width = min_content_width;
        }
        if (content_height < min_content_height) {
            content_height = min_content_height;
        }
        layout->width = content_width + padding_x * 2;
        layout->height = content_height + padding_y * 2;
        if (max_width < layout->width) {
            max_width = layout->width;
        }
        if (max_height < layout->height) {
            max_height = layout->height;
        }
    }

    int popup_height = max_height;
    for (i = 0; i < key_count; ++i) {
        struct keycap_layout *layout = &layouts[i];
        if ((layout->icon_svg || !layout->special) && layout->width > popup_height) {
            popup_height = layout->width;
        }
    }

    size_t total_width = 0;
    for (i = 0; i < key_count; ++i) {
        struct keycap_layout *layout = &layouts[i];
        layout->height = popup_height;
        if (layout->icon_svg || !layout->special) {
            layout->width = popup_height;
        } else {
            layout->width = max_width;
        }
        total_width += (size_t) layout->width;
    }

    *width = (uint32_t)(total_width + (key_count - 1) * (size_t) gap);
    *height = popup_height;
    *out_layouts = layouts;
    return key_count;
}

void wsk_render_keycaps(cairo_t *cairo, struct keycap_layout *layouts,
                        size_t key_count, const struct wsk_config *config,
                        struct wsk_theme *theme, int scale) {
    const struct keycap_style style = {
        .padding_x = 12,
        .padding_y = 6,
        .gap = 6,
        .radius = 8,
        .border_width = 1,
        .icon_size = 32,
        .normal_bg = 0x222222CC,
        .normal_fg = config->foreground,
        .special_bg = 0x444444CC,
        .special_fg = config->specialfg,
        .border = 0xFFFFFF33,
    };

    const int gap = style.gap * scale;
    const int radius = style.radius * scale;
    const int border_width = style.border_width * scale;
    const int icon_size = style.icon_size * scale;

    int x = 0;
    for (size_t i = 0; i < key_count; ++i) {
        struct keycap_layout *layout = &layouts[i];
        layout->x = x;
        layout->y = 0;
        x += layout->width + gap;

        if (!theme->key_svg || theme->key_svg_failed ||
            !draw_svg_keycap(cairo, theme->key_svg, layout)) {
            if (theme->key_svg && !theme->key_svg_failed) {
                fprintf(stderr, "Falling back to Cairo keycap background\n");
                theme->key_svg_failed = true;
            }
            draw_cairo_keycap(cairo, layout, &style, radius, border_width);
        }

        if (layout->icon_svg) {
            layout->icon_x = layout->x + (layout->width - icon_size) / 2;
            layout->icon_y = layout->y + (layout->height - icon_size) / 2;
            draw_svg_icon(cairo, layout->icon_svg, layout, icon_size);
            continue;
        }

        layout->text_x = layout->x + (layout->width - layout->text_width) / 2;
        layout->text_y = layout->y + (layout->height - layout->text_height) / 2;
        wsk_cairo_set_source_u32(cairo,
                                 layout->special ? style.special_fg : style.normal_fg);
        cairo_move_to(cairo, layout->text_x, layout->text_y);
        pango_printf(cairo, config->font, scale, "%s", layout->label);
    }
}

void wsk_render_keycaps_to_cairo(cairo_t *cairo, const struct wsk_keypress *keys,
                                 const struct wsk_config *config,
                                 struct wsk_theme *theme, int scale,
                                 uint32_t *width, uint32_t *height) {
    cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE);
    wsk_cairo_set_source_u32(cairo, config->background);
    cairo_paint(cairo);
    cairo_set_operator(cairo, CAIRO_OPERATOR_OVER);

    struct keycap_layout *layouts = NULL;
    size_t key_count = wsk_measure_keycaps(cairo, keys, config, theme, scale,
                                           width, height, &layouts);
    if (layouts) {
        wsk_render_keycaps(cairo, layouts, key_count, config, theme, scale);
        free(layouts);
    }
}
