// SPDX-License-Identifier: MIT
import Foundation

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

    /// Whether window/fullscreen size changes request a matching guest resolution.
    /// Default ON to preserve current virt-viewer-like behavior. Disable it to keep
    /// the guest resolution fixed and only scale locally.
    static var autoResizeGuestDisplay: Bool {
        get { (UserDefaults.standard.object(forKey: autoResizeGuestDisplayKey) as? Bool) ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: autoResizeGuestDisplayKey)
            NotificationCenter.default.post(name: .autoResizeGuestDisplayChanged, object: nil)
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
    static let autoResizeGuestDisplayChanged = Notification.Name("SpiceMac.autoResizeGuestDisplayChanged")
    static let hideHostChromeInFullScreenChanged = Notification.Name("SpiceMac.hideHostChromeInFullScreenChanged")
}
