#include "icons.h"

#include "theme.h"

#include <stdlib.h>
#include <string.h>

const char *wsk_special_icon_name(const char *key_name) {
    static const struct {
        const char *key_name;
        const char *icon_name;
    } icon_map[] = {
        {"Escape", "escape.svg"},
        {"Tab", "tab.svg"},
        {"ISO_Left_Tab", "tab.svg"},
        {"Enter", "enter.svg"},
        {"Return", "enter.svg"},
        {"KP_Enter", "enter.svg"},
        {"BackSpace", "backspace.svg"},
        {"Delete", "delete.svg"},
        {"KP_Delete", "delete.svg"},
        {"Insert", "insert.svg"},
        {"KP_Insert", "insert.svg"},
        {"Home", "home.svg"},
        {"KP_Home", "home.svg"},
        {"End", "end.svg"},
        {"KP_End", "end.svg"},
        {"Page_Up", "page-up.svg"},
        {"KP_Page_Up", "page-up.svg"},
        {"Page_Down", "page-down.svg"},
        {"KP_Page_Down", "page-down.svg"},
        {"Caps_Lock", "caps-lock.svg"},
        {"Num_Lock", "num-lock.svg"},
        {"Scroll_Lock", "scroll-lock.svg"},
        {"Pause", "pause.svg"},
        {"Break", "pause.svg"},
        {"Print", "print-screen.svg"},
        {"Sys_Req", "print-screen.svg"},
        {"Menu", "menu.svg"},
        {"XF86MenuKB", "menu.svg"},
        {"space", "space.svg"},
        {"KP_Space", "space.svg"},
        {"Shift_L", "shift.svg"},
        {"Shift_R", "shift.svg"},
        {"Control_L", "ctrl.svg"},
        {"Control_R", "ctrl.svg"},
        {"Alt_L", "alt.svg"},
        {"Alt_R", "alt.svg"},
        {"Meta_L", "alt.svg"},
        {"Meta_R", "alt.svg"},
        {"Super_L", "super.svg"},
        {"Super_R", "super.svg"},
        {"Hyper_L", "super.svg"},
        {"Hyper_R", "super.svg"},
        {"Left", "arrow-left.svg"},
        {"KP_Left", "arrow-left.svg"},
        {"Right", "arrow-right.svg"},
        {"KP_Right", "arrow-right.svg"},
        {"Up", "arrow-up.svg"},
        {"KP_Up", "arrow-up.svg"},
        {"Down", "arrow-down.svg"},
        {"KP_Down", "arrow-down.svg"},
        {"KP_Begin", "keypad.svg"},
        {"KP_Add", "keypad.svg"},
        {"KP_Subtract", "keypad.svg"},
        {"KP_Multiply", "keypad.svg"},
        {"KP_Divide", "keypad.svg"},
        {"XF86AudioPlay", "media-play.svg"},
        {"XF86AudioPause", "pause.svg"},
        {"XF86AudioStop", "media-stop.svg"},
        {"XF86AudioPrev", "media-prev.svg"},
        {"XF86AudioNext", "media-next.svg"},
        {"XF86AudioRaiseVolume", "volume-up.svg"},
        {"XF86AudioLowerVolume", "volume-down.svg"},
        {"XF86AudioMute", "volume-mute.svg"},
        {"XF86MonBrightnessUp", "brightness.svg"},
        {"XF86MonBrightnessDown", "brightness.svg"},
        {"XF86KbdBrightnessUp", "brightness.svg"},
        {"XF86KbdBrightnessDown", "brightness.svg"},
        {"XF86Fn", "fn.svg"},
        {"XF86Fn_Esc", "fn.svg"},
        {"Mouse Left", "mouse-left.svg"},
        {"Mouse Right", "mouse-right.svg"},
        {"Mouse Middle", "mouse-middle.svg"},
        {"Mouse Wheel Up", "mouse-wheel-up.svg"},
        {"Mouse Wheel Down", "mouse-wheel-down.svg"},
        {"Mouse Wheel Left", "mouse-wheel-left.svg"},
        {"Mouse Wheel Right", "mouse-wheel-right.svg"},
        {"Mouse Side", "mouse-side.svg"},
        {"Mouse Extra", "mouse-extra.svg"},
        {"Mouse Forward", "mouse-forward.svg"},
        {"Mouse Back", "mouse-back.svg"},
    };

    for (size_t i = 0; i < sizeof(icon_map) / sizeof(icon_map[0]); ++i) {
        if (strcmp(key_name, icon_map[i].key_name) == 0) {
            return icon_map[i].icon_name;
        }
    }
    return NULL;
}

RsvgHandle *wsk_icon_cache_get(struct wsk_icon_cache *cache,
                               const char *base_dir,
                               const char *icon_name) {
    if (!base_dir || !icon_name) {
        return NULL;
    }

    for (struct wsk_icon_cache_entry *entry = cache->entries; entry;
         entry = entry->next) {
        if (strcmp(entry->icon_name, icon_name) == 0) {
            return entry->failed ? NULL : entry->svg;
        }
    }

    struct wsk_icon_cache_entry *entry = calloc(1, sizeof(*entry));
    if (!entry) {
        return NULL;
    }
    entry->icon_name = wsk_xstrdup(icon_name);
    if (!entry->icon_name) {
        free(entry);
        return NULL;
    }

    char *path = wsk_join_path3(base_dir, "icons", icon_name);
    if (!path) {
        entry->failed = true;
    } else {
        GError *error = NULL;
        entry->svg = rsvg_handle_new_from_file(path, &error);
        if (!entry->svg) {
            entry->failed = true;
            if (error) {
                g_error_free(error);
            }
        }
        free(path);
    }

    entry->next = cache->entries;
    cache->entries = entry;
    return entry->failed ? NULL : entry->svg;
}

void wsk_icon_cache_finish(struct wsk_icon_cache *cache) {
    struct wsk_icon_cache_entry *icons = cache->entries;
    while (icons) {
        struct wsk_icon_cache_entry *next = icons->next;
        if (icons->svg) {
            g_object_unref(icons->svg);
        }
        free(icons->icon_name);
        free(icons);
        icons = next;
    }
    cache->entries = NULL;
}

