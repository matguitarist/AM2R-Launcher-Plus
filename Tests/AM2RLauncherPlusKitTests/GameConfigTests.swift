import Foundation
import Testing
@testable import AM2RLauncherPlusKit

struct GameConfigTests {
    let sample = "[Screen]\nFullscreen=\"0\"\nScale=\"0\"\n\n[Control]\nEnableXBJoypad=\"1\"\nXBJoypadButtonStart=\"32778\"\nXBJoypadButtonExit=\"32780\"\n\n[Extras]\nController=\"0\"\n"

    @Test func readsValuesAndIgnoresCase() {
        let ini = IniFile(text: sample)
        #expect(ini.value("Scale", in: "Screen") == "0")
        #expect(ini.value("xbjoypadbuttonexit", in: "control") == "32780")
        #expect(ini.value("Scale", in: "Control") == nil)
        #expect(ini.value("Anything", in: "Missing") == nil)
    }

    @Test func changesOnlyTheKeyAsked() {
        var ini = IniFile(text: sample)
        ini.set("Scale", to: "3", in: "Screen")
        #expect(ini.text == sample.replacingOccurrences(of: "Scale=\"0\"", with: "Scale=\"3\""))
    }

    @Test func addsAMissingKeyAtTheEndOfItsSection() {
        var ini = IniFile(text: sample)
        ini.set("Widescreen", to: "1", in: "Screen")
        #expect(ini.text.contains("Scale=\"0\"\nWidescreen=\"1\"\n\n[Control]"))
    }

    @Test func addsAMissingSection() {
        var ini = IniFile(text: sample)
        ini.set("InsanityMode", to: "0", in: "GameplayMenu")
        #expect(ini.text.hasSuffix("Controller=\"0\"\n\n[GameplayMenu]\nInsanityMode=\"0\"\n"))
        var empty = IniFile(text: "")
        empty.set("Fullscreen", to: "1", in: "Screen")
        #expect(empty.text == "[Screen]\nFullscreen=\"1\"\n")
    }

    @Test func keepsWindowsLineEndings() {
        var ini = IniFile(text: sample.replacingOccurrences(of: "\n", with: "\r\n"))
        ini.set("Scale", to: "2", in: "Screen")
        #expect(ini.text.contains("Scale=\"2\"\r\n"))
        #expect(!ini.text.contains("\r\r"))
        #expect(ini.value("Fullscreen", in: "Screen") == "0")
    }

    @Test func macLayoutPutsMapOnSelectAndPauseOnStart() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ini-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        // No config.ini yet: the game hasn't run. The file is created.
        try ControllerLayout.mac.apply(toConfigIn: folder)
        var ini = IniFile(text: try String(contentsOf: folder.appending(path: "config.ini"), encoding: .utf8))
        #expect(ini.value("XBJoypadButtonStart", in: "Control") == "32777")
        #expect(ini.value("XBJoypadButtonExit", in: "Control") == "32778")
        // Back to the game's layout, then custom leaves the file alone.
        ControllerLayout.original.apply(to: &ini)
        #expect(ini.value("XBJoypadButtonStart", in: "Control") == "32778")
        #expect(ini.value("XBJoypadButtonExit", in: "Control") == "32780")
        try ini.text.write(to: folder.appending(path: "config.ini"), atomically: true, encoding: .utf8)
        try ControllerLayout.custom.apply(toConfigIn: folder)
        #expect(try String(contentsOf: folder.appending(path: "config.ini"), encoding: .utf8) == ini.text)
    }
}

struct GameSettingsTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func defaultsBeforeTheGameRanUseTheMacLayout() throws {
        let saves = try folder()
        defer { try? FileManager.default.removeItem(at: saves) }
        let settings = GameSettings.read(from: saves)
        #expect(settings == GameSettings())
        #expect(settings.controller == .mac && settings.scale == 1 && !settings.fullscreen)
    }

    @Test func readsWhatTheGameWroteAndWritesOnlyItsKeys() throws {
        let saves = try folder()
        defer { try? FileManager.default.removeItem(at: saves) }
        let original = "[Screen]\nFullscreen=\"1\"\nScale=\"0\"\nVSync=\"0\"\nLanguage=\"2\"\nWidescreen=\"1\"\n\n[Control]\nXBJoypadButtonStart=\"32778\"\nXBJoypadButtonExit=\"32780\"\nAimStyle=\"1\"\n"
        try original.write(to: GameSettings.configFile(in: saves), atomically: true, encoding: .utf8)
        var settings = GameSettings.read(from: saves)
        #expect(settings.fullscreen && settings.scale == 0 && settings.widescreen && settings.language == 2)
        #expect(settings.controller == .original)
        settings.fullscreen = false
        settings.clampScale()
        #expect(settings.scale == 1)
        settings.controller = .mac
        try settings.write(to: saves)
        let written = try String(contentsOf: GameSettings.configFile(in: saves), encoding: .utf8)
        #expect(written == "[Screen]\nFullscreen=\"0\"\nScale=\"1\"\nVSync=\"0\"\nLanguage=\"2\"\nWidescreen=\"1\"\n\n[Control]\nXBJoypadButtonStart=\"32777\"\nXBJoypadButtonExit=\"32778\"\nAimStyle=\"1\"\n")
        #expect(GameSettings.read(from: saves).controller == .mac)
    }

    @Test func rebindsMadeInTheGameAreCustom() {
        let ini = IniFile(text: "[Control]\nXBJoypadButtonStart=\"32772\"\nXBJoypadButtonExit=\"32778\"\n")
        #expect(ControllerLayout.detect(in: ini) == .custom)
        // The game writes reals; "32777.000000" still counts.
        #expect(ControllerLayout.detect(in: IniFile(text: "[Control]\nXBJoypadButtonStart=\"32777.000000\"\nXBJoypadButtonExit=\"32778\"\n")) == .mac)
    }

    @Test func languagesComeFromTheProfile() throws {
        let profile = try folder()
        defer { try? FileManager.default.removeItem(at: profile) }
        let lang = profile.appending(path: "lang")
        try FileManager.default.createDirectory(at: lang, withIntermediateDirectories: true)
        try "english.ini\r\nfrench.ini\r\nswedish.ini".write(to: lang.appending(path: "languages.txt"), atomically: true, encoding: .utf8)
        try "\u{FEFF}[Header]\nLanguage = \"English\"\n".write(to: lang.appending(path: "english.ini"), atomically: true, encoding: .utf8)
        try "[Header]\r\nLanguage = \"Français\"\r\n".write(to: lang.appending(path: "french.ini"), atomically: true, encoding: .utf8)
        let languages = GameLanguages.list(in: profile)
        #expect(languages.map(\.name) == ["English", "Français", "Swedish"])
        #expect(languages.map(\.index) == [0, 1, 2])
        #expect(GameLanguages.list(in: lang).isEmpty)
    }

    @Test func realProfileLanguages() throws {
        guard let path = ProcessInfo.processInfo.environment["AM2R_PROFILE"] else { return }
        let languages = GameLanguages.list(in: URL(fileURLWithPath: path))
        #expect(languages.first?.name == "English")
        #expect(languages.count >= 10)
    }
}
