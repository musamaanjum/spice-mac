# Agent Notes

## Google/AOSP USB redirection on macOS

Google/AOSP phones may fail to redirect through SpiceMac even though simpler USB devices, such as cameras, work. The same phone also failed with UTM but worked with Parallels Desktop.

Observed symptoms:

- macOS/libusb reports `USBDeviceClose: no connection to an IOService` and control-transfer failures such as `0xe00002d8`.
- The Linux guest reports `device not responding to setup address` followed by `hub failed to enable device, error -71`.
- The tested Google device re-enumerated from USB ID `18d1:4ee0` to `18d1:4ee7` while remaining on the same physical USB location.
- Parallels logs reported `PRL_ERR_DEV_USB_CHANGEPID` and retained/reconnected the device after its PID changed.

Current diagnosis:

- This is not primarily a Q35 setting, SPICE-port-count, USB 2/3, or outdated-libusb problem.
- UTM and SpiceMac use libusb/usbredir and lose the device when Android re-enumerates. A macOS device-access entitlement is necessary for capture but is not sufficient; UTM has the entitlement and still fails.
- Parallels succeeds using proprietary macOS USB handling that tracks/reserves the physical port and reconnects the replacement USB device after a PID change.

Likely implementation direction:

1. Identify a selected device by stable physical USB location and serial number instead of retaining only its libusb device instance or PID.
2. On removal, `NO_DEVICE`, `NotReady`, or `NotAttached` during capture, retain the intended redirection/channel assignment temporarily.
3. Watch for a replacement device at the same physical location or with the same serial, allowing its PID to change.
4. Reopen, authorize, claim, and reconnect that replacement device through usbredir. If seamless replacement is unsupported by the protocol, perform a controlled disconnect/reconnect on the same SPICE USB channel.

Possible workaround: let the phone finish switching into its final USB mode before selecting it in SpiceMac. Otherwise use Parallels, wireless ADB, or attach the phone directly to the Proxmox host.
