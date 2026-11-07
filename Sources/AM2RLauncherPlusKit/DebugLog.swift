import Foundation
import LogKit

/// The Log page's two logs: the launcher's own events (launcher.log), and the game's output read back from its log.
public enum DebugLog {
    public enum Level: Int, CaseIterable, Comparable, Sendable, Codable {
        case debug, info, warning, error

        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        /// The word in launcher.log.
        var tag: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERROR"
            }
        }

        /// The level in the viewer.
        public var logLevel: LogLevel {
            switch self {
            case .debug: .debug
            case .info: .info
            case .warning: .warning
            case .error: .error
            }
        }
    }

    // MARK: launcher.log

    /// "2026-11-03T14:05:00Z INFO [Install] Downloaded patch data 7e5ff84"
    public static func line(date: Date, level: Level, source: String, message: String) -> String {
        let message = message.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(date.formatted(.iso8601)) \(level.tag) [\(source)] \(message)"
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

    /// The game log for the viewer: one entry per line, without times (the game doesn't write them).
    public static let gameParser = LineLogParser(parseLine: gameLine)

    /// Reads one line of the engine's output: "Warning: VM: [gml_…] Unknown function …" is a warning from VM,
    /// "GL: Compiling default vertex shader" is info from GL, a line without a tag comes from "Game".
    /// Nil for an empty line.
    @Sendable public static func gameLine(_ line: Substring) -> ParsedLine? {
        guard !line.isEmpty else { return nil }
        var text = line
        var level = LogLevel.info
        for (prefix, found) in [("Warning: ", LogLevel.warning), ("WARNING: ", .warning), ("Error: ", .error), ("ERROR: ", .error),
                                ("Fatal: ", .critical), ("FATAL: ", .critical)] where text.hasPrefix(prefix) {
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
        return ParsedLine(level: level, source: source, message: String(text))
    }
}
