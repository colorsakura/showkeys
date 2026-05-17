#ifndef SHOWKEYS_RENDER_H
#define SHOWKEYS_RENDER_H

struct wsk_app;

void wsk_render_frame(struct wsk_app *app);
void wsk_render_set_dirty(struct wsk_app *app);

#endif
