import Foundation
import Testing
@testable import AM2RLauncherPlusKit

/// modifiers.ini as Community Updates 1.5.5 ships it, cut to the randomizer sections and one more.
private let shipped = """
[RandomizerSeed]\r
Defaults = "0, 0"\r
Ex = "Used to force randomizer to use a specific seed instead of a random seed."\r
UseManualSeed = 0\r
Seed = 0000000000\r
\r
[RandomizerSettings]\r
Defaults = "1, 1, 1, 1"\r
BombRun = 1\r
PowerBombsRun = 1\r
ScrewAttackRun = 1\r
\r
[ETankHealth]\r
Multiplier = 1\r

"""

@Test func randomizerOptionsReadTheShippedFileAsTheGameDoes() {
    let options = RandomizerOptions(ini: IniFile(text: shipped))
    #expect(options == RandomizerOptions())
    #expect(options.seed == "0")
    #expect(options.hasStartingPath)
}

@Test func randomizerOptionsWriteOnlyTheirKeys() {
    var options = RandomizerOptions()
    options.useCustomSeed = true
    options.seed = "123456"
    options.screwAttackRun = false
    var ini = IniFile(text: shipped)
    options.apply(to: &ini)
    #expect(RandomizerOptions(ini: ini) == options)
    #expect(ini.value("Multiplier", in: "ETankHealth") == "1")
    #expect(ini.value("Ex", in: "RandomizerSeed") == "Used to force randomizer to use a specific seed instead of a random seed.")
    #expect(ini.text.contains("\r\n"))
    #expect(ini.lines.count == IniFile(text: shipped).lines.count)
}

@Test func seedsAreDigitsTheEngineCanUse() {
    #expect(RandomizerOptions.cleanSeed("0000000000") == "0")
    #expect(RandomizerOptions.cleanSeed("0042") == "42")
    #expect(RandomizerOptions.cleanSeed(" 3390671227 ") == "3390671227")
    #expect(RandomizerOptions.cleanSeed("1500.000000") == "1500")
    #expect(RandomizerOptions.cleanSeed("99999999999") == "4294967295")
    #expect(RandomizerOptions.cleanSeed("-5") == "0")
    #expect(RandomizerOptions.cleanSeed("samus") == "0")
}

@Test func noStartingPathWhenAllThreeAreOff() {
    var options = RandomizerOptions()
    options.bombRun = false
    options.powerBombRun = false
    #expect(options.hasStartingPath)
    options.screwAttackRun = false
    #expect(!options.hasStartingPath)
}

@Test func anUpdateCarriesTheRandomizerKeysOver() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "randomizer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appending(path: "old"), new = root.appending(path: "new")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
    var options = RandomizerOptions()
    options.useCustomSeed = true
    options.seed = "777"
    options.bombRun = false
    var oldIni = IniFile(text: shipped)
    options.apply(to: &oldIni)
    oldIni.set("Multiplier", to: "0.5", in: "ETankHealth")
    try oldIni.text.write(to: RandomizerOptions.file(in: old), atomically: true, encoding: .utf8)
    try shipped.write(to: RandomizerOptions.file(in: new), atomically: true, encoding: .utf8)

    try RandomizerOptions.carryOver(from: old, to: new)
    #expect(RandomizerOptions.read(from: new) == options)
    // Only the randomizer keys move; the new version's other values stay.
    let newIni = IniFile(text: try String(contentsOf: RandomizerOptions.file(in: new), encoding: .utf8))
    #expect(newIni.value("Multiplier", in: "ETankHealth") == "1")
    // No modifiers.ini (a mod built on AM2R 1.1): nothing to read, nothing to carry.
    #expect(RandomizerOptions.read(from: root) == nil)
    try RandomizerOptions.carryOver(from: root, to: new)
}

@Test func aSaveTellsItsRandomizerModeAndSeed() throws {
    let id: UInt32 = 971_912_648
    func game(_ data: Data) throws -> RandomizedGame? { try GameSave(decrypting: data, gameID: id).randomizedGame }
    #expect(try game(GameSave.sampleRandomized(gameID: id, gameMode: 4, seed: "3390671227")) == RandomizedGame(mode: .am2Random, seed: "3390671227"))
    #expect(try game(GameSave.sampleRandomized(gameID: id, gameMode: 3, seed: "42")) == RandomizedGame(mode: .classic, seed: "42"))
    #expect(try game(GameSave.sampleRandomized(gameID: id, gameMode: 5, seed: "7")) == RandomizedGame(mode: .splitRandom, seed: "7"))
    // A normal game, and a save whose randomizer list is too short to tell, aren't randomized.
    #expect(try game(GameSave.sampleRandomized(gameID: id, gameMode: 0, seed: "9")) == nil)
    #expect(try game(GameSave.sample(gameID: id)) == nil)
}
