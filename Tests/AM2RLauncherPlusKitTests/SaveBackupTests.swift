import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private func folder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "backup-\(UUID().uuidString)/\(name)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }
private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

@Test func backupZipsTheSaveFolderWithADate() throws {
    let saves = try folder("Saves/one")
    try write("[Screen]\n", saves.appending(path: "config.ini"))
    try write("slot 1", saves.appending(path: "save1"))
    let backups = saves.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 14, minute: 5))!
    let zip = try SaveBackup.backup(saves: saves, into: backups, profileName: "CU 1.5.5", date: date)
    #expect(zip.lastPathComponent == "CU 1.5.5 – 2026-11-03 14-05.zip")
    let again = try SaveBackup.backup(saves: saves, into: backups, profileName: "CU 1.5.5", label: "before restore", date: date)
    #expect(again.lastPathComponent == "CU 1.5.5 – 2026-11-03 14-05 (before restore).zip")
    let third = try SaveBackup.backup(saves: saves, into: backups, profileName: "CU 1.5.5", date: date)
    #expect(third.lastPathComponent == "CU 1.5.5 – 2026-11-03 14-05 2.zip")
    #expect(SaveBackup.list(in: backups).count == 3)
    #expect(SaveBackup.list(in: backups).allSatisfy { $0.size > 0 })
}

@Test func restoreReplacesTheSaves() throws {
    let saves = try folder("Saves/one")
    try write("[Screen]\n", saves.appending(path: "config.ini"))
    try write("slot 1", saves.appending(path: "save1"))
    let backups = saves.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
    let zip = try SaveBackup.backup(saves: saves, into: backups, profileName: "CU")
    try write("slot 1 later", saves.appending(path: "save1"))
    try write("slot 2", saves.appending(path: "save2"))
    try SaveBackup.restore(zip, into: saves)
    #expect(read(saves.appending(path: "save1")) == "slot 1")
    #expect(read(saves.appending(path: "config.ini")) == "[Screen]\n")
    #expect(!FileManager.default.fileExists(atPath: saves.appending(path: "save2").path))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: saves.deletingLastPathComponent().path).filter { $0.hasPrefix("one.") }
    #expect(leftovers.isEmpty)
}

@Test func restoreAcceptsAZippedSaveFolder() throws {
    let dir = try folder("zipped")
    let original = dir.appending(path: "com.yoyogames.am2r", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    try write("old mac save", original.appending(path: "save1"))
    let zip = dir.appending(path: "saves.zip")
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--keepParent", original.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    let saves = try folder("Saves/two")
    try SaveBackup.restore(zip, into: saves)
    #expect(read(saves.appending(path: "save1")) == "old mac save")
}

@Test func aZipWithoutSavesChangesNothing() throws {
    let dir = try folder("other")
    try write("hello", dir.appending(path: "notes.txt"))
    let zip = dir.deletingLastPathComponent().appending(path: "notes.zip")
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", dir.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    let saves = try folder("Saves/three")
    try write("keep", saves.appending(path: "save1"))
    #expect(throws: SaveBackup.Failure.notABackup) { try SaveBackup.restore(zip, into: saves) }
    #expect(read(saves.appending(path: "save1")) == "keep")
    let empty = try folder("Saves/empty")
    #expect(throws: SaveBackup.Failure.noSaves) { try SaveBackup.backup(saves: empty, into: dir, profileName: "x") }
}
