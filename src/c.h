#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <cairo/cairo.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#include <xkbcommon/xkbcommon.h>

/* ---- GLib / librsvg / Pango opaque type declarations ---- */
typedef unsigned int GQuark;
typedef int gint;
typedef int gboolean;
typedef char gchar;
typedef struct _GError {
    GQuark domain;
    gint code;
    gchar *message;
} GError;
typedef struct _RsvgHandle RsvgHandle;
typedef struct _PangoContext PangoContext;
typedef struct _PangoLayout PangoLayout;
typedef struct _PangoAttrList PangoAttrList;
typedef struct _PangoAttribute PangoAttribute;
typedef struct _PangoFontDescription PangoFontDescription;
enum { PANGO_SCALE = 1024 };
typedef struct {
    double x;
    double y;
    double width;
    double height;
} RsvgRectangle;
typedef unsigned long nfds_t;
struct pollfd {
    int fd;
    short events;
    short revents;
};
enum { POLLIN = 0x001 };
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
struct udev;
struct libinput;
struct libinput_event;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;
RsvgHandle *rsvg_handle_new_from_file(const char *file_name, GError **error);
RsvgHandle *rsvg_handle_new_from_data(const unsigned char *data, unsigned long data_len, GError **error);
gboolean rsvg_handle_render_document(RsvgHandle *handle, cairo_t *cr, const RsvgRectangle *viewport, GError **error);
void g_error_free(GError *error);
void g_object_unref(void *object);
PangoContext *pango_cairo_create_context(cairo_t *cr);
PangoLayout *pango_cairo_create_layout(cairo_t *cr);
void pango_cairo_update_layout(cairo_t *cr, PangoLayout *layout);
void pango_cairo_show_layout(cairo_t *cr, PangoLayout *layout);
void pango_cairo_context_set_font_options(PangoContext *context, const cairo_font_options_t *options);
PangoAttrList *pango_attr_list_new(void);
void pango_attr_list_insert(PangoAttrList *list, PangoAttribute *attr);
void pango_attr_list_unref(PangoAttrList *list);
PangoAttribute *pango_attr_scale_new(double scale_factor);
PangoFontDescription *pango_font_description_from_string(const char *str);
void pango_font_description_free(PangoFontDescription *desc);
void pango_layout_set_text(PangoLayout *layout, const char *text, int length);
void pango_layout_set_font_description(PangoLayout *layout, const PangoFontDescription *desc);
void pango_layout_set_single_paragraph_mode(PangoLayout *layout, gboolean setting);
void pango_layout_set_attributes(PangoLayout *layout, PangoAttrList *attrs);
void pango_layout_get_pixel_size(PangoLayout *layout, int *width, int *height);
int pango_layout_get_baseline(PangoLayout *layout);
PangoContext *pango_layout_get_context(PangoLayout *layout);
