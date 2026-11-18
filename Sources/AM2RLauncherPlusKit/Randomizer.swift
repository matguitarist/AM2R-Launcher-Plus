import Foundation

/// The game's own randomizer options, in modifiers.ini in the profile folder (S-040). The game reads
/// them when it starts (scr_load_mods); its Options > Gameplay menu writes the seed ones (save_modifiers).
///
/// [RandomizerSeed] UseManualSeed, Seed: every randomized new game (Classic Mode, AM2Random, Split
/// Random, Random Game+) uses Seed instead of a random one. [RandomizerSettings] BombRun, PowerBombsRun,
/// ScrewAttackRun: the items Starting Paths may open Area 1 with (Classic Mode > Starting Paths).
public struct RandomizerOptions: Equatable, Sendable {
    public var useCustomSeed = false
    /// The seed as digits; the engine seeds with a 32-bit number.
    public var seed = "0"
    public var bombRun = true
    public var powerBombRun = true
    public var screwAttackRun = true

    public init() {}

    public static let maxSeed: UInt64 = 4_294_967_295

    public static func file(in profileFolder: URL) -> URL { profileFolder.appending(path: "modifiers.ini") }

    /// Keys the launcher writes, by section; a profile update carries them over (`carryOver`).
    static let keys: [(section: String, key: String)] = [
        ("RandomizerSeed", "UseManualSeed"), ("RandomizerSeed", "Seed"),
        ("RandomizerSettings", "BombRun"), ("RandomizerSettings", "PowerBombsRun"), ("RandomizerSettings", "ScrewAttackRun"),
    ]

    public init(ini: IniFile) {
        func flag(_ key: String, _ section: String, _ standard: Bool) -> Bool {
            ini.value(key, in: section).flatMap(Double.init).map { $0 != 0 } ?? standard
        }
        useCustomSeed = flag("UseManualSeed", "RandomizerSeed", false)
        seed = Self.cleanSeed(ini.value("Seed", in: "RandomizerSeed") ?? "0")
        bombRun = flag("BombRun", "RandomizerSettings", true)
        powerBombRun = flag("PowerBombsRun", "RandomizerSettings", true)
        screwAttackRun = flag("ScrewAttackRun", "RandomizerSettings", true)
    }

    public func apply(to ini: inout IniFile) {
        ini.set("UseManualSeed", to: useCustomSeed ? "1" : "0", in: "RandomizerSeed")
        ini.set("Seed", to: Self.cleanSeed(seed), in: "RandomizerSeed")
        ini.set("BombRun", to: bombRun ? "1" : "0", in: "RandomizerSettings")
        ini.set("PowerBombsRun", to: powerBombRun ? "1" : "0", in: "RandomizerSettings")
        ini.set("ScrewAttackRun", to: screwAttackRun ? "1" : "0", in: "RandomizerSettings")
    }

    /// The options in a profile, or nil when it has no modifiers.ini (mods built on AM2R 1.1).
    public static func read(from profileFolder: URL) -> RandomizerOptions? {
        guard let text = try? String(contentsOf: file(in: profileFolder), encoding: .utf8) else { return nil }
        return RandomizerOptions(ini: IniFile(text: text))
    }

    public func write(to profileFolder: URL) throws {
        let url = Self.file(in: profileFolder)
        var ini = IniFile(text: try String(contentsOf: url, encoding: .utf8))
        apply(to: &ini)
        try ini.text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Starting Paths needs an item to start with; the game's list would be empty with all three off.
    public var hasStartingPath: Bool { bombRun || powerBombRun || screwAttackRun }

    /// Digits only, at most the engine's largest seed, no leading zeros: "0042" is 42, "1.5e3" is 1500,
    /// the game's "0000000000" is 0. Anything else becomes 0.
    public static func cleanSeed(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isASCIIDigit) {
            let digits = trimmed.drop { $0 == "0" }
            if digits.isEmpty { return "0" }
            return digits.count > 10 || UInt64(digits)! > maxSeed ? String(maxSeed) : String(digits)
        }
        guard let number = Double(trimmed), number.isFinite, number >= 0 else { return "0" }
        return String(UInt64(min(number.rounded(.down), Double(maxSeed))))
    }

    /// Copies the randomizer keys of an old profile folder into a rebuilt one, so an update keeps the
    /// player's seed and Starting Paths. Keys the old file doesn't have stay as the new file has them.
    public static func carryOver(from oldFolder: URL, to newFolder: URL) throws {
        guard let oldText = try? String(contentsOf: file(in: oldFolder), encoding: .utf8),
              let newText = try? String(contentsOf: file(in: newFolder), encoding: .utf8) else { return }
        let old = IniFile(text: oldText)
        var new = IniFile(text: newText)
        for (section, key) in keys {
            if let value = old.value(key, in: section), new.value(key, in: section) != value { new.set(key, to: value, in: section) }
        }
        if new.text != newText { try new.text.write(to: file(in: newFolder), atomically: true, encoding: .utf8) }
    }
}

/// How a save slot's game was randomized, read from the slot (sv6_randomizer, sv6_add_seed).
public struct RandomizedGame: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// global.gamemode 3: Classic Mode (Power-ups Only or Starting Paths)
        case classic
        /// 4
        case am2Random
        /// 5
        case splitRandom
        /// mod_purerandombool set by another mode
        case randomGamePlus
        case other

        public var title: String {
            switch self {
            case .classic: "Classic Mode"
            case .am2Random: "AM2Random"
            case .splitRandom: "Split Random"
            case .randomGamePlus: "Random Game+"
            case .other: "Randomized"
            }
        }
    }

    public var mode: Mode
    public var seed: String

    public init(mode: Mode, seed: String) {
        self.mode = mode
        self.seed = seed
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
