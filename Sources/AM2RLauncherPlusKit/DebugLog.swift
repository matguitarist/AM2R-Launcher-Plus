import Foundation

/// Lines of the Debug Log window: the launcher's own events, and the game's output read back from its log.
public enum DebugLog {
    public enum Level: Int, CaseIterable, Comparable, Sendable, Codable {
        case debug, info, warning, error

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .debug: "Debug"
            case .info: "Info"
            case .warning: "Warning"
            case .error: "Error"
            }
        }

        /// The word in launcher.log.
        var tag: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERROR"
            }
        }
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: Int
        /// Nil for game lines: the game doesn't write times.
        public var date: Date?
        public var level: Level
        /// What wrote it: "Install", "Play", "Update" for the launcher; "VM", "GL", "Runner" for the game.
        public var source: String
        public var message: String

        public init(id: Int, date: Date?, level: Level, source: String, message: String) {
            self.id = id
            self.date = date
            self.level = level
            self.source = source
            self.message = message
        }
    }

    // MARK: launcher.log

    /// "2026-11-03T14:05:00Z INFO [Install] Downloaded patch data 7e5ff84"
    public static func line(_ entry: Entry) -> String {
        let date = (entry.date ?? .now).formatted(.iso8601)
        let message = entry.message.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(date) \(entry.level.tag) [\(entry.source)] \(message)"
    }

    /// Appends lines to `file`; past `maxBytes` the file moves to <name>.1.log first, so two files at most.
    public static func append(_ lines: [String], to file: URL, maxBytes: Int = 1 << 20) {
        guard !lines.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int), size > maxBytes {
            let old = file.deletingPathExtension().appendingPathExtension("1").appendingPathExtension(file.pathExtension)
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: file, to: old)
        }
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    // MARK: Game log

    /// Reads one line of the engine's output: "Warning: VM: [gml_…] Unknown function …" is a warning from VM,
    /// "GL: Compiling default vertex shader" is info from GL, a line without a tag comes from "Game".
    public static func gameEntry(_ line: String, id: Int) -> Entry {
        var text = Substring(line)
        var level = Level.info
        for (prefix, found) in [("Warning: ", Level.warning), ("WARNING: ", .warning), ("Error: ", .error), ("ERROR: ", .error),
                                ("Fatal: ", .error), ("FATAL: ", .error)] where text.hasPrefix(prefix) {
            level = found
            text = text.dropFirst(prefix.count)
            break
        }
        var source = "Game"
        if let colon = text.firstIndex(of: ":"), text.index(after: colon) < text.endIndex, text[text.index(after: colon)] == " " {
            let tag = text[..<colon]
            if (1...12).contains(tag.count), tag.allSatisfy({ $0.isLetter || $0.isNumber }), tag.first?.isUppercase == true {
                source = String(tag)
                text = text[text.index(colon, offsetBy: 2)...]
            }
        }
        if level == .info {
            let lower = text.lowercased()
            if lower.contains("segmentation fault") || lower.contains("crash") || lower.contains("exception") || lower.hasPrefix("failed") {
                level = .error
            }
        }
        return Entry(id: id, date: nil, level: level, source: source, message: String(text))
    }

    /// Every line of a game log as entries, numbered from 1.
    public static func gameEntries(_ text: String) -> [Entry] {
        text.split(separator: "\n", omittingEmptySubsequences: true).enumerated().map { gameEntry(String($1), id: $0 + 1) }
    }

    /// Entries with one of `levels`, whose message or source contains `query` (any case).
    public static func filter(_ entries: [Entry], levels: Set<Level>, query: String) -> [Entry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            levels.contains(entry.level)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query) || entry.source.localizedCaseInsensitiveContains(query))
        }
    }
}
