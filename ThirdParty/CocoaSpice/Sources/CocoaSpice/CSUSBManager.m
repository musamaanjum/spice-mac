//
// Copyright © 2021 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "CocoaSpice.h"
#import "CSUSBDevice+Protected.h"
#import <glib.h>
#import <spice-client.h>

typedef enum {
    kUsbManagerCallConnect,
    kUsbManagerCallDisconnect
} usbManagerCall;

typedef struct {
    usbManagerCall call;
    SpiceUsbDeviceManager *manager;
    SpiceUsbDevice *device;
    gpointer callback;
} usbManagerData;

static NSString *const kCSUSBManagerDomain = @"org.spice-space.usb";

@interface CSUSBManager ()

@property (nonatomic, readwrite, nonnull) SpiceUsbDeviceManager *usbDeviceManager;

@end

@implementation CSUSBManager

#pragma mark - Signal callbacks

static NSError *errorWithGError(GError *error) {
    NSString *description = [NSString stringWithUTF8String:error->message];
    NSString *domain = [NSString stringWithUTF8String:g_quark_to_string(error->domain) ?: "unknown"];
    return [NSError errorWithDomain:kCSUSBManagerDomain code:error->code
                          userInfo:@{NSLocalizedDescriptionKey: description, @"GLibErrorDomain": domain}];
}

static void logDeviceEvent(CSUSBManager *manager, NSString *event, CSUSBDevice *device, GError *error) {
    NSString *detail = error ? [NSString stringWithFormat:@" error-domain=%s error-code=%d message=%s",
                               g_quark_to_string(error->domain) ?: "unknown", error->code, error->message] : @"";
    [CSMain.sharedInstance spiceLog:[NSString stringWithFormat:@"USB %@ manager=%p free-channels=%ld %@%@",
                                    event, manager.usbDeviceManager, (long)manager.numberFreeChannels,
                                    device.diagnosticDescription, detail]];
}

static void cs_device_error(SpiceUsbDeviceManager *manager,
                            SpiceUsbDevice        *device,
                            GError                *error,
                            gpointer               data)
{
    CSUSBManager *self = (__bridge CSUSBManager *)data;
    CSUSBDevice *usbdevice = [CSUSBDevice usbDeviceWithDevice:device manager:manager];
    logDeviceEvent(self, @"device-error", usbdevice, error);
    if (error->domain == G_IO_ERROR && error->code == G_IO_ERROR_CANCELLED)
        return;
    
    [self.delegate spiceUsbManager:self deviceError:[NSString stringWithUTF8String:error->message] forDevice:usbdevice];
}

static void cs_auto_connect_failed(SpiceUsbDeviceManager *manager, SpiceUsbDevice *device, GError *error, gpointer data) {
    CSUSBManager *self = (__bridge CSUSBManager *)data;
    logDeviceEvent(self, @"auto-connect-failed", [CSUSBDevice usbDeviceWithDevice:device manager:manager], error);
    cs_device_error(manager, device, error, data);
}

static void cs_free_channels_changed(GObject *object, GParamSpec *property, gpointer data) {
    CSUSBManager *self = (__bridge CSUSBManager *)data;
    [CSMain.sharedInstance spiceLog:[NSString stringWithFormat:@"USB channel-availability manager=%p free-channels=%ld",
                                    object, (long)self.numberFreeChannels]];
}

static void cs_device_added(SpiceUsbDeviceManager *manager,
    SpiceUsbDevice *device, gpointer data)
{
    CSUSBManager *self = (__bridge CSUSBManager *)data;
    CSUSBDevice *usbdevice = [CSUSBDevice usbDeviceWithDevice:device manager:manager];
    logDeviceEvent(self, @"device-added", usbdevice, NULL);
    [self.delegate spiceUsbManager:self deviceAttached:usbdevice];
}

static void cs_device_removed(SpiceUsbDeviceManager *manager,
    SpiceUsbDevice *device, gpointer data)
{
    CSUSBManager *self = (__bridge CSUSBManager *)data;
    CSUSBDevice *usbdevice = [CSUSBDevice usbDeviceWithDevice:device manager:manager];
    logDeviceEvent(self, @"device-removed", usbdevice, NULL);
    [self.delegate spiceUsbManager:self deviceRemoved:usbdevice];
}

static void cs_connect_cb(GObject *gobject, GAsyncResult *res, gpointer data)
{
    SpiceUsbDeviceManager *manager = SPICE_USB_DEVICE_MANAGER(gobject);
    CSUSBManagerConnectionCallback callback = (__bridge_transfer CSUSBManagerConnectionCallback)(data);
    GError *err = NULL;

    spice_usb_device_manager_connect_device_finish(manager, res, &err);
    if (err) {
        callback(errorWithGError(err));
        g_error_free(err);
    } else {
        callback(nil);
    }
}

static void cs_disconnect_cb(GObject *gobject, GAsyncResult *res, gpointer data)
{
    SpiceUsbDeviceManager *manager = SPICE_USB_DEVICE_MANAGER(gobject);
    CSUSBManagerConnectionCallback callback = (__bridge_transfer CSUSBManagerConnectionCallback)(data);
    GError *err = NULL;

    spice_usb_device_manager_disconnect_device_finish(manager, res, &err);
    if (err) {
        callback(errorWithGError(err));
        g_error_free(err);
    } else {
        callback(nil);
    }
}

static gboolean cs_call_manager(gpointer user_data)
{
    usbManagerData *data = (usbManagerData *)user_data;
    switch (data->call) {
        case kUsbManagerCallConnect:
            spice_usb_device_manager_connect_device_async(data->manager, data->device, NULL, cs_connect_cb, data->callback);
            break;
        case kUsbManagerCallDisconnect:
            spice_usb_device_manager_disconnect_device_async(data->manager, data->device, NULL, cs_disconnect_cb, data->callback);
            break;
        default:
            g_assert(0);
    }
    return G_SOURCE_REMOVE;
}

#pragma mark - Properties

- (BOOL)isAutoConnect {
    gboolean value;
    g_object_get(self.usbDeviceManager, "auto-connect", &value, NULL);
    return value;
}

- (void)setIsAutoConnect:(BOOL)isAutoConnect {
    g_object_set(self.usbDeviceManager, "auto-connect", isAutoConnect, NULL);
}

- (NSString *)autoConnectFilter {
    gchar *string;
    g_object_get(self.usbDeviceManager, "auto-connect-filter", &string, NULL);
    NSString *nsstring = [NSString stringWithUTF8String:string];
    g_free(string);
    return nsstring;
}

- (void)setAutoConnectFilter:(NSString *)autoConnectFilter {
    const gchar *string = [autoConnectFilter UTF8String];
    g_object_set(self.usbDeviceManager, "auto-connect-filter", string, NULL);
}

- (BOOL)isRedirectOnConnect {
    gboolean value;
    g_object_get(self.usbDeviceManager, "redirect-on-connect", &value, NULL);
    return value;
}

- (void)setIsRedirectOnConnect:(BOOL)isRedirectOnConnect {
    g_object_set(self.usbDeviceManager, "redirect-on-connect", isRedirectOnConnect, NULL);
}

- (NSInteger)numberFreeChannels {
    gint value;
    g_object_get(self.usbDeviceManager, "free-channels", &value, NULL);
    return value;
}

- (NSArray<CSUSBDevice *> *)usbDevices {
    NSMutableArray<CSUSBDevice *> *usbDevices = [NSMutableArray new];
    GPtrArray *arr = spice_usb_device_manager_get_devices(self.usbDeviceManager);
    if (arr != NULL) {
        for (int i = 0; i < arr->len; i++) {
            SpiceUsbDevice *device = g_ptr_array_index(arr, i);
            [usbDevices addObject:[CSUSBDevice usbDeviceWithDevice:device manager:self.usbDeviceManager]];
        }
        g_ptr_array_unref(arr);
    }
    return usbDevices;
}

- (BOOL)isBusy {
    return spice_usb_device_manager_is_redirecting(self.usbDeviceManager);
}

#pragma mark - Construction

- (instancetype)initWithUsbDeviceManager:(SpiceUsbDeviceManager *)usbDeviceManager {
    if (self = [super init]) {
        self.usbDeviceManager = g_object_ref(usbDeviceManager);
        g_signal_connect(usbDeviceManager, "auto-connect-failed",
                         G_CALLBACK(cs_auto_connect_failed), (__bridge void *)self);
        g_signal_connect(usbDeviceManager, "device-error",
                         G_CALLBACK(cs_device_error), (__bridge void *)self);
        g_signal_connect(usbDeviceManager, "device-added",
                         G_CALLBACK(cs_device_added), (__bridge void *)self);
        g_signal_connect(usbDeviceManager, "device-removed",
                         G_CALLBACK(cs_device_removed), (__bridge void *)self);
        g_signal_connect(usbDeviceManager, "notify::free-channels",
                         G_CALLBACK(cs_free_channels_changed), (__bridge void *)self);
        [CSMain.sharedInstance spiceLog:[NSString stringWithFormat:@"USB manager-created manager=%p free-channels=%ld",
                                        usbDeviceManager, (long)self.numberFreeChannels]];
        for (CSUSBDevice *device in self.usbDevices) {
            logDeviceEvent(self, @"device-present", device, NULL);
        }
    }
    return self;
}

- (void)dealloc {
    SpiceUsbDeviceManager *usbDeviceManager = self.usbDeviceManager;
    gpointer data = (__bridge void *)self;
    [CSMain.sharedInstance syncWith:^{
        [CSMain.sharedInstance spiceLog:[NSString stringWithFormat:@"USB manager-destroyed manager=%p", usbDeviceManager]];
        g_signal_handlers_disconnect_by_func(usbDeviceManager, G_CALLBACK(cs_auto_connect_failed), data);
        g_signal_handlers_disconnect_by_func(usbDeviceManager, G_CALLBACK(cs_device_error), data);
        g_signal_handlers_disconnect_by_func(usbDeviceManager, G_CALLBACK(cs_device_added), data);
        g_signal_handlers_disconnect_by_func(usbDeviceManager, G_CALLBACK(cs_device_removed), data);
        g_signal_handlers_disconnect_by_func(usbDeviceManager, G_CALLBACK(cs_free_channels_changed), data);
        g_object_unref(usbDeviceManager);
    }];
}

#pragma mark - Methods

- (BOOL)canRedirectUsbDevice:(CSUSBDevice *)usbDevice errorMessage:(NSString * _Nullable __autoreleasing *)errorMessage {
    GError *err = NULL;
    gboolean res = spice_usb_device_manager_can_redirect_device(self.usbDeviceManager, usbDevice.device, &err);
    logDeviceEvent(self, res ? @"redirect-check-ok" : @"redirect-check-failed", usbDevice, err);
    if (errorMessage && err) {
        *errorMessage = [NSString stringWithUTF8String:err->message];
    }
    g_clear_error(&err);
    return res;
}

- (BOOL)isUsbDeviceConnected:(CSUSBDevice *)usbDevice {
    return spice_usb_device_manager_is_device_connected(self.usbDeviceManager, usbDevice.device);
}

- (void)spiceUsbManagerCall:(usbManagerCall)call forUsbDevice:(CSUSBDevice *)usbDevice withCompletion:(CSUSBManagerConnectionCallback)completion {
    NSString *operation = call == kUsbManagerCallConnect ? @"connect" : @"disconnect";
    NSString *attempt = NSUUID.UUID.UUIDString;
    NSString *identity = usbDevice.diagnosticDescription;
    logDeviceEvent(self, [NSString stringWithFormat:@"%@-requested attempt=%@", operation, attempt], usbDevice, NULL);
    CSUSBManagerConnectionCallback loggedCompletion = ^(NSError *error) {
        [CSMain.sharedInstance spiceLog:[NSString stringWithFormat:@"USB %@-%@ attempt=%@ manager=%p free-channels=%ld %@ error-domain=%@ error-code=%ld glib-domain=%@ message=%@",
                                        operation, error ? @"failed" : @"succeeded", attempt,
                                        self.usbDeviceManager, (long)self.numberFreeChannels, identity,
                                        error.domain ?: @"none", (long)error.code, error.userInfo[@"GLibErrorDomain"] ?: @"none",
                                        error.localizedDescription ?: @"none"]];
        completion(error);
    };
    usbManagerData *data = g_new0(usbManagerData, 1);
    data->call = call;
    data->manager = self.usbDeviceManager;
    data->device = usbDevice.device;
    data->callback = (__bridge_retained gpointer)[loggedCompletion copy];
    g_main_context_invoke_full([CSMain sharedInstance].glibMainContext,
                               G_PRIORITY_HIGH,
                               cs_call_manager,
                               data,
                               g_free);
}

- (void)connectUsbDevice:(CSUSBDevice *)usbDevice withCompletion:(CSUSBManagerConnectionCallback)completion {
    [self spiceUsbManagerCall:kUsbManagerCallConnect forUsbDevice:usbDevice withCompletion:completion];
}

- (void)disconnectUsbDevice:(CSUSBDevice *)usbDevice withCompletion:(CSUSBManagerConnectionCallback)completion {
    [self spiceUsbManagerCall:kUsbManagerCallDisconnect forUsbDevice:usbDevice withCompletion:completion];
}

@end
