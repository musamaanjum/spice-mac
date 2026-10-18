// SPDX-License-Identifier: MIT
import Foundation
import Darwin

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spice-usb-log-check-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let concurrentDirectory = directory.appendingPathComponent("concurrent")
let log = try DiagnosticLog(directory: concurrentDirectory)
DispatchQueue.concurrentPerform(iterations: 8) { worker in
    for event in 0..<100 { log.record("worker=\(worker) event=\(event)") }
}
let content = try String(contentsOf: log.fileURL, encoding: .utf8)
let lines = content.split(separator: "\n")
check(lines.count == 800, "Concurrent callbacks lost or split log records")
for worker in 0..<8 {
    for event in 0..<100 {
        check(lines.filter { $0.hasSuffix("worker=\(worker) event=\(event)") }.count == 1,
              "Concurrent callbacks interleaved records")
    }
}
let permissions = try FileManager.default.attributesOfItem(atPath: log.fileURL.path)[.posixPermissions] as! NSNumber
check(permissions.intValue == 0o600, "Diagnostic file must be private")

let secondLog = try DiagnosticLog(directory: concurrentDirectory)
secondLog.record("second app")
check(secondLog.fileURL != log.fileURL, "Two apps must use different diagnostic files")
log.record("first app still logging")
check(try String(contentsOf: log.fileURL, encoding: .utf8).contains("first app still logging"), "Second app disrupted the first log")

let rotatingDirectory = directory.appendingPathComponent("rotation")
let rotatingLog = try DiagnosticLog(directory: rotatingDirectory, maximumBytes: 256)
for event in 0..<100 { rotatingLog.record("rotation event=\(event) " + String(repeating: "x", count: 64)) }
let segments = try FileManager.default.contentsOfDirectory(at: rotatingDirectory, includingPropertiesForKeys: nil)
check(segments.count == 4, "Rotation must retain four segments")
check(try String(contentsOf: rotatingLog.fileURL, encoding: .utf8).contains("rotation event=99"), "Rotation lost the most recent error")
for file in segments {
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    check((attributes[.size] as! NSNumber).intValue <= 256, "Rotation exceeded the size limit")
}

let redacted = DiagnosticLog.redacted(#"password="private value" ticket=PVE:secret PVEAuthCookie=secret authorization=secret id=18d1:4ee7"#)
check(!redacted.contains("secret") && !redacted.contains("private value"), "Authentication values leaked")
check(redacted.contains("id=18d1:4ee7"), "Redaction removed useful USB identity")
for message in ["Authorization: Bearer private-token", "Authorization: Basic private-token", #""password": "private-token""#] {
    check(!DiagnosticLog.redacted(message).contains("private-token"), "Structured authentication value leaked")
}
log.record("error with\na forged record\rnext line")
let finalLines = try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n")
check(finalLines.last!.hasSuffix("error with | a forged record next line"), "Native multiline errors must remain one record")

let expired = concurrentDirectory.appendingPathComponent("USB-0-2147483647-expired-0.log")
let live = concurrentDirectory.appendingPathComponent("USB-0-\(getpid())-live-0.log")
for file in [expired, live] {
    try Data().write(to: file)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-15 * 24 * 60 * 60)], ofItemAtPath: file.path)
}
let retentionLog = try DiagnosticLog(directory: concurrentDirectory)
retentionLog.record("retention check")
check(!FileManager.default.fileExists(atPath: expired.path), "Expired diagnostics were not pruned")
check(FileManager.default.fileExists(atPath: live.path), "Retention deleted another live app's log")

let invalidDirectory = directory.appendingPathComponent("regular-file")
try Data().write(to: invalidDirectory)
do {
    _ = try DiagnosticLog(directory: invalidDirectory)
    fatalError("An invalid log destination must report an error")
} catch { }

print("Passed USB diagnostic concurrency, rotation, privacy, redaction, process isolation, and error checks.")
