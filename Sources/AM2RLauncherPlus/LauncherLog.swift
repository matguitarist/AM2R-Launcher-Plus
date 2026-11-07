import AM2RLauncherPlusKit
import Foundation
import LogKitUI
import os

/// What the launcher did, for the Log page: kept in memory (the last 5000 entries) in a LogKit store,
/// written to <data folder>/Logs/launcher.log, and sent to the system log (Console, subsystem
/// com.mathieu.am2rlauncherplus).
final class LauncherLog {
    static let shared = LauncherLog()
    static let limit = 5000

    /// Memory only: launcher.log keeps its own format and rotation, written below.
    let store = LogStore(fileURL: nil, limit: LauncherLog.limit)
    /// The Log page's Launcher view, kept here so filters and Clear survive leaving the page.
    let viewer: LogViewerModel

    private var pending: [String] = []
    private var flushScheduled = false
    private let system = Logger(subsystem: "com.mathieu.am2rlauncherplus", category: "launcher")

    static var file: URL { DataFolder.url.appending(path: "Logs/launcher.log") }

    init() {
        viewer = LogViewerModel(store: store)
        viewer.filter.levels = DebugLogSource.startLevels
        viewer.defaultFilter = viewer.filter
    }

    var entries: [LogEntry] { store.entries }

    func add(_ level: DebugLog.Level, _ source: String, _ message: String) {
        store.post(level.logLevel, message, source: source)
        switch level {
        case .debug: system.debug("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .info: system.info("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .warning: system.warning("[\(source, privacy: .public)] \(message, privacy: .public)")
        case .error: system.error("[\(source, privacy: .public)] \(message, privacy: .public)")
        }
        // Batched: many lines at once (a download) become one write.
        pending.append(DebugLog.line(date: .now, level: level, source: source, message: message))
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
