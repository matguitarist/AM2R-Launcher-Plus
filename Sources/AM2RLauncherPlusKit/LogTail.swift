import Foundation

/// The end of a game log, for the log sheet (S-006). Big logs show their last lines only;
/// Reveal in Finder gives the whole file.
public enum LogTail {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// True when earlier lines were left out.
        public var truncated: Bool

        public init(text: String, truncated: Bool) {
            self.text = text
            self.truncated = truncated
        }
    }

    public static func read(_ file: URL, maxLines: Int = 5000, maxBytes: Int = 2 << 20) -> Result {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return Result(text: "", truncated: false) }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var truncated = start > 0
        // A cut at a byte offset leaves a partial first line.
        if truncated, !lines.isEmpty { lines.removeFirst() }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
            truncated = true
        }
        return Result(text: lines.joined(separator: "\n"), truncated: truncated)
    }

    /// The newest .log in a folder (names are ISO dates, so they sort by time).
    public static func newest(in folder: URL) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "log" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
    }
}
