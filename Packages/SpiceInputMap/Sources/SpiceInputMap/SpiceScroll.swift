// SPDX-License-Identifier: MIT
import Foundation

/// Converts AppKit scroll deltas to CocoaSpice's scroll coordinate convention.
public enum SpiceScroll {
    /// AppKit's positive Y scrolls up; CocoaSpice's negative Y scrolls up.
    /// AppKit already applies the user's Natural Scrolling preference, so do not
    /// invert again based on `NSEvent.isDirectionInvertedFromDevice`.
    public static func cocoaSpiceDeltaY(forMacDeltaY delta: CGFloat) -> CGFloat {
        -delta
    }
}
