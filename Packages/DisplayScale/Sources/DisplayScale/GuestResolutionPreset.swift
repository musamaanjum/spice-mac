// SPDX-License-Identifier: MIT
import CoreGraphics

/// Fixed presets share the upstream request path; window sizing uses its zoom.
public enum GuestResolutionPreset: Int, CaseIterable {
    case window = 0
    case manual = -1
    case fullHD = 1920
    case macBook = 1512

    public var title: String {
        switch self {
        case .window: return "Match Window (Use Zoom)"
        case .manual: return "Keep Current Resolution"
        case .fullHD: return "1920 × 1080"
        case .macBook: return "1512 × 982"
        }
    }

    public func target(viewPoints: CGSize, backingScale: CGFloat, zoom: DisplayZoom) -> CGSize? {
        switch self {
        case .manual: return nil
        case .window:
            return DisplayScale.targetGuestSize(viewPoints: viewPoints, backingScale: backingScale, zoom: zoom)
        case .fullHD: return CGSize(width: 1920, height: 1080)
        case .macBook: return CGSize(width: 1512, height: 982)
        }
    }
}
