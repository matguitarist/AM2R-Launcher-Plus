import FileKit
import Foundation
import Testing
@testable import AM2RLauncherPlusKit

/// The move itself is FileKit's, tested there. These check what is the launcher's own: its database staying in
/// the default data folder, and its words.
struct FolderMoveTests {
    /// The default data folder is also where the database lives (~/Library/Application Support/AM2RLauncherPlus).
    @Test func movingTheDefaultDataFolderLeavesTheDatabaseWhereItIs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data.appending(path: "Saves/A"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: data.appending(path: "Saves/A/save1"))
        let store = data.appending(path: "AM2RLauncherPlus.store")
        try Data("db".utf8).write(to: store)
        let target = root.appending(path: "External", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let keeping = FolderMove.databaseFiles(store: store, in: data)
        #expect(keeping == ["AM2RLauncherPlus.store", "AM2RLauncherPlus.store-shm", "AM2RLauncherPlus.store-wal"])
        let moved = try FolderMove.move(data, into: target, keeping: keeping)
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(!FileManager.default.fileExists(atPath: moved.appending(path: "AM2RLauncherPlus.store").path))
        #expect(FileManager.default.fileExists(atPath: moved.appending(path: "Saves/A/save1").path))
    }

    @Test func failuresSayWhatHappened() {
        #expect(FolderMove.Failure.destinationExists("AM2RLauncherPlus/Saves").message
                == "That folder already has an item named “AM2RLauncherPlus/Saves”. Choose another folder.")
        #expect(FolderMove.Failure.insideItself.message == "Choose a folder outside the current data folder.")
        #expect(FolderMove.Failure.copyFailed("disk full").message == "Unable to copy the data. The old folder is unchanged.")
        #expect(FolderMove.Failure.verifyFailed("Saves/A/save1").message == "The copy doesn't match the original (Saves/A/save1). The old folder is unchanged.")
        #expect(FolderMove.Failure.notEnoughSpace(needed: 2_000_000, available: 1_000_000).message.hasPrefix("Not enough space: the data needs "))
    }
}
