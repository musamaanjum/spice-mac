// SPDX-License-Identifier: MIT
// Test transport records the actual CSInput.send API calls from SpiceInputRouter.
import AppKit

public enum CSInputKey: Equatable { case press, release }
public enum CSInputScroll { case up, down, smooth }
public struct CSInputButton: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = Self(rawValue: 1)
    public static let middle = Self(rawValue: 2)
    public static let right = Self(rawValue: 4)
    public static let side = Self(rawValue: 32)
    public static let extra = Self(rawValue: 64)
}
public final class CSInput {
    public struct Key: Equatable {
        public let type: CSInputKey
        public let code: Int32
        public init(_ type: CSInputKey, _ code: Int32) { self.type = type; self.code = code }
    }
    public var keys: [Key] = []
    public var serverModeCursor = false
    public var flushes = 0
    public init() {}
    public func send(_ type: CSInputKey, code: Int32) { keys.append(Key(type, code)) }
    public func releaseKeys() { flushes += 1 }
    public func sendMouseButton(_ button: CSInputButton, mask: CSInputButton, pressed: Bool) {}
    public func sendMouseMotion(_ mask: CSInputButton, relativePoint: CGPoint) {}
    public func sendMousePosition(_ mask: CSInputButton, absolutePoint: CGPoint) {}
    public func sendMouseScroll(_ type: CSInputScroll, buttonMask: CSInputButton, dy: CGFloat) {}
    public func requestMouseMode(_ server: Bool) {}
}
