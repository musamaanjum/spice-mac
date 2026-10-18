// SPDX-License-Identifier: MIT
import Foundation

/// Converts AppKit scroll deltas to CocoaSpice's scroll coordinate convention.
public enum SpiceScroll {
    public enum Speed: Int, CaseIterable {
        case quarter = 25
        case half = 50
        case normal = 100
        case double = 200

        public var title: String {
            self == .normal ? "100% (Default)" : "\(rawValue)%"
        }

        public var factor: CGFloat { CGFloat(rawValue) / 100 }
    }

    /// AppKit's positive Y scrolls up; CocoaSpice's negative Y scrolls up.
    /// AppKit already applies the user's Natural Scrolling preference, so do not
    /// invert again based on `NSEvent.isDirectionInvertedFromDevice`.
    public static func cocoaSpiceDeltaY(forMacDeltaY delta: CGFloat) -> CGFloat {
        -delta
    }

    /// CocoaSpice's smooth-scroll API accumulates fractional wheel notches, not
    /// pixels. Use 40 points per notch for precise devices; a conventional wheel
    /// event keeps the existing one-notch behavior, regardless of acceleration.
    public static func wheelDeltaY(forMacDeltaY delta: CGFloat, precise: Bool,
                                   speed: Speed = .normal) -> CGFloat {
        guard delta.isFinite, delta != 0 else { return 0 }
        let notches = precise ? delta / 40 : (delta > 0 ? CGFloat(1) : -1)
        return cocoaSpiceDeltaY(forMacDeltaY: notches) * speed.factor
    }
}
