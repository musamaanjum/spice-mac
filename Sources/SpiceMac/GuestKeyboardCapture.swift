// SPDX-License-Identifier: MIT
import AppKit
import Carbon

/// Records only Tab/Control delivery and focus state, never typed characters.
enum GuestKeyboardTrace {
    private static var descriptor: Int32 = -1

    static func start() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SpiceMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("Keyboard.log").path
        descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o600)
        setenv("SPICEMAC_KEYBOARD_TRACE_PATH", path, 1)
        record("start fullscreen-shortcut-capture-3 pid=\(getpid()) app=\(Bundle.main.bundlePath)")
    }

    static func record(_ message: String) {
        guard descriptor >= 0 else { return }
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        line.utf8CString.withUnsafeBytes { buffer in
            _ = write(descriptor, buffer.baseAddress!, buffer.count - 1)
        }
    }
}

/// AppKit's disableProcessSwitching suppresses the switcher UI; it does not
/// arrange delivery of system-owned shortcuts. VM clients such as UTM capture
/// at the WindowServer hotkey layer instead. Resolve these SPI functions at
/// runtime so an unavailable API cannot prevent the app from launching.
final class SystemShortcutCapture {
    typealias Connection = @convention(c) () -> UInt32
    typealias GetMode = @convention(c) (UInt32, UnsafeMutablePointer<Int32>) -> Int32
    typealias SetMode = @convention(c) (UInt32, Int32) -> Int32
    private let connection: Connection?
    private let getMode: GetMode?
    private let setMode: SetMode?
    private var originalMode: Int32?

    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        connection = symbol("CGSMainConnectionID", as: Connection.self)
        getMode = symbol("CGSGetGlobalHotKeyOperatingMode", as: GetMode.self)
        setMode = symbol("CGSSetGlobalHotKeyOperatingMode", as: SetMode.self)
        if let handle { dlclose(handle) }
    }

    var currentMode: Int32? {
        guard let connection, let getMode else { return nil }
        var mode: Int32 = 0
        guard getMode(connection(), &mode) == 0 else { return nil }
        return mode
    }

    func setCaptured(_ captured: Bool) {
        guard let connection, let setMode else {
            if captured { GuestKeyboardTrace.record("capture unavailable WindowServer API") }
            return
        }
        if captured {
            if originalMode == nil { originalMode = currentMode ?? 0 }
            // Disable host hotkey interception on this application's connection.
            // Ordinary key events (including Ctrl+Tab) then reach the responder.
            let result = setMode(connection(), 1)
            GuestKeyboardTrace.record("capture on result=\(result) mode=\(currentMode ?? -1)")
        } else if let originalMode {
            let result = setMode(connection(), originalMode)
            self.originalMode = nil
            GuestKeyboardTrace.record("capture off result=\(result) mode=\(currentMode ?? -1)")
        }
    }

    deinit { setCaptured(false) }
}

enum GuestKeyboardPolicy {
    static func routesTabToHost(_ event: NSEvent, isFullScreen: Bool) -> Bool {
        !isFullScreen && event.keyCode == UInt16(kVK_Tab) && event.modifierFlags.contains(.control)
    }
}

/// Runs before AppKit's key equivalents and window-tab navigation. Forward the
/// physical Tab press/release, including Shift-Tab and modifier-first releases.
final class GuestKeyboardMonitor {
    private var monitor: Any?
    private let isGuestFocused: (NSEvent) -> Bool
    private let isFullScreen: () -> Bool
    private let keyDown: (NSEvent) -> Void
    private let keyUp: (NSEvent) -> Void
    private let release: () -> Void
    private let trace: (String) -> Void

    init(isGuestFocused: @escaping (NSEvent) -> Bool,
         isFullScreen: @escaping () -> Bool,
         keyDown: @escaping (NSEvent) -> Void,
         keyUp: @escaping (NSEvent) -> Void,
         release: @escaping () -> Void,
         trace: @escaping (String) -> Void = { _ in }) {
        self.isGuestFocused = isGuestFocused
        self.isFullScreen = isFullScreen
        self.keyDown = keyDown
        self.keyUp = keyUp
        self.release = release
        self.trace = trace
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let focused = isGuestFocused(event)
        if event.keyCode == UInt16(kVK_Tab) {
            trace("monitor type=\(event.type.rawValue) flags=\(event.modifierFlags.rawValue) focused=\(focused) fullscreen=\(isFullScreen())")
        }
        guard focused else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, event.keyCode == UInt16(kVK_ANSI_R),
           flags.contains([.control, .option]), !flags.contains(.command) {
            release()
            return nil
        }
        guard isFullScreen(), event.keyCode == UInt16(kVK_Tab) else { return event }
        if event.type == .keyDown { keyDown(event) } else { keyUp(event) }
        return nil
    }
}

/// Presentation options belong to the application, not individual windows.
/// A single owner prevents a background session from restoring another session's
/// keyboard grab. Restore only the bits we changed; AppKit owns fullscreen state.
final class HostPresentationController {
    static let shared = HostPresentationController()
    private var ownerID: ObjectIdentifier?
    private var originalOptions: NSApplication.PresentationOptions?
    private var fullScreenBaselines: [ObjectIdentifier: NSApplication.PresentationOptions] = [:]
    private var windowedBaselines: [ObjectIdentifier: NSApplication.PresentationOptions] = [:]
    let shortcutCapture = SystemShortcutCapture()
    private static let managedOptions: NSApplication.PresentationOptions = [
        .hideDock, .autoHideDock, .hideMenuBar, .autoHideMenuBar, .disableProcessSwitching
    ]

    static func options(_ base: NSApplication.PresentationOptions,
                        hideChrome: Bool) -> NSApplication.PresentationOptions {
        var options = base
        if hideChrome {
            options.subtract([.autoHideDock, .autoHideMenuBar])
            options.formUnion([.hideDock, .hideMenuBar])
        }
        // Keyboard capture is independent of Dock/menu-bar presentation.
        options.remove(.disableProcessSwitching)
        return options
    }

    /// AppKit reapplies the delegate's fullscreen options after didEnterFullScreen.
    /// Save the unmodified proposal before hiding chrome, so a later release
    /// restores native fullscreen presentation instead of our overrides.
    func fullScreenOptions(owner: AnyObject, proposedOptions: NSApplication.PresentationOptions,
                           hideChrome: Bool) -> NSApplication.PresentationOptions {
        let id = ObjectIdentifier(owner)
        if windowedBaselines[id] == nil { windowedBaselines[id] = NSApp.presentationOptions }
        let baseline = fullScreenBaselines[id] ?? proposedOptions
        fullScreenBaselines[id] = baseline
        if ownerID != id {
            restoreCurrentOwner()
            ownerID = id
            originalOptions = baseline
        }
        var base = proposedOptions
        base.subtract(Self.managedOptions)
        base.formUnion(baseline.intersection(Self.managedOptions))
        return Self.options(base, hideChrome: hideChrome)
    }

    func update(owner: AnyObject, hideChrome: Bool, captureKeyboard: Bool) {
        guard hideChrome || captureKeyboard else {
            restore(owner: owner)
            return
        }
        if ownerID != ObjectIdentifier(owner) {
            restoreCurrentOwner()
            ownerID = ObjectIdentifier(owner)
            originalOptions = fullScreenBaselines[ObjectIdentifier(owner)] ?? NSApp.presentationOptions
        }
        NSApp.presentationOptions = Self.options(restoredOptions(), hideChrome: hideChrome)
        shortcutCapture.setCaptured(captureKeyboard)
    }

    func restore(owner: AnyObject, useWindowedOptions: Bool = false) {
        let id = ObjectIdentifier(owner)
        guard ownerID == id || (ownerID == nil && fullScreenBaselines[id] != nil) else { return }
        if useWindowedOptions, let baseline = windowedBaselines[id] {
            originalOptions = baseline
        } else if originalOptions == nil {
            originalOptions = fullScreenBaselines[id]
        }
        restoreCurrentOwner()
    }

    func endFullScreen(owner: AnyObject) {
        restore(owner: owner, useWindowedOptions: true)
        fullScreenBaselines.removeValue(forKey: ObjectIdentifier(owner))
        windowedBaselines.removeValue(forKey: ObjectIdentifier(owner))
    }

    private func restoredOptions() -> NSApplication.PresentationOptions {
        var options = NSApp.presentationOptions
        options.subtract(Self.managedOptions)
        options.formUnion((originalOptions ?? []).intersection(Self.managedOptions))
        return options
    }

    private func restoreCurrentOwner() {
        shortcutCapture.setCaptured(false)
        if originalOptions != nil { NSApp.presentationOptions = restoredOptions() }
        originalOptions = nil
        ownerID = nil
    }
}
