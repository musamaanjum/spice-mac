// SPDX-License-Identifier: MIT
import Foundation
import CoreGraphics

@main
struct ResolutionCheck {
    static func main() {
        // This runner must never write the real app's preference domain.
        precondition(ProcessInfo.processInfo.processName == "resolutioncheck")
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: "resolutioncheck")
        defer { defaults.removePersistentDomain(forName: "resolutioncheck") }

        let area = CGSize(width: 1512, height: 950)
        precondition(GuestResolutionMode.automatic.resolution(for: area, backingScale: 2) == area)
        precondition(GuestResolutionMode.fitWindow15.resolution(for: area, backingScale: 2)
                     == CGSize(width: 2016, height: 1266))
        precondition(GuestResolutionMode.fitWindow15.resolution(for: CGSize(width: 1200, height: 750), backingScale: 1)
                     == CGSize(width: 800, height: 500))
        precondition(GuestResolutionMode.fullHD.resolution(for: area, backingScale: 2)
                     == CGSize(width: 1920, height: 1080))
        precondition(GuestResolutionMode.fixed1512.resolution(for: area, backingScale: 2)
                     == CGSize(width: 1512, height: 982))
        precondition(GuestResolutionMode.manual.resolution(for: area, backingScale: 2) == nil)
        precondition(GuestResolutionMode.automatic.resolution(for: .zero, backingScale: 2) == nil)

        precondition(Preferences.guestResolutionMode == .automatic)
        defaults.set(true, forKey: "FixedCurrentScreenGuestDisplay")
        precondition(Preferences.guestResolutionMode == .fitWindow15)
        defaults.set(false, forKey: "FixedCurrentScreenGuestDisplay")
        defaults.set(true, forKey: "Fixed1080pGuestDisplay")
        precondition(Preferences.guestResolutionMode == .fullHD)

        var count = 0
        var observed: GuestResolutionMode?
        let observer = NotificationCenter.default.addObserver(
            forName: .guestResolutionModeChanged, object: nil, queue: nil) { _ in
                count += 1
                observed = Preferences.guestResolutionMode
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        for mode: GuestResolutionMode in [.automatic, .fullHD, .fixed1512, .fitWindow15, .manual, .fixed1512, .fixed1512] {
            let before = count
            Preferences.guestResolutionMode = mode
            precondition(count == before + 1 && observed == mode)
            let selected = ["AutoResizeGuestDisplay", "Fixed1080pGuestDisplay", "Fixed1512GuestDisplay", "FixedCurrentScreenGuestDisplay"]
                .filter { defaults.bool(forKey: $0) }.count
            precondition(selected == (mode == .manual ? 0 : 1))
        }
        print("Resolution checks passed: geometry, existing preferences, atomic selection, preset reapply")
    }
}
