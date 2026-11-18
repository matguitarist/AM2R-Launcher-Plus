import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let gameID: UInt32 = 971_912_648

private func folders() throws -> (saves: URL, game: URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: "GameUnlocksTests-\(UUID().uuidString)")
    let saves = root.appending(path: "saves")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    let game = root.appending(path: "game.ios")
    try GameSave.sampleGameData(gameID: gameID).write(to: game)
    return (saves, game)
}

@Test func unlockEverythingMakesBothFilesTheGameReads() throws {
    let (saves, game) = try folders()
    #expect(!GameUnlocks.isEverythingUnlocked(saves: saves, game: game))
    try GameUnlocks.unlockEverything(saves: saves, game: game)
    #expect(GameUnlocks.isEverythingUnlocked(saves: saves, game: game))

    let data = try GameUnlocks.read(saves.appending(path: "data.sav"), gameID: gameID, lists: 4)
    #expect(data.map(\.values.count) == [50, 50, 100, 100])
    #expect(data[0].values.prefix(4) == [.real(1), .real(1), .real(1), .real(0)])
    #expect(data[1].values.prefix(4) == [.real(1), .real(1), .real(1), .real(0)])
    let extras = try GameUnlocks.read(saves.appending(path: "extras.sav"), gameID: gameID, lists: 1)
    #expect(extras[0].values.count == 20)
    #expect(extras[0].values.first == .real(1))
}

@Test func unlockEverythingKeepsStatsAndAchievements() throws {
    let (saves, game) = try folders()
    var stats = DSList.empty, other = DSList.empty
    stats.values = Array(repeating: .real(7), count: 100)
    other.values = Array(repeating: .real(0), count: 50)
    let file = saves.appending(path: "data.sav")
    try GameUnlocks.encrypted([other, other, stats, stats], gameID: gameID).write(to: file)
    try GameUnlocks.unlockEverything(saves: saves, game: game)
    let data = try GameUnlocks.read(file, gameID: gameID, lists: 4)
    #expect(data[2].values == stats.values)
    #expect(data[3].values == stats.values)
    #expect(data[0].values[0] == .real(1))
}

@Test func unlockEverythingRefusesAFileItCantRead() throws {
    let (saves, game) = try folders()
    try Data("not a save".utf8).write(to: saves.appending(path: "extras.sav"))
    #expect(throws: GameUnlocks.Failure.notASave) { try GameUnlocks.unlockEverything(saves: saves, game: game) }
    #expect(!FileManager.default.fileExists(atPath: saves.appending(path: "data.sav").path))
}
