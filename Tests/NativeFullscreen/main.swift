// SPDX-License-Identifier: MIT
// Exercise native fullscreen animations, including AppKit's delayed settings reset.
import AppKit

final class FullscreenCheck: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let presentation = HostPresentationController()
    var captured = true
    var cycles = 0
    var checks = 0
    var failed = false

    func stop() {
        NSApp.stop(nil)
        // Wake nextEvent so stopping from a dispatch timer exits the app loop.
        NSApp.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0)!, atStart: true)
    }

    func check(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            failed = true
            presentation.endFullScreen(owner: self)
            stop()
            return
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.title = "SpiceMac fullscreen regression check"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.window.toggleFullScreen(nil) }
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposed: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        presentation.fullScreenOptions(owner: self, proposedOptions: proposed,
                                       hideChrome: true)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        presentation.update(owner: self, hideChrome: true, captureKeyboard: captured)
        // didEnter alone passes with the old implementation. Wait for AppKit to
        // finish applying its fullscreen presentation before checking the system.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.check(self.presentation.shortcutCapture.currentMode == 1,
                       "capture must survive native fullscreen entry, cycle \(self.cycles + 1)")
            guard !self.failed else { return }
            // Losing focus and regaining it must retain the native baseline,
            // rather than remembering our own captured settings as the baseline.
            self.presentation.restore(owner: self)
            self.check(self.presentation.shortcutCapture.currentMode == 0,
                       "focus loss releases app switching")
            self.presentation.update(owner: self, hideChrome: true, captureKeyboard: true)
            self.check(self.presentation.shortcutCapture.currentMode == 1,
                       "refocus captures keyboard")
            self.captured = false
            self.presentation.update(owner: self, hideChrome: true, captureKeyboard: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.check(self.presentation.shortcutCapture.currentMode == 0,
                           "explicit release must stay released after native fullscreen updates")
                guard !self.failed else { return }
                self.window.toggleFullScreen(nil)
            }
        }
    }

    func windowWillExitFullScreen(_ notification: Notification) { presentation.restore(owner: self) }
    func windowDidExitFullScreen(_ notification: Notification) {
        presentation.endFullScreen(owner: self)
        check(presentation.shortcutCapture.currentMode == 0,
              "fullscreen exit restores app switching")
        cycles += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.cycles < 2 {
                self.captured = true
                self.window.toggleFullScreen(nil)
            } else {
                self.stop()
            }
        }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) { check(false, "native fullscreen entry failed") }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { check(false, "native fullscreen exit failed") }
}

let app = NSApplication.shared
let previousApp = NSWorkspace.shared.frontmostApplication
app.setActivationPolicy(.regular)
let fullscreenCheck = FullscreenCheck()
app.delegate = fullscreenCheck
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fullscreenCheck.check(false, "native fullscreen check timed out") }
app.run()
fullscreenCheck.presentation.endFullScreen(owner: fullscreenCheck)
fullscreenCheck.window.orderOut(nil)
previousApp?.activate(options: [])
if fullscreenCheck.failed { exit(1) }
print("native fullscreen: \(fullscreenCheck.checks) checks passed across \(fullscreenCheck.cycles) cycles")
