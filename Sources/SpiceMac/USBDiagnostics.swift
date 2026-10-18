// SPDX-License-Identifier: MIT
import AppKit
import CocoaSpice

enum USBDiagnostics {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpiceMac", isDirectory: true)
    private static var log: DiagnosticLog?

    static func start() {
        do {
            let writer = try DiagnosticLog(directory: directory)
            log = writer
            let bundle = Bundle.main
            writer.record("start version=\(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "development") "
                + "commit=\(bundle.object(forInfoDictionaryKey: "SpiceMacGitCommit") ?? "unknown") "
                + "os=\(ProcessInfo.processInfo.operatingSystemVersionString) arch=\(architecture) euid=\(geteuid())")
            CSMain.shared.logHandler = { line in
                writer.record(line.trimmingCharacters(in: .whitespacesAndNewlines))
                // Keep command-line debug-run output available as before.
                if ProcessInfo.processInfo.environment["SPICE_DEBUG"] != nil {
                    fputs(line.hasSuffix("\n") ? line : line + "\n", stderr)
                }
            }
            CSMain.shared.spiceEnableUSBDiagnostics()
        } catch {
            NSLog("SpiceMac: could not open USB diagnostics: %@", error.localizedDescription)
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func revealLogs() {
        NSWorkspace.shared.open(directory)
    }
}
