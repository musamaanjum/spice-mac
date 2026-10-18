// SPDX-License-Identifier: MIT
import Foundation
import Darwin

/// Synchronous writes keep the last error on disk even if the app crashes.
/// Each process has its own files so a second app cannot rotate an active log.
final class DiagnosticLog {
    private let lock = NSLock()
    private let directory: URL
    private let prefix: String
    private let maximumBytes: Int
    private var descriptor: Int32 = -1
    private var byteCount = 0
    private var segment = 0
    private(set) var fileURL: URL

    init(directory: URL, maximumBytes: Int = 5 * 1024 * 1024) throws {
        self.directory = directory
        self.maximumBytes = maximumBytes
        prefix = "USB-\(Int(Date().timeIntervalSince1970))-\(getpid())-\(UUID().uuidString.prefix(8))"
        fileURL = directory.appendingPathComponent("\(prefix)-0.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try openSegment()
        // Only expire old logs; never prune files belonging to another live app.
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("USB-") && file.pathExtension == "log" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            let fields = file.lastPathComponent.split(separator: "-")
            if fields.count >= 3, let pid = Int32(fields[2]), kill(pid, 0) == 0 || errno == EPERM {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    deinit { if descriptor >= 0 { close(descriptor) } }

    private func openSegment() throws {
        descriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        byteCount = 0
    }

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { return }
        // Keep records on one line, cap native messages, and mask common auth fields.
        let clean = Self.redacted(String(message.prefix(32_768)))
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " | ")
        let data = Data("\(Date().timeIntervalSince1970) pid=\(getpid()) \(clean)\n".utf8)
        if byteCount > 0 && byteCount + data.count > maximumBytes {
            close(descriptor)
            descriptor = -1
            segment += 1
            fileURL = directory.appendingPathComponent("\(prefix)-\(segment).log")
            do { try openSegment() }
            catch {
                NSLog("SpiceMac: could not rotate USB diagnostics: %@", error.localizedDescription)
                return
            }
            // Retain the current segment and the previous three (about 20 MiB).
            if segment >= 4 {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(prefix)-\(segment - 4).log"))
            }
        }
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    NSLog("SpiceMac: could not write USB diagnostics (errno=%d)", errno)
                    close(descriptor)
                    descriptor = -1
                    return
                }
                offset += count
                byteCount += count
            }
        }
    }

    static func redacted(_ message: String) -> String {
        let headers = message.replacingOccurrences(
            of: #"(?i)\bauthorization\s*[:=]\s*(?:Basic|Bearer)\s+[^\s,;]+"#,
            with: "authorization=<redacted>", options: .regularExpression)
        return headers.replacingOccurrences(
            of: #"(?i)\b(password|passwd|ticket|authorization|PVEAuthCookie)[\"']?\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"#,
            with: "$1=<redacted>", options: .regularExpression)
    }
}
