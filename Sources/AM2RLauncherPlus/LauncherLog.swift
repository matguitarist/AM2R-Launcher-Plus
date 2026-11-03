import AM2RLauncherPlusKit
import Foundation
import os

/// What the launcher did, for the Debug Log window: kept in memory (the last 5000 entries),
/// written to <data folder>/Logs/launcher.log, and sent to the system log (Console, subsystem
/// com.mathieu.am2rlauncherplus).
@Observable
final class LauncherLog {
    static let shared = LauncherLog()
    static let limit = 5000

    private(set) var entries: [DebugLog.Entry] = []
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var pending: [String] = []
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private let system = Logger(subsystem: "com.mathieu.am2rlauncherplus", category: "launcher")

    static var file: URL { DataFolder.url.appending(path: "Logs/launcher.log") }

    func add(_ level: DebugLog.Level, _ source: String, _ message: String) {
        let entry = DebugLog.Entry(id: nextID, date: .now, level: level, source: source, message: message)
        nextID += 1
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        switch level {
        case .debug: system.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .info: system.info("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .warning: system.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .error: system.error("[\(source, privacy: .public)] \(message, privacy: .public)")
        }
        // Batched: many lines at once (a download) become one write.
        pending.append(DebugLog.line(entry))
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            flush()
        }
    }

    func flush() {
        flushScheduled = false
        let lines = pending, file = Self.file
        pending = []
        Task.detached(priority: .utility) { DebugLog.append(lines, to: file) }
    }
}

/// `log(.info, "Install", "…")` from anywhere on the main actor.
func log(_ level: DebugLog.Level, _ source: String, _ message: String) {
    LauncherLog.shared.add(level, source, message)
}
