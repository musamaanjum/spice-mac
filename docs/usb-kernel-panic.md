# USB redirection kernel panic on macOS 26

## Evidence from the October 13, 2026 incident

The local report is
`/Library/Logs/DiagnosticReports/panic-full-2026-10-13-111725.0002.panic`.
It reports macOS 26.6.2, build 25G83, and a `Kernel data abort` with fault
address `0x0000000000000003`. The panicked task is SpiceMac, PID 2375, UID 0;
the panicked thread is its `SPICE Main Loop`, thread 314424. The faulting program
counter belongs to Apple's `com.apple.iokit.IOUSBHostFamily`, version 1.2.

Matching the report's image UUIDs to the installed binaries and symbolizing the
thread with `atos` gives this call chain:

```text
guest USB SET_INTERFACE message
spice_usb_backend_read_guest_data
usbredirparser_do_read
usbredirhost_set_alt_setting
darwin_set_interface_altsetting
get_endpoints
darwin_get_pipe_properties
IOUSBInterfaceClass::GetEndpointPropertiesV3
IOUSBHostFamily kernel data abort, fault address 0x3
```

The report's libusb UUID matches the checkout's bundled libusb 1.0.30. The
return address in `darwin_get_pipe_properties` is offset `0xf3bc`, immediately
after its second IOKit query, `GetEndpointPropertiesV3`. The IOUSBLib frame at
offset `0x5810` independently resolves to the same API. This is a kernel panic
while handling a guest USB request, rather than a userspace app crash or a
failure of the launcher to acquire root privileges. The earlier
`LIBUSB_ERROR_ACCESS` prevented capture before this path could be reached.

The panic alone does not identify the selected USB device or its descriptors.
The USB inventory contains a Plantronics headset, but inventory is not proof
that it was the device selected during the incident.

An upstream [libusb issue](https://github.com/libusb/libusb/issues/1762) reports
the same Tahoe driver and null-plus-three fault address with isochronous
endpoints. This is consistent with the local trace; it does not establish that
every device has the same trigger. The upstream issue was closed as an Apple
kernel issue, not as a confirmed libusb fix.

## Workaround in this checkout

`ThirdParty/libusb-tahoe-isochronous.patch` skips `GetEndpointPropertiesV3` for
isochronous pipes on macOS 26 and later. The preceding `GetPipePropertiesV3`
already supplies their endpoint address, type, and interval. In libusb 1.0.30,
isochronous I/O uses the interval for scheduling and does not consume the
returned packet size. Its packet sizes come from each submitted transfer.
Bulk and interrupt pipes retain the original uncooked packet-size query needed
by zero-length-packet handling. Earlier macOS and the legacy interface path
retain their existing behavior.

`scripts/upgrade-libusb.sh` applies the patch, tests the actual patched function
with mock IOKit calls, builds the library, and verifies that it exports every
libusb symbol imported by SPICE and usbredir before replacing the framework.
The framework's Info.plist records `SpiceMacTahoeIsochronousWorkaround = true`.
Rebuild the app after upgrading. Fetching a fresh sysroot replaces this generated
framework, so run the upgrade again afterward.

The checks cover isochronous IN/OUT endpoints, alternate settings 0/1, macOS
26/27, bulk/interrupt packet sizes, query failures, pre-Tahoe behavior, and the
legacy query path. They perform no device capture or physical USB I/O. They
verify removal of the implicated call for isochronous pipes; they cannot prove
that all other macOS USB operations are free of kernel bugs or that redirection
works on the affected hardware. Do not reproduce the unpatched panic to test it.

## Startup regression caught after the first workaround build

The reports `SpiceMac-2026-10-13-112457.ips` and
`SpiceMac-2026-10-13-112458.ips` show a userspace `SIGSEGV` at address zero in
`usbi_create_event`, before connecting to the VM. Disassembly identifies the call
as `pipe2()`. Xcode's selected SDK is macOS 27.0; the running macOS 26.6.2 has no
`pipe2` symbol. Autoconf accepted the SDK's weak import during its link check.
The original pipe-query unit checks and signature verification did not exercise
library initialization, so they did not detect this independent build regression.

The upgrade now forces `ac_cv_func_pipe2=no` to retain libusb's portable
`pipe()` plus `fcntl()` implementation throughout the macOS 11+ deployment range.
Before replacing the framework, `test-libusb-runtime.sh` rejects a `pipe2` import
and exercises three actual initialization/event-handling/shutdown cycles against
the newly built library. It does not claim interfaces, detach drivers, reset
devices, or redirect USB traffic. Repeat the check against the bundled framework
after assembling the app.

## Deferred reconnect issue

After successful capture, repeated disconnect/reconnect attempts can still
produce `darwin_abort_transfers` warnings followed by `LIBUSB_ERROR_ACCESS`,
even when SpiceMac runs as root. The proposed libusb interface-release and
state-restoration changes were withdrawn; this reconnect edge case remains
unfixed. The endpoint-query workaround and startup fix above remain in place.
