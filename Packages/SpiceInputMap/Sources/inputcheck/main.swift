// SPDX-License-Identifier: MIT
import Foundation
import SpiceInputMap

let t = TestRunner()
print("SpiceInputMap checks")

func code(_ k: UInt16) -> Int? { SpiceScancode.setOne(forMacVirtualKey: k) }

t.test("letters map to set-1 make codes") {
    t.expectEqual(code(MacVirtualKey.a), 0x1E)
    t.expectEqual(code(MacVirtualKey.z), 0x2C)
    t.expectEqual(code(MacVirtualKey.m), 0x32)
    t.expectEqual(code(MacVirtualKey.q), 0x10)
    t.expectEqual(code(MacVirtualKey.p), 0x19)
}

t.test("digit row") {
    t.expectEqual(code(MacVirtualKey.one), 0x02)
    t.expectEqual(code(MacVirtualKey.nine), 0x0A)
    t.expectEqual(code(MacVirtualKey.zero), 0x0B)
}

t.test("ISO/GB backslash-pipe key maps to the PC 102nd key") {
    t.expectEqual(MacVirtualKey.isoSection, 0x0A)
    t.expectEqual(code(MacVirtualKey.isoSection), 0x56)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.isoSection), 0x56)
}

t.test("AppKit ISO swap is undone for both affected physical keys") {
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.grave,
                                             isISOKeyboard: true), 0x56)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.isoSection,
                                             isISOKeyboard: true), 0x29)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.grave,
                                             isISOKeyboard: false), 0x29)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.a,
                                             isISOKeyboard: true), 0x1E)
    t.expectEqual(SpiceScancode.breakBytes(0x56), [0xD6])
}

t.test("control and whitespace keys") {
    t.expectEqual(code(MacVirtualKey.escape), 0x01)
    t.expectEqual(code(MacVirtualKey.returnKey), 0x1C)
    t.expectEqual(code(MacVirtualKey.space), 0x39)
    t.expectEqual(code(MacVirtualKey.delete), 0x0E)        // Backspace
    t.expectEqual(code(MacVirtualKey.tab), 0x0F)
}

t.test("left-hand modifiers are non-extended") {
    t.expectEqual(code(MacVirtualKey.control), 0x1D)
    t.expectEqual(code(MacVirtualKey.shift), 0x2A)
    t.expectEqual(code(MacVirtualKey.option), 0x38)
    t.expectEqual(code(MacVirtualKey.capsLock), 0x3A)
    for k in [MacVirtualKey.control, MacVirtualKey.shift, MacVirtualKey.option] {
        t.expect(!SpiceScancode.isExtended(code(k)!), "\(hex(Int(k))) should not be extended")
    }
}

t.test("right-hand modifiers and GUI are extended") {
    t.expectEqual(code(MacVirtualKey.rightControl), 0xE01D)
    t.expectEqual(code(MacVirtualKey.rightOption), 0xE038)
    t.expectEqual(code(MacVirtualKey.rightCommand), 0xE05C)
    t.expectEqual(code(MacVirtualKey.command), 0xE05B)     // left GUI
    t.expect(SpiceScancode.isExtended(0xE05B), "GUI should be extended")
}

t.test("function keys F1-F12") {
    t.expectEqual(code(MacVirtualKey.f1), 0x3B)
    t.expectEqual(code(MacVirtualKey.f10), 0x44)
    t.expectEqual(code(MacVirtualKey.f11), 0x57)
    t.expectEqual(code(MacVirtualKey.f12), 0x58)
}

t.test("extended function keys F13-F20") {
    let expected = [0x5D, 0x5E, 0x5F, 0x55, 0xE003, 0xE077, 0xE004, 0x5A]
    let keys = [MacVirtualKey.f13, MacVirtualKey.f14, MacVirtualKey.f15, MacVirtualKey.f16,
                MacVirtualKey.f17, MacVirtualKey.f18, MacVirtualKey.f19, MacVirtualKey.f20]
    t.expectEqual(keys.compactMap(code), expected)
}

t.test("keypad equals, context menu, and media keys") {
    t.expectEqual(code(MacVirtualKey.keypadEquals), 0x59)
    t.expectEqual(code(MacVirtualKey.contextualMenu), 0xE05D)
    t.expectEqual(code(MacVirtualKey.mute), 0xE020)
    t.expectEqual(code(MacVirtualKey.volumeDown), 0xE02E)
    t.expectEqual(code(MacVirtualKey.volumeUp), 0xE030)
}

t.test("JIS-specific physical keys") {
    t.expectEqual(code(MacVirtualKey.jisYen), 0x7D)
    t.expectEqual(code(MacVirtualKey.jisUnderscore), 0x73)
    t.expectEqual(code(MacVirtualKey.jisKeypadComma), 0x5C)
    t.expectEqual(code(MacVirtualKey.jisEisu), 0xF1)
    t.expectEqual(code(MacVirtualKey.jisKana), 0xF2)
}

t.test("arrow keys are extended with correct make codes") {
    t.expectEqual(code(MacVirtualKey.upArrow), 0xE048)
    t.expectEqual(code(MacVirtualKey.downArrow), 0xE050)
    t.expectEqual(code(MacVirtualKey.leftArrow), 0xE04B)
    t.expectEqual(code(MacVirtualKey.rightArrow), 0xE04D)
    for k in [MacVirtualKey.upArrow, MacVirtualKey.downArrow, MacVirtualKey.leftArrow, MacVirtualKey.rightArrow] {
        t.expect(SpiceScancode.isExtended(code(k)!), "arrow should be extended")
    }
}

t.test("navigation cluster is extended") {
    t.expectEqual(code(MacVirtualKey.home), 0xE047)
    t.expectEqual(code(MacVirtualKey.end), 0xE04F)
    t.expectEqual(code(MacVirtualKey.pageUp), 0xE049)
    t.expectEqual(code(MacVirtualKey.pageDown), 0xE051)
    t.expectEqual(code(MacVirtualKey.help), 0xE052)          // Insert
    t.expectEqual(code(MacVirtualKey.forwardDelete), 0xE053) // Delete
}

t.test("keypad: numbers non-extended, Enter/Divide extended") {
    t.expectEqual(code(MacVirtualKey.keypad0), 0x52)
    t.expectEqual(code(MacVirtualKey.keypad7), 0x47)
    t.expectEqual(code(MacVirtualKey.keypadClear), 0x45)     // NumLock
    t.expectEqual(code(MacVirtualKey.keypadEnter), 0xE01C)
    t.expectEqual(code(MacVirtualKey.keypadDivide), 0xE035)
    t.expect(!SpiceScancode.isExtended(code(MacVirtualKey.keypad0)!), "keypad 0 not extended")
    t.expect(SpiceScancode.isExtended(code(MacVirtualKey.keypadEnter)!), "keypad enter extended")
}

t.test("make/break byte expansion") {
    // Plain key: Escape
    t.expectEqual(SpiceScancode.makeBytes(0x01), [0x01])
    t.expectEqual(SpiceScancode.breakBytes(0x01), [0x81])
    // Extended key: Right arrow 0xE04D
    t.expectEqual(SpiceScancode.makeBytes(0xE04D), [0xE0, 0x4D])
    t.expectEqual(SpiceScancode.breakBytes(0xE04D), [0xE0, 0xCD])
}

t.test("CocoaSpice 0x100 extended encoding (CSInput.sendKey:code:)") {
    // Plain keys: bare make byte.
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0x01), 0x01)        // Esc
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0x1E), 0x1E)        // A
    // Extended keys: 0xE0NN -> 0x1NN.
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE04D), 0x14D)     // Right arrow
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE01D), 0x11D)     // Right Ctrl
    t.expectEqual(SpiceScancode.cocoaSpiceEncoded(0xE01C), 0x11C)     // Keypad Enter
    // End-to-end from a mac key code.
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.rightArrow), 0x14D)
    t.expectEqual(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: MacVirtualKey.escape), 0x01)
    t.expect(SpiceScancode.cocoaSpiceCode(forMacVirtualKey: 0xFE) == nil, "unmapped -> nil")
}

t.test("unmapped keys return nil") {
    t.expect(code(0xFE) == nil, "0xFE should be unmapped")
}

t.test("all scancodes are unique (no accidental duplicate make codes)") {
    let values = Array(SpiceScancode.table.values)
    let unique = Set(values)
    t.expectEqual(values.count, unique.count)
    t.expect(values.count >= 90, "expected a broad mapping, got \(values.count) entries")
}

t.finishAndExit()
