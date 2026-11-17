import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private func makeSave(gameID: UInt32 = 971_912_648, inventory: [DSList.Value]? = nil) -> Data {
    GameSave.sample(gameID: gameID, inventory: inventory)
}

@Test func cryptIsItsOwnInverseAndSkipsBytesByFileSize() {
    let plain = Data((0..<30_000).map { UInt8($0 % 251) })
    let scrambled = GameSave.crypt(plain, gameID: 971_912_648)
    #expect(scrambled != plain)
    #expect(GameSave.crypt(scrambled, gameID: 971_912_648) == plain)
    // 30000 bytes: rate = round(2 * 3) = 6, so only every 7th byte changes.
    #expect(zip(plain, scrambled).enumerated().allSatisfy { $0.offset.isMultiple(of: 7) || $0.element.0 == $0.element.1 })
}

@Test func dsListReadsAndWritesEveryValueKind() throws {
    var list = try #require(DSList(hex: "2F01000000000000"))
    list.values = [.real(1.5), .string(Data("hi".utf8)), .array([.int32(-1)]), .pointer(9), .undefined, .int32(7), .int64(-8), .bool(1)]
    let again = try #require(DSList(hex: list.hex))
    #expect(again.values == list.values)
    #expect(again.hex == list.hex)
    #expect(DSList(hex: "2F010000") == nil)
    #expect(DSList(hex: "2F0100000100000063000000") == nil)
}

@Test func aSaveReadsAndWritesBackByteForByte() throws {
    let data = makeSave()
    let save = try GameSave(decrypting: data, gameID: 971_912_648)
    #expect(save.encrypted(gameID: 971_912_648) == data)
    #expect(save.value(inventory: 6) == 1)
    #expect(throws: GameSave.Failure.notASave) { try GameSave(decrypting: data, gameID: 1) }
    #expect(throws: GameSave.Failure.notASave) { try GameSave(decrypting: Data("hello".utf8), gameID: 971_912_648) }
}

@Test func abilitiesGiveEveryAbilityBeamAndSuitButNoTanks() throws {
    var save = try GameSave(decrypting: makeSave(), gameID: 971_912_648)
    try save.give(.abilities)
    let again = try GameSave(decrypting: save.encrypted(gameID: 971_912_648), gameID: 971_912_648)
    #expect(again.value(inventory: 0) == 2)
    #expect((1...14).allSatisfy { again.value(inventory: $0) == 1 })
    #expect(again.value(inventory: 15) == 0)
    #expect((0...14).allSatisfy { again.value(items: $0) == 1 })
    #expect(again.value(items: 15) == 0)
    #expect(again.value(main: 4) == 1)
    #expect(again.value(main: 5) == 2)
    #expect(again.value(main: 2) == 10054)
}

@Test func everythingAlsoFillsEveryTank() throws {
    var save = try GameSave(decrypting: makeSave(), gameID: 971_912_648)
    let before = save.lines
    try save.give(.everything)
    #expect(save.value(main: 4) == 10)
    #expect(save.value(main: 5) == 44)
    #expect(save.value(main: 6) == 10)
    #expect(save.value(main: 7) == 10)
    #expect(save.value(main: 3) == 3)
    // Only main, items and inventory change.
    #expect(Set(save.lines.indices.filter { save.lines[$0] != before[$0] }) == [1, 2, 7])
}

@Test func refusesASaveWithTooShortAnInventory() throws {
    var save = try GameSave(decrypting: makeSave(inventory: [.real(0)]), gameID: 971_912_648)
    #expect(throws: GameSave.Failure.notASave) { try save.give(.abilities) }
}

/// AM2R_SAVE=<a copy of a real save> AM2R_GAME=<its game.ios>: reads it, writes it back unchanged,
/// and gives it every upgrade, on a copy in the temporary folder. AM2R_SAVE_EDITED=<path> keeps that
/// copy there, to load in the game.
@Test(.enabled(if: ProcessInfo.processInfo.environment["AM2R_SAVE"] != nil && ProcessInfo.processInfo.environment["AM2R_GAME"] != nil))
func aRealSaveRoundTripsAndTakesUpgrades() throws {
    let env = ProcessInfo.processInfo.environment
    let game = URL(fileURLWithPath: env["AM2R_GAME"]!)
    let gameID = try #require(GameSave.gameID(of: game))
    let original = try Data(contentsOf: URL(fileURLWithPath: env["AM2R_SAVE"]!))
    #expect(try GameSave(decrypting: original, gameID: gameID).encrypted(gameID: gameID) == original)
    let copy = FileManager.default.temporaryDirectory.appending(path: "save1-\(UUID().uuidString)")
    try original.write(to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }
    try GameSave.giveUpgrades(.everything, slot: copy, game: game)
    let edited = try GameSave(decrypting: Data(contentsOf: copy), gameID: gameID)
    #expect(edited.value(inventory: 10) == 1)
    #expect(edited.value(main: 7) == 10)
    if let kept = env["AM2R_SAVE_EDITED"] {
        try? FileManager.default.removeItem(atPath: kept)
        try FileManager.default.copyItem(at: copy, to: URL(fileURLWithPath: kept))
    }
}
