import Foundation

/// Reads and edits AM2R's config.ini (GameMaker ini: [Section] then Key="value"),
/// changing only the keys asked for and keeping every other line as it was (S-010 to S-012).
public struct IniFile: Equatable, Sendable {
    public private(set) var lines: [String]
    /// Kept from the file, so an edit doesn't rewrite every line ending.
    private let newline: String

    public init(text: String) {
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        lines = text.isEmpty ? [] : text.components(separatedBy: "\n").map {
            // "\r\n" is one Character in Swift, so trim the code unit, not the Character.
            $0.utf16.last == 13 ? String($0.utf16.dropLast())! : $0
        }
        while lines.last == "" { lines.removeLast() }
    }

    public var text: String { lines.joined(separator: newline) + newline }

    public func value(_ key: String, in section: String) -> String? {
        guard let range = range(of: section) else { return nil }
        for line in lines[range] {
            if let (k, v) = Self.split(line), k.caseInsensitiveCompare(key) == .orderedSame { return v }
        }
        return nil
    }

    public mutating func set(_ key: String, to value: String, in section: String) {
        let line = "\(key)=\"\(value)\""
        guard let range = range(of: section) else {
            if !lines.isEmpty { lines.append("") }
            lines.append("[\(section)]")
            lines.append(line)
            return
        }
        for index in range {
            if let (k, _) = Self.split(lines[index]), k.caseInsensitiveCompare(key) == .orderedSame {
                lines[index] = line
                return
            }
        }
        // Add after the section's last key, before any blank lines that separate it from the next one.
        var insertAt = range.upperBound
        while insertAt > range.lowerBound, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertAt -= 1 }
        lines.insert(line, at: insertAt)
    }

    /// The lines after "[section]" up to the next section header.
    private func range(of section: String) -> Range<Int>? {
        guard let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("[\(section)]") == .orderedSame }) else { return nil }
        var end = header + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
        return (header + 1)..<end
    }

    private static func split(_ line: String) -> (String, String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
        return key.isEmpty ? nil : (key, value)
    }
}

/// Gamepad layouts for AM2R's Xbox-style joypad settings (S-011).
/// GameMaker constants: gp_select = 32777, gp_start = 32778, gp_stickr = 32780.
public enum ControllerLayout: String, CaseIterable, Codable, Sendable {
    /// Select opens the map, Start opens the pause menu. The game has no controller binding for its
    /// pause menu (only Escape opens it), so the engine also presses Escape for Start: `engineKeys`.
    case mac
    /// The game's own default: Start opens the map, right-stick click opens the pause menu.
    case original
    /// The launcher leaves the controls as set in the game.
    case custom

    /// The [Control] keys this layout writes; empty for custom.
    public var keys: [String: String] {
        switch self {
        // Exit quits the game when EnableExitButton is on; it keeps the game's default, away from Start.
        case .mac: ["XBJoypadButtonStart": "32777", "XBJoypadButtonExit": "32780"]
        case .original: ["XBJoypadButtonStart": "32778", "XBJoypadButtonExit": "32780"]
        case .custom: [:]
        }
    }

    /// BUTTERSCOTCH_GAMEPAD_KEYS for the engine (patch 0006): gp_start also presses Escape (key 27).
    public var engineKeys: String? { self == .mac ? "32778=27" : nil }

    public func apply(to ini: inout IniFile) {
        for (key, value) in keys.sorted(by: { $0.key < $1.key }) { ini.set(key, to: value, in: "Control") }
    }

    /// Writes the layout into config.ini in `saveFolder`, creating the file if the game hasn't yet.
    public func apply(toConfigIn saveFolder: URL) throws {
        guard self != .custom else { return }
        let file = saveFolder.appending(path: "config.ini")
        var ini = IniFile(text: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
        apply(to: &ini)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        try ini.text.write(to: file, atomically: true, encoding: .utf8)
    }
}

extension ControllerLayout {
    /// The layout config.ini already has. Mac is told by the map button alone, so a profile from an
    /// earlier launcher build (Exit on Start) still counts; Original needs both keys; else custom.
    public static func detect(in ini: IniFile) -> ControllerLayout {
        func value(_ key: String) -> Double? { ini.value(key, in: "Control").flatMap(Double.init) }
        if value("XBJoypadButtonStart") == 32777 { return .mac }
        if ControllerLayout.original.keys.allSatisfy({ value($0.key) == Double($0.value) }) { return .original }
        return .custom
    }
}

/// The button pictures in the game's hints: [Extras] Controller, the game's Extras > Controller Tips (S-034).
public enum ButtonPrompts: Int, CaseIterable, Codable, Sendable {
    case xbox = 0, playStation = 1, nintendo = 2, coloredSNES = 3, moga = 4, ouya = 5

    public var title: String {
        switch self {
        case .xbox: "Xbox"
        case .playStation: "PlayStation"
        case .nintendo: "Nintendo"
        case .coloredSNES: "Colored SNES"
        case .moga: "MOGA"
        case .ouya: "OUYA"
        }
    }

    /// The set for a controller, from GCController's productCategory ("DualSense", "Switch Pro Controller", "Xbox One"…).
    public static func matching(productCategory: String) -> ButtonPrompts {
        let name = productCategory.lowercased()
        if ["dualshock", "dualsense", "playstation"].contains(where: name.contains) { return .playStation }
        if ["switch", "joy-con", "nintendo"].contains(where: name.contains) { return .nintendo }
        return .xbox
    }
}

/// The settings the launcher shows for a profile, read from and written to its config.ini (S-010 to S-012).
/// Values and limits follow the game's own options menu (oOptionsDisplay):
/// windowed, Scale 1-4 is the window size (320 x 240 times Scale, 0 counts as 1);
/// fullscreen, Scale 0 stretches and 1-4 scales by whole pixels.
public struct GameSettings: Equatable, Sendable {
    public var fullscreen = false
    public var scale = 1
    public var widescreen = false
    /// Index into lang/languages.txt.
    public var language = 0
    public var controller = ControllerLayout.mac
    /// [Extras], with the game's defaults when a key is missing (S-034, S-035).
    public var buttonPrompts = ButtonPrompts.xbox
    public var showTimer = false
    public var lowHealthAlarm = true
    public var earlyBaby = false
    public var extremeLabMetroids = false

    public init() {}

    public static let scales = 1...4
    public static let fullscreenScales = 0...4

    public init(ini: IniFile) {
        func int(_ key: String) -> Int { ini.value(key, in: "Screen").flatMap(Double.init).map { Int($0) } ?? 0 }
        fullscreen = int("Fullscreen") != 0
        scale = int("Scale")
        widescreen = int("Widescreen") != 0
        language = max(0, int("Language"))
        controller = ControllerLayout.detect(in: ini)
        func extra(_ key: String, _ fallback: Int) -> Int { ini.value(key, in: "Extras").flatMap(Double.init).map { Int($0) } ?? fallback }
        buttonPrompts = ButtonPrompts(rawValue: extra("Controller", 0)) ?? .xbox
        showTimer = extra("DisplayIGT", 0) != 0
        lowHealthAlarm = extra("LowHealthWarning", 1) != 0
        earlyBaby = extra("EarlyBaby", 0) != 0
        extremeLabMetroids = extra("ExtremeLabMonsters", 0) != 0
        clampScale()
    }

    /// Keeps Scale in the range the game's menu offers for the current mode.
    public mutating func clampScale() {
        let range = fullscreen ? Self.fullscreenScales : Self.scales
        scale = min(max(scale, range.lowerBound), range.upperBound)
    }

    public func apply(to ini: inout IniFile) {
        ini.set("Fullscreen", to: fullscreen ? "1" : "0", in: "Screen")
        ini.set("Scale", to: String(scale), in: "Screen")
        ini.set("Widescreen", to: widescreen ? "1" : "0", in: "Screen")
        ini.set("Language", to: String(language), in: "Screen")
        controller.apply(to: &ini)
        // An extra still at the game's default and not in the file yet stays out of it.
        func extra(_ key: String, _ value: Int, default fallback: Int) {
            if value != fallback || ini.value(key, in: "Extras") != nil { ini.set(key, to: String(value), in: "Extras") }
        }
        extra("Controller", buttonPrompts.rawValue, default: 0)
        extra("DisplayIGT", showTimer ? 1 : 0, default: 0)
        extra("LowHealthWarning", lowHealthAlarm ? 1 : 0, default: 1)
        extra("EarlyBaby", earlyBaby ? 1 : 0, default: 0)
        extra("ExtremeLabMonsters", extremeLabMetroids ? 1 : 0, default: 0)
    }

    // MARK: Files

    public static func configFile(in saveFolder: URL) -> URL { saveFolder.appending(path: "config.ini") }

    /// The settings in a save folder; defaults (with the Mac controller layout) when the game hasn't run yet.
    public static func read(from saveFolder: URL) -> GameSettings {
        guard let text = try? String(contentsOf: configFile(in: saveFolder), encoding: .utf8) else { return GameSettings() }
        return GameSettings(ini: IniFile(text: text))
    }

    /// Whether the game wrote its own config.ini. AM2R 1.1, and the mods built on it, write one only
    /// when none exists and read every key missing from it as a wrong value (button A = 7, Start = 19),
    /// so the launcher must never create a partial one for them.
    public static func gameHasWritten(in saveFolder: URL) -> Bool {
        guard let text = try? String(contentsOf: configFile(in: saveFolder), encoding: .utf8) else { return false }
        return IniFile(text: text).value("SoundVolume", in: "Sound") != nil
    }

    /// Whether a gamepad button holds a value no AM2R writes (GameMaker's are 32769 and up). An AM2R 1.1
    /// mod saves that after it started on a partial config.ini, and with it sound effects off and more.
    public static func hasBrokenGamepadButtons(in saveFolder: URL) -> Bool {
        guard let text = try? String(contentsOf: configFile(in: saveFolder), encoding: .utf8) else { return false }
        let ini = IniFile(text: text)
        return ["A", "B", "X", "L", "L2", "R", "R2", "Select", "Start", "MenuOK", "MenuCancel"].contains { button in
            ini.value("XBJoypadButton" + button, in: "Control").flatMap(Double.init).map { $0 < 32769 } ?? false
        }
    }

    /// Removes a config.ini that holds only the launcher's keys, or that a mod saved from one,
    /// so the game writes a clean one on its next start. Returns whether it removed one.
    @discardableResult
    public static func removeLauncherOnlyConfig(in saveFolder: URL) -> Bool {
        let file = configFile(in: saveFolder)
        guard FileManager.default.fileExists(atPath: file.path),
              !gameHasWritten(in: saveFolder) || hasBrokenGamepadButtons(in: saveFolder) else { return false }
        return (try? FileManager.default.removeItem(at: file)) != nil
    }

    /// Writes only the launcher's keys; every other line of config.ini stays as the game wrote it.
    public func write(to saveFolder: URL) throws {
        let file = Self.configFile(in: saveFolder)
        var ini = IniFile(text: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
        apply(to: &ini)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        try ini.text.write(to: file, atomically: true, encoding: .utf8)
    }
}

/// The game languages a profile ships (S-012): lang/languages.txt lists the files, in the
/// order config.ini's Language index uses; each file's [Header] Language is its name.
public enum GameLanguages {
    public struct Language: Equatable, Sendable, Identifiable {
        public var index: Int
        public var file: String
        public var name: String
        public var id: Int { index }
    }

    public static func list(in profileFolder: URL) -> [Language] {
        let lang = profileFolder.appending(path: "lang", directoryHint: .isDirectory)
        guard let text = try? String(contentsOf: lang.appending(path: "languages.txt"), encoding: .utf8) else { return [] }
        let files = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return files.enumerated().map { index, file in
            let ini = (try? String(contentsOf: lang.appending(path: file), encoding: .utf8)).map { IniFile(text: $0.replacingOccurrences(of: "\u{FEFF}", with: "")) }
            let name = ini?.value("Language", in: "Header").flatMap { $0.isEmpty ? nil : $0 }
                ?? file.replacingOccurrences(of: ".ini", with: "").capitalized
            return Language(index: index, file: file, name: name)
        }
    }
}

/// A look drawn over the game by the engine (patch 0007). Not in config.ini: the game doesn't know about it.
public enum DisplayFilter: String, CaseIterable, Codable, Sendable {
    case none, scanlines, crt

    public var title: String {
        switch self {
        case .none: "None"
        case .scanlines: "Scanlines"
        case .crt: "CRT"
        }
    }

    /// BUTTERSCOTCH_FILTER and BUTTERSCOTCH_FILTER_LINES for the engine; empty for none.
    /// AM2R is 240 pixels tall, so each game row gets one scanline.
    public var engineEnvironment: [String: String] {
        self == .none ? [:] : ["BUTTERSCOTCH_FILTER": rawValue, "BUTTERSCOTCH_FILTER_LINES": "240"]
    }
}
