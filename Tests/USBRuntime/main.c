#include <dlfcn.h>
#include <libusb.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    int (*initialize)(libusb_context **) = dlsym(library, "libusb_init");
    void (*shutdown)(libusb_context *) = dlsym(library, "libusb_exit");
    int (*handle_events)(libusb_context *, struct timeval *, int *) =
        dlsym(library, "libusb_handle_events_timeout_completed");
    if (!initialize || !shutdown || !handle_events) {
        fprintf(stderr, "Missing libusb runtime entry points\n");
        dlclose(library);
        return 1;
    }
    for (int i = 0; i < 3; ++i) {
        libusb_context *context = NULL;
        int result = initialize(&context);
        if (result || !context) {
            fprintf(stderr, "libusb_init failed: %d\n", result);
            dlclose(library);
            return 1;
        }
        struct timeval timeout = {0, 0};
        result = handle_events(context, &timeout, NULL);
        shutdown(context);
        if (result) {
            fprintf(stderr, "libusb event handling failed: %d\n", result);
            dlclose(library);
            return 1;
        }
    }
    dlclose(library);
    puts("Passed 3 actual libusb initialization, event handling, and shutdown cycles; no device capture.");
    return 0;
}
