#include "app.h"
#include <stdlib.h>

int main(int argc, char *argv[]) {
	struct wsk_app *app = NULL;
	if (!wsk_app_init_privileged(&app)) {
		return 1;
	}

	if (!wsk_app_init(app, argc, argv)) {
		wsk_app_finish(app);
		return 1;
	}

	int ret = wsk_app_run(app);
	wsk_app_finish(app);
	return ret;
}
