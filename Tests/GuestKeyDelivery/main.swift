// SPDX-License-Identifier: MIT
import AppKit
import CocoaSpice
import SpiceInputMap

var checks = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func event(_ type: NSEvent.EventType, key: UInt16 = MacVirtualKey.tab,
           flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "\t",
                    charactersIgnoringModifiers: "\t", isARepeat: repeatKey, keyCode: key)!
}
let input = CSInput()
let router = SpiceInputRouter(input: input)
func reset() { router.releaseAll(); input.keys.removeAll() }
let ctrl: Int32 = 0x1D
let tab: Int32 = 0x0F
let shift: Int32 = 0x2A

let app = NSApplication.shared
let monitor = GuestKeyboardMonitor(isGuestFocused: { _ in true },
    isFullScreen: { true },
    keyDown: { router.keyDown($0) }, keyUp: { router.keyUp($0) }, release: { router.releaseAll() })
app.sendEvent(event(.keyDown, flags: .control))
app.sendEvent(event(.keyUp, flags: .control))
router.flagsChanged(event(.flagsChanged, key: MacVirtualKey.control))
check(input.keys == [.init(.press, ctrl), .init(.press, tab), .init(.release, tab), .init(.release, ctrl)],
      "captured AppKit shortcut must reach guest transport as Ctrl+Tab, without remapping")
reset()

// This failed before the fix: the monitor forwarded a flagged Ctrl+Tab NSEvent,
// but the router sent bare Tab when the modifier transition was missed.
router.keyDown(event(.keyDown, flags: .control))
check(input.keys == [.init(.press, ctrl), .init(.press, tab)], "Ctrl must be pressed before captured Tab")
router.keyUp(event(.keyUp, flags: .control))
router.flagsChanged(event(.flagsChanged, key: MacVirtualKey.control))
check(input.keys == [.init(.press, ctrl), .init(.press, tab), .init(.release, tab), .init(.release, ctrl)],
      "Ctrl+Tab must reach CSInput with balanced, unmodified guest scancodes")

reset()
router.flagsChanged(event(.flagsChanged, key: MacVirtualKey.control, flags: .control))
router.keyDown(event(.keyDown, flags: .control))
check(input.keys == [.init(.press, ctrl), .init(.press, tab)], "normal Control press must not be duplicated")
router.keyDown(event(.keyDown, flags: .control, repeatKey: true))
check(input.keys.count == 2, "macOS repeat must not duplicate the guest shortcut")

reset()
router.keyDown(event(.keyDown, flags: [.control, .shift]))
check(input.keys == [.init(.press, ctrl), .init(.press, shift), .init(.press, tab)], "Ctrl+Shift+Tab must preserve both modifiers")
router.keyUp(event(.keyUp))
check(input.keys.contains(.init(.release, ctrl)) && input.keys.contains(.init(.release, shift)) && input.keys.last == .init(.release, tab),
      "modifiers released before Tab must not remain stuck")

reset()
router.flagsChanged(event(.flagsChanged, key: MacVirtualKey.rightControl, flags: .control))
router.keyDown(event(.keyDown, flags: .control))
check(input.keys == [.init(.press, 0x11D), .init(.press, tab)], "known right Control must remain right Control")

reset()
router.keyEquivalent(event(.keyDown, flags: .control))
check(input.keys == [.init(.press, ctrl), .init(.press, tab), .init(.release, tab)], "key equivalents also recover a missed modifier press")
// AppKit/system shortcuts can consume the matching keyUp. The next physical
// press is a new chord, even when the previous equivalent's keyUp was lost.
input.keys.removeAll()
router.keyDown(event(.keyDown, flags: .control))
router.keyUp(event(.keyUp, flags: .control))
check(input.keys == [.init(.press, tab), .init(.release, tab)],
      "a lost key-equivalent keyUp must not swallow the next Ctrl+Tab")

reset()
router.keyDown(event(.keyDown))
check(input.keys == [.init(.press, tab)], "plain Tab must stay plain Tab")
reset()
router.keyDown(event(.keyDown, flags: .command))
check(input.keys == [.init(.press, 0x15B), .init(.press, tab)], "Command must stay guest GUI, without Alt/Ctrl remapping")
reset()
router.keyDown(event(.keyDown, flags: .option))
check(input.keys == [.init(.press, 0x38), .init(.press, tab)], "Option must stay guest Alt")
print("guest key delivery: \(checks) checks passed")
withExtendedLifetime(monitor) {}
