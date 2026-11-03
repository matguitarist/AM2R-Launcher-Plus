import Foundation
import Testing
@testable import AM2RLauncherPlusKit

struct FolderMoveTests {
    func makeData() throws -> (root: URL, data: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString)", directoryHint: .isDirectory)
        let data = root.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data.appending(path: "Profiles/A/lang"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: data.appending(path: "Saves/A"), withIntermediateDirectories: true)
        try Data(count: 5000).write(to: data.appending(path: "Profiles/A/game.ios"))
        try Data("english.ini".utf8).write(to: data.appending(path: "Profiles/A/lang/languages.txt"))
        try Data("x".utf8).write(to: data.appending(path: "Saves/A/save1"))
        return (root, data)
    }

    @Test func movesEverythingAndRemovesTheOldFolder() throws {
        let (root, data) = try makeData()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = FolderMove.listFiles(in: data)
        let target = root.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let moved = try FolderMove.move(data, into: target)
        #expect(moved.lastPathComponent == "AM2RLauncherPlus")
        #expect(FolderMove.listFiles(in: moved) == before)
        #expect(!FileManager.default.fileExists(atPath: data.path))
        #expect(FolderMove.size(of: moved) == 5000 + 11 + 1)
    }

    @Test func refusesAFolderThatAlreadyHasOne() throws {
        let (root, data) = try makeData()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "Busy", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target.appending(path: "AM2RLauncherPlus"), withIntermediateDirectories: true)
        #expect(throws: FolderMove.Failure.destinationExists("AM2RLauncherPlus")) { try FolderMove.move(data, into: target) }
        #expect(FolderMove.listFiles(in: data).count == 3)
    }

    @Test func refusesToMoveIntoItself() throws {
        let (root, data) = try makeData()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: FolderMove.Failure.insideItself) { try FolderMove.move(data, into: data.appending(path: "Saves")) }
    }

    /// Another disk: set MOVE_VOLUME=/Volumes/<disk> to run the copy-verify-delete path for real.
    @Test func movesToAnotherDisk() throws {
        guard let volume = ProcessInfo.processInfo.environment["MOVE_VOLUME"] else { return }
        let (root, data) = try makeData()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = URL(fileURLWithPath: volume).appending(path: "move-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: target) }
        let before = FolderMove.listFiles(in: data)
        let moved = try FolderMove.move(data, into: target)
        #expect(FolderMove.listFiles(in: moved) == before)
        #expect(!FileManager.default.fileExists(atPath: data.path))
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "AM2RLauncherPlus.partial").path))
    }
}
