import Foundation
import LogKit
import Testing
@testable import AM2RLauncherPlusKit

private func game(_ line: String) throws -> ParsedLine { try #require(DebugLog.gameLine(Substring(line))) }

@Test func readsGameLines() throws {
    let warning = try game(#"Warning: VM: [gml_Script_check_keys] Unknown function "gamepad_set_vibration"!"#)
    #expect(warning.level == .warning && warning.source == "VM" && warning.message.hasPrefix("[gml_Script_check_keys]"))
    let gl = try game("GL: Compiling default vertex shader")
    #expect(gl.level == .info && gl.source == "GL" && gl.message == "Compiling default vertex shader")
    let plain = try game(#"Loaded "AM2R" (971912648) successfully!"#)
    #expect(plain.level == .info && plain.source == "Game")
    let room = try game("Room changed: rm_loading -> titleroom")
    #expect(room.source == "Game", "two words before the colon aren't a source")
    let path = try game("Loading /Users/x/Profiles/game.ios...")
    #expect(path.source == "Game" && path.message.hasPrefix("Loading /Users"))
    let error = try game("Error: Runner: data.win is damaged")
    #expect(error.level == .error && error.source == "Runner")
    #expect(try game("Segmentation fault: 11").level == .error)
    #expect(try game("FATAL: Runner: out of memory").level == .critical)
    #expect(DebugLog.gameLine("") == nil)
}

@Test func parsesAGameLog() {
    let document = DebugLog.gameParser.parse("GL: one\n\nWarning: VM: two\r\n")
    #expect(document.entries.map(\.level) == [.info, .warning])
    #expect(document.entries.map(\.message) == ["one", "two"])
    #expect(document.entries.allSatisfy { $0.time == nil })
}

@Test func writesAndRotatesTheLauncherLog() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "debuglog-\(UUID().uuidString)/launcher.log")
    let line = DebugLog.line(date: Date(timeIntervalSince1970: 1_793_714_700), level: .warning, source: "Install", message: "two\nlines")
    #expect(line == "2026-11-03T14:05:00Z WARN [Install] two\n    lines")
    DebugLog.append([line], to: file, maxBytes: 10)
    DebugLog.append(["second"], to: file, maxBytes: 10)
    #expect(try String(contentsOf: file, encoding: .utf8) == "second\n")
    let old = file.deletingLastPathComponent().appending(path: "launcher.1.log")
    #expect(try String(contentsOf: old, encoding: .utf8).hasPrefix("2026-11-03T14:05:00Z WARN"))
}

@Test func launcherLevelsMapToTheViewer() {
    #expect(DebugLog.Level.allCases.map(\.logLevel) == [.debug, .info, .warning, .error])
}
