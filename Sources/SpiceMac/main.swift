// SPDX-License-Identifier: MIT
import AppKit

// SwiftPM executable entry point for an AppKit app (no storyboard/nib).
GuestKeyboardTrace.start()
USBDiagnostics.start()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
