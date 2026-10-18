// SPDX-License-Identifier: MIT
// Compile the actual callbacks and inject messages without a session or device.
#import "../../ThirdParty/CocoaSpice/Sources/CocoaSpice/CSMain.m"

// No SPICE worker or audio capture is started by this check.
void gst_ios_init(void) { abort(); }

int main(void) {
    @autoreleasepool {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        CSMain *main = CSMain.sharedInstance;
        main.logHandler = ^(NSString *line) { [lines addObject:line]; };
        setenv("LIBUSB_DEBUG", "4", 1);
        [main spiceEnableUSBDiagnostics];
        if (strcmp(getenv("LIBUSB_DEBUG"), "4") != 0) return 1;
        [main spiceLog:@"USB connect-failed attempt=synthetic error-code=4"];
        g_log("USB-test", G_LOG_LEVEL_WARNING, "%s", "injected GLib error");
        usbLogHandler(NULL, LIBUSB_LOG_LEVEL_ERROR, "injected NO_DEVICE error");
        BOOL sawUSB = NO, sawGLib = NO, sawLibusb = NO;
        for (NSString *line in lines) {
            sawUSB |= [line containsString:@"connect-failed attempt=synthetic"];
            sawGLib |= [line containsString:@"WARNING USB-test-injected GLib error"];
            sawLibusb |= [line containsString:@"libusb level=1"] && [line containsString:@"NO_DEVICE"];
        }
        if (!sawUSB || !sawGLib || !sawLibusb) {
            fprintf(stderr, "Native diagnostics failed: %s\n", lines.description.UTF8String);
            return 1;
        }
        puts("Passed native USB, GLib, and libusb log callback checks; no session or device capture.");
        return 0;
    }
}
