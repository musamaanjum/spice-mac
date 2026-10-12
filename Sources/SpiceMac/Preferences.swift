// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics

enum GuestResolutionMode {
    case manual, automatic, fullHD, fixed1512, fitWindow15

    func resolution(for size: CGSize, backingScale: CGFloat) -> CGSize? {
        switch self {
        case .manual: return nil
        case .fullHD: return CGSize(width: 1920, height: 1080)
        case .fixed1512: return CGSize(width: 1512, height: 982)
        case .automatic, .fitWindow15:
            guard size.width > 1, size.height > 1 else { return nil }
            let scale: CGFloat = self == .fitWindow15 ? backingScale / 1.5 : 1
            return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        }
    }
}

/// App preferences, backed by `UserDefaults`.
enum Preferences {
    private static let hideHostCursorKey = "HideHostCursor"

    /// When true, the macOS cursor is hidden over the display so only the guest
    /// cursor shows. Default off. Changing it posts `.hideHostCursorChanged`.
    static var hideHostCursor: Bool {
        get { UserDefaults.standard.bool(forKey: hideHostCursorKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideHostCursorKey)
            NotificationCenter.default.post(name: .hideHostCursorChanged, object: nil)
        }
    }

    private static let shareClipboardKey = "ShareClipboard"

    /// Whether to share the clipboard with the guest (both directions). Default
    /// ON (matches virt-viewer and the working behavior). Disable it when
    /// connecting to an untrusted VM — while on, anything you copy on the Mac is
    /// sent to the guest. Takes effect on the next connection.
    static var shareClipboard: Bool {
        get { (UserDefaults.standard.object(forKey: shareClipboardKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: shareClipboardKey) }
    }

    private static let autoResizeGuestDisplayKey = "AutoResizeGuestDisplay"

    private static let fixed1080pGuestDisplayKey = "Fixed1080pGuestDisplay"
    private static let fixed1512GuestDisplayKey = "Fixed1512GuestDisplay"
    private static let fitGuestToScreenKey = "FixedCurrentScreenGuestDisplay"

    /// Keep existing defaults, but change the whole selection before notifying
    /// windows. One menu click must not request several intermediate resolutions.
    static var guestResolutionMode: GuestResolutionMode {
        get {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: fixed1512GuestDisplayKey) { return .fixed1512 }
            if defaults.bool(forKey: fitGuestToScreenKey) { return .fitWindow15 }
            if defaults.bool(forKey: fixed1080pGuestDisplayKey) { return .fullHD }
            if (defaults.object(forKey: autoResizeGuestDisplayKey) as? Bool) ?? true { return .automatic }
            return .manual
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue == .automatic, forKey: autoResizeGuestDisplayKey)
            defaults.set(newValue == .fullHD, forKey: fixed1080pGuestDisplayKey)
            defaults.set(newValue == .fixed1512, forKey: fixed1512GuestDisplayKey)
            defaults.set(newValue == .fitWindow15, forKey: fitGuestToScreenKey)
            NotificationCenter.default.post(name: .guestResolutionModeChanged, object: nil)
        }
    }

    private static let hideHostChromeInFullScreenKey = "HideHostChromeInFullScreen"

    /// Whether fullscreen sessions suppress the host Dock and menu bar. Default ON
    /// so the VM owns screen edges like a dedicated remote viewer.
    static var hideHostChromeInFullScreen: Bool {
        get { (UserDefaults.standard.object(forKey: hideHostChromeInFullScreenKey) as? Bool) ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: hideHostChromeInFullScreenKey)
            NotificationCenter.default.post(name: .hideHostChromeInFullScreenChanged, object: nil)
        }
    }

    private static let trashAfterUseKey = "TrashConnectionFileAfterUse"

    /// Whether to move a `.vv` connection file to the Trash after using it to
    /// connect. Proxmox SPICE tickets are single-use and the file also carries the
    /// cluster CA, so keeping it around is pointless and a mild secret-hygiene risk.
    /// Default ON. It goes to the Trash (recoverable), not a permanent delete.
    static var trashConnectionFileAfterUse: Bool {
        get { (UserDefaults.standard.object(forKey: trashAfterUseKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: trashAfterUseKey) }
    }
}

extension Notification.Name {
    static let hideHostCursorChanged = Notification.Name("SpiceMac.hideHostCursorChanged")
    static let guestResolutionModeChanged = Notification.Name("SpiceMac.guestResolutionModeChanged")
    static let hideHostChromeInFullScreenChanged = Notification.Name("SpiceMac.hideHostChromeInFullScreenChanged")
}
