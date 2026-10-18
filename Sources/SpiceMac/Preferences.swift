// SPDX-License-Identifier: MIT
import Foundation
import DisplayScale
import SpiceInputMap

/// App preferences, backed by `UserDefaults`.
enum Preferences {
    static var scrollSpeed: SpiceScroll.Speed {
        get {
            SpiceScroll.Speed(rawValue: UserDefaults.standard.integer(forKey: "ScrollSpeed")) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "ScrollSpeed") }
    }

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

    private static let displayZoomKey = "DisplayZoom"
    private static let guestResolutionPresetKey = "GuestResolutionPreset"

    /// Seed for new windows, like displayZoom. Read the old preset keys only
    /// until a selection has been saved using the new single key.
    static var guestResolutionPreset: GuestResolutionPreset {
        get {
            let defaults = UserDefaults.standard
            if let raw = defaults.object(forKey: guestResolutionPresetKey) as? Int {
                return GuestResolutionPreset(rawValue: raw) ?? .window
            }
            if defaults.bool(forKey: "FixedCurrentScreenGuestDisplay") { return .window }
            if defaults.bool(forKey: "Fixed1512GuestDisplay") { return .macBook }
            if defaults.bool(forKey: "Fixed1080pGuestDisplay") { return .fullHD }
            if (defaults.object(forKey: "AutoResizeGuestDisplay") as? Bool) == false { return .manual }
            return .window
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: guestResolutionPresetKey) }
    }

    /// The zoom level a NEWLY opened window starts at: host physical pixels per
    /// guest pixel. A seed, NOT a live global — zoom belongs to the window (see
    /// `SpiceWindowController.displayZoom`), so writing this notifies nobody.
    /// Default `.automatic` (zoom = backingScaleFactor), and raw 0 == `.automatic`,
    /// so a missing key reads as automatic.
    static var displayZoom: DisplayZoom {
        get {
            if UserDefaults.standard.object(forKey: displayZoomKey) == nil,
               UserDefaults.standard.bool(forKey: "FixedCurrentScreenGuestDisplay") {
                return .percent150
            }
            return DisplayZoom(rawValue: UserDefaults.standard.integer(forKey: displayZoomKey)) ?? .automatic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: displayZoomKey) }
    }
}

extension Notification.Name {
    static let hideHostCursorChanged = Notification.Name("SpiceMac.hideHostCursorChanged")
    static let hideHostChromeInFullScreenChanged = Notification.Name("SpiceMac.hideHostChromeInFullScreenChanged")
}
