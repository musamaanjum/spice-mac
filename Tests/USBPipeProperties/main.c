// Exercise the real libusb Darwin pipe query without entering the USB kernel.
#include <IOKit/usb/IOUSBLib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_INTERFACE_VERSION 550
#define IOINTERFACE(i) ((i)->interface)
#define IOINTERFACE_V(i, version) ((IOUSBInterfaceInterface##version **)(i)->interface)
struct darwin_interface { IOUSBInterfaceInterface550 **interface; };
static uint32_t os_version = 260602, interface_version = 550;
static uint32_t __attribute__((unused)) get_running_version(void) { return os_version; }
static uint32_t get_interface_interface_version(void) { return interface_version; }
#include "pipe-query-under-test.inc"

static int pipe_calls, endpoint_calls, checks;
static IOReturn pipe_error, endpoint_error, alternate_error;
static UInt8 transfer_type = kUSBIsoc, direction = kUSBIn, alternate = 1;
static UInt16 cooked_size = 3072, raw_size = 1024;

#define CHECK(condition) do { \
  if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); exit(1); } \
  ++checks; \
} while (0)

static IOReturn pipe_v3(void *self, UInt8 pipe, IOUSBEndpointProperties *p) {
  (void)self;
  CHECK(pipe == 1 && p->bVersion == kUSBEndpointPropertiesVersion3);
  ++pipe_calls;
  if (pipe_error) return pipe_error;
  p->bAlternateSetting = alternate;
  p->bEndpointNumber = 3;
  p->bDirection = direction;
  p->bTransferType = transfer_type;
  p->wMaxPacketSize = cooked_size;
  p->bInterval = 4;
  return kIOReturnSuccess;
}

static IOReturn endpoint_v3(void *self, IOUSBEndpointProperties *p) {
  (void)self;
  ++endpoint_calls;
  CHECK(p->bAlternateSetting == alternate && p->bEndpointNumber == 3);
  CHECK(p->bDirection == direction);
  if (endpoint_error) return endpoint_error;
  p->wMaxPacketSize = raw_size;
  return kIOReturnSuccess;
}

static IOReturn pipe_legacy(void *self, UInt8 pipe, UInt8 *dir, UInt8 *number,
                           UInt8 *type, UInt16 *size, UInt8 *interval) {
  (void)self;
  CHECK(pipe == 1);
  ++pipe_calls;
  if (pipe_error) return pipe_error;
  *dir = direction; *number = 3; *type = transfer_type;
  *size = cooked_size; *interval = 4;
  return kIOReturnSuccess;
}

static IOReturn get_alternate(void *self, UInt8 *value) {
  (void)self;
  *value = alternate;
  return alternate_error;
}

static IOReturn endpoint_legacy(void *self, UInt8 alt, UInt8 number, UInt8 dir,
                               UInt8 *type, UInt16 *size, UInt8 *interval) {
  (void)self; (void)type; (void)interval;
  ++endpoint_calls;
  CHECK(alt == alternate && number == 3 && dir == direction);
  if (endpoint_error) return endpoint_error;
  *size = raw_size;
  return kIOReturnSuccess;
}

static void reset(void) {
  pipe_calls = endpoint_calls = 0;
  pipe_error = endpoint_error = alternate_error = kIOReturnSuccess;
}

int main(void) {
  IOUSBInterfaceInterface550 api = {
    .GetPipePropertiesV3 = pipe_v3, .GetEndpointPropertiesV3 = endpoint_v3,
    .GetPipeProperties = pipe_legacy, .GetAlternateSetting = get_alternate,
    .GetEndpointProperties = endpoint_legacy,
  };
  IOUSBInterfaceInterface550 *pointer = &api;
  struct darwin_interface interface = { .interface = &pointer };
  darwin_pipe_properties_t out;

  // The crashing kernel query must never run on Tahoe isochronous IN or OUT,
  // including default/nondefault alternate settings and later macOS versions.
  for (unsigned version = 260000; version <= 270000; version += 10000) {
    os_version = version;
    for (unsigned alt = 0; alt <= 1; ++alt) {
      alternate = alt;
      for (unsigned dir = kUSBOut; dir <= kUSBIn; ++dir) {
        reset(); direction = dir; transfer_type = kUSBIsoc;
        // An error sentinel verifies that the second query is genuinely skipped.
        endpoint_error = kIOReturnUnsupported;
        CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnSuccess);
        CHECK(pipe_calls == 1 && endpoint_calls == 0);
        CHECK(out.number == 3 && out.direction == dir && out.transfer_type == kUSBIsoc);
        CHECK(out.interval == 4 && out.max_packet_size == cooked_size);
      }
    }
  }

  os_version = 260602; alternate = 1; direction = kUSBIn;
  for (unsigned type = kUSBBulk; type <= kUSBInterrupt; ++type) {
    reset(); transfer_type = type;
    CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnSuccess);
    CHECK(pipe_calls == 1 && endpoint_calls == 1);
    CHECK(out.max_packet_size == raw_size && out.transfer_type == type);
    reset(); endpoint_error = kIOReturnNoDevice;
    CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnNoDevice);
  }

  reset(); pipe_error = kIOReturnNoDevice;
  CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnNoDevice);
  CHECK(endpoint_calls == 0);

  reset(); os_version = 150000; transfer_type = kUSBIsoc;
  CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnSuccess);
  CHECK(endpoint_calls == 1 && out.max_packet_size == raw_size);

  reset(); interface_version = 245;
  CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnSuccess);
  CHECK(endpoint_calls == 1 && out.max_packet_size == raw_size && out.interval == 4);
  reset(); alternate_error = kIOReturnNoDevice;
  CHECK(darwin_get_pipe_properties(&interface, 1, &out) == kIOReturnNoDevice);
  CHECK(endpoint_calls == 0);

  printf("Passed %d USB pipe-query checks without accessing hardware.\n", checks);
  return 0;
}
