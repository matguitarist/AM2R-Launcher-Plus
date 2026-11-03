import Foundation
import Testing
@testable import AM2RLauncherPlusKit

struct LogTailTests {
    func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "log-\(UUID().uuidString).log")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func shortLogIsShownWhole() throws {
        let url = try write("one\ntwo\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LogTail.read(url) == .init(text: "one\ntwo", truncated: false))
    }

    @Test func longLogKeepsTheLastLines() throws {
        let url = try write((1...20).map { "line \($0)" }.joined(separator: "\n") + "\n")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LogTail.read(url, maxLines: 3) == .init(text: "line 18\nline 19\nline 20", truncated: true))
        // Cut by size: the partial first line is dropped.
        let bySize = LogTail.read(url, maxBytes: 20)
        #expect(bySize.truncated && bySize.text == "line 19\nline 20")
    }

    @Test func emptyOrMissingLogIsEmpty() throws {
        let url = try write("")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LogTail.read(url).text.isEmpty)
        #expect(LogTail.read(url.appending(path: "missing")).text.isEmpty)
    }

    @Test func newestLogIsPicked() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["2026-11-01T10-00-00Z.log", "2026-11-03T09-00-00Z.log", "2026-11-02T10-00-00Z.log", "notes.txt"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        #expect(LogTail.newest(in: folder)?.lastPathComponent == "2026-11-03T09-00-00Z.log")
    }
}
