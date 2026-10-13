// SPDX-License-Identifier: MIT
// AppKit regression checks; no SPICE server or Accessibility permission needed.
import AppKit
import Carbon

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

final class HostView: NSView {
    var events: [NSEvent] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { events.append(event) }
    override func keyUp(with event: NSEvent) { events.append(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        events.append(event)
        return true
    }
}

let app = NSApplication.shared
let previousApp = NSWorkspace.shared.frontmostApplication
app.setActivationPolicy(.accessory)
app.finishLaunching()
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                      styleMask: [.titled], backing: .buffered, defer: false)
let host = HostView()
window.contentView = host
window.makeFirstResponder(host)
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
let activationDeadline = Date(timeIntervalSinceNow: 0.5)
while let next = app.nextEvent(matching: .any, until: activationDeadline, inMode: .default, dequeue: true) {
    app.sendEvent(next)
    if Date() >= activationDeadline { break }
}
defer {
    window.orderOut(nil)
    previousApp?.activate(options: [])
}
check(window.isKeyWindow, "AppKit test window must receive uncaptured key events (active=\(app.isActive), visible=\(window.isVisible), canBecomeKey=\(window.canBecomeKey))")
var focused = true
var fullScreen = true
var guestEvents: [NSEvent] = []
var releases = 0
var monitor: GuestKeyboardMonitor? = GuestKeyboardMonitor(
    isGuestFocused: { _ in focused },
    isFullScreen: { fullScreen },
    keyDown: { guestEvents.append($0) },
    keyUp: { guestEvents.append($0) },
    release: { releases += 1; focused = false })

func event(_ type: NSEvent.EventType, key: Int = kVK_Tab,
           flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: key == kVK_Tab ? "\t" : "r",
                    charactersIgnoringModifiers: key == kVK_Tab ? "\t" : "r",
                    isARepeat: repeatKey, keyCode: UInt16(key))!
}

// Dispatch through NSApplication, so these checks exercise the installed local
// monitor and prove AppKit's host handlers never see the captured Tab events.
for flags: NSEvent.ModifierFlags in [[], .shift, .control, [.control, .shift], .command, [.command, .shift], .option] {
    guestEvents.removeAll()
    host.events.removeAll()
    app.sendEvent(event(.keyDown, flags: flags))
    app.sendEvent(event(.keyUp, flags: flags))
    check(guestEvents.map(\.type) == [.keyDown, .keyUp], "Tab chord must reach guest as one press/release: \(flags)")
    check(guestEvents.allSatisfy { $0.modifierFlags == flags }, "preserve Tab modifiers")
    check(host.events.isEmpty, "captured Tab must not reach host navigation")
}

fullScreen = false
guestEvents.removeAll()
host.events.removeAll()
app.sendEvent(event(.keyDown, flags: .control))
app.sendEvent(event(.keyUp, flags: .control))
check(guestEvents.isEmpty && !host.events.isEmpty, "windowed Ctrl+Tab must remain with macOS")
check(GuestKeyboardPolicy.routesTabToHost(event(.keyDown, flags: .control), isFullScreen: false), "windowed responder must leave Ctrl+Tab to the host")
check(!GuestKeyboardPolicy.routesTabToHost(event(.keyDown, flags: .control), isFullScreen: true), "fullscreen responder must deliver Ctrl+Tab to the guest")
check(!GuestKeyboardPolicy.routesTabToHost(event(.keyDown), isFullScreen: false), "ordinary windowed Tab remains a guest key")
fullScreen = true

guestEvents.removeAll()
app.sendEvent(event(.keyDown, flags: .control))
app.sendEvent(event(.keyUp))
check(guestEvents.count == 2 && guestEvents.last?.type == .keyUp, "release Tab even when Control was released first")

guestEvents.removeAll()
app.sendEvent(event(.keyDown, flags: .control, repeatKey: true))
check(guestEvents.count == 1 && guestEvents[0].isARepeat, "preserve repeat metadata for the input router")

guestEvents.removeAll()
host.events.removeAll()
app.sendEvent(event(.keyDown, key: kVK_ANSI_R, flags: [.control, .option]))
check(releases == 1 && !focused, "Control-Option-R releases guest focus")
check(guestEvents.isEmpty && host.events.isEmpty, "release shortcut must not be typed in guest or host")

app.sendEvent(event(.keyDown))
check(guestEvents.isEmpty && !host.events.isEmpty, "released keyboard must allow host shortcuts")
focused = true
guestEvents.removeAll()
app.sendEvent(event(.keyDown, flags: .control))
check(guestEvents.count == 1, "refocusing guest resumes capture")

host.events.removeAll()
guestEvents.removeAll()
app.sendEvent(event(.keyDown, key: kVK_ANSI_R, flags: [.command, .control, .option]))
check(releases == 1 && guestEvents.isEmpty && !host.events.isEmpty, "unrelated shortcuts must retain normal AppKit routing")

monitor = nil
host.events.removeAll()
app.sendEvent(event(.keyDown))
check(!host.events.isEmpty, "destroying capture removes the local monitor")

// Capture must not depend on Dock hiding or the process-switcher UI option.
let original = app.presentationOptions
defer { app.presentationOptions = original }
for base: NSApplication.PresentationOptions in [[], [.autoHideDock, .autoHideMenuBar], [.hideDock, .hideMenuBar], [.fullScreen, .autoHideDock, .autoHideMenuBar]] {
    for hideChrome in [false, true] {
        let options = HostPresentationController.options(base, hideChrome: hideChrome)
        check(options.contains(.fullScreen) == base.contains(.fullScreen), "fullscreen mode is owned by AppKit")
        app.presentationOptions = options
        check(!options.contains(.disableProcessSwitching), "presentation must not swallow process-switching events")
        if hideChrome {
            check(options.contains([.hideDock, .hideMenuBar]), "fullscreen chrome stays hidden")
            check(options.intersection([.autoHideDock, .autoHideMenuBar]).isEmpty, "hide flags must not conflict with auto-hide")
        }
    }
}

app.presentationOptions = []
let presentation = HostPresentationController()
let firstSession = NSObject()
let secondSession = NSObject()
presentation.update(owner: firstSession, hideChrome: true, captureKeyboard: true)
check(presentation.shortcutCapture.currentMode == 1, "fullscreen capture must disable WindowServer shortcut interception")
presentation.update(owner: firstSession, hideChrome: true, captureKeyboard: false)
check(presentation.shortcutCapture.currentMode == 0, "release must restore WindowServer shortcuts while remaining fullscreen")
check(app.presentationOptions.contains(.hideMenuBar), "keyboard release preserves chrome preference")
presentation.update(owner: firstSession, hideChrome: false, captureKeyboard: true)
check(!app.presentationOptions.contains(.hideMenuBar), "chrome preference does not disable keyboard capture")
presentation.update(owner: secondSession, hideChrome: true, captureKeyboard: true)
presentation.restore(owner: firstSession)
check(presentation.shortcutCapture.currentMode == 1, "background session must not release active session capture")
presentation.restore(owner: secondSession)
check(app.presentationOptions.isEmpty, "switching sessions must not inherit previous capture as baseline")
check(presentation.shortcutCapture.currentMode == 0, "ending capture restores the original hotkey mode")

presentation.update(owner: firstSession, hideChrome: false, captureKeyboard: true)
app.presentationOptions.insert(.disableHideApplication)
presentation.restore(owner: firstSession)
check(app.presentationOptions == [.disableHideApplication], "release must preserve unmanaged presentation changes")
app.presentationOptions = [.disableHideApplication, .autoHideDock, .autoHideMenuBar]
presentation.update(owner: firstSession, hideChrome: true, captureKeyboard: true)
app.presentationOptions.remove(.disableHideApplication)
presentation.restore(owner: firstSession)
check(!app.presentationOptions.contains(.disableHideApplication), "release must not restore stale unmanaged presentation bits")
check(presentation.shortcutCapture.currentMode == 0, "fullscreen exit restores system hotkey handling")

app.presentationOptions = []
let nativeProposal: NSApplication.PresentationOptions = [.fullScreen, .autoHideDock, .autoHideMenuBar]
let capturedProposal = presentation.fullScreenOptions(owner: firstSession, proposedOptions: nativeProposal,
                                                      hideChrome: true)
app.presentationOptions = capturedProposal
presentation.restore(owner: firstSession, useWindowedOptions: true)
check(app.presentationOptions.intersection([.hideDock, .autoHideDock, .hideMenuBar, .autoHideMenuBar, .disableProcessSwitching]).isEmpty,
      "an invisible/minimized fullscreen window must not hide Dock or capture macOS")
// Native fullscreen can reapply its cached proposal on Dock activation. Release
// it even when focus loss already relinquished the presentation owner.
app.presentationOptions = capturedProposal
presentation.restore(owner: firstSession, useWindowedOptions: true)
check(app.presentationOptions.intersection([.hideDock, .hideMenuBar, .disableProcessSwitching]).isEmpty,
      "Dock activation must clear cached capture before the VM is visible")
presentation.update(owner: firstSession, hideChrome: true, captureKeyboard: true)
check(presentation.shortcutCapture.currentMode == 1, "visible fullscreen guest may capture again")
presentation.endFullScreen(owner: firstSession)
check(app.presentationOptions.intersection([.hideDock, .autoHideDock, .hideMenuBar, .autoHideMenuBar, .disableProcessSwitching]).isEmpty,
      "ending fullscreen must restore windowed Dock and menu settings")
print("keyboard capture: \(checks) checks passed")
