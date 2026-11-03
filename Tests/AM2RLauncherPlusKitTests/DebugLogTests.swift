import Foundation
import Testing
@testable import AM2RLauncherPlusKit

@Test func readsGameLines() {
    let warning = DebugLog.gameEntry(#"Warning: VM: [gml_Script_check_keys] Unknown function "gamepad_set_vibration"!"#, id: 1)
    #expect(warning.level == .warning && warning.source == "VM" && warning.message.hasPrefix("[gml_Script_check_keys]"))
    let gl = DebugLog.gameEntry("GL: Compiling default vertex shader", id: 2)
    #expect(gl.level == .info && gl.source == "GL" && gl.message == "Compiling default vertex shader")
    let plain = DebugLog.gameEntry(#"Loaded "AM2R" (971912648) successfully!"#, id: 3)
    #expect(plain.level == .info && plain.source == "Game")
    let room = DebugLog.gameEntry("Room changed: rm_loading -> titleroom", id: 4)
    #expect(room.source == "Game", "two words before the colon aren't a source")
    let path = DebugLog.gameEntry("Loading /Users/x/Profiles/game.ios...", id: 5)
    #expect(path.source == "Game" && path.message.hasPrefix("Loading /Users"))
    let error = DebugLog.gameEntry("Error: Runner: data.win is damaged", id: 6)
    #expect(error.level == .error && error.source == "Runner")
    #expect(DebugLog.gameEntry("Segmentation fault: 11", id: 7).level == .error)
}

@Test func numbersGameLines() {
    let entries = DebugLog.gameEntries("GL: one\n\nWarning: VM: two\n")
    #expect(entries.map(\.id) == [1, 2] && entries.map(\.level) == [.info, .warning])
}

@Test func filtersByLevelAndSearch() {
    let entries = DebugLog.gameEntries("GL: shader\nWarning: VM: Unknown function\nVM: Reset complete")
    #expect(DebugLog.filter(entries, levels: [.warning], query: "").count == 1)
    #expect(DebugLog.filter(entries, levels: Set(DebugLog.Level.allCases), query: "vm").count == 2)
    #expect(DebugLog.filter(entries, levels: Set(DebugLog.Level.allCases), query: " SHADER ").count == 1)
}

@Test func writesAndRotatesTheLauncherLog() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "debuglog-\(UUID().uuidString)/launcher.log")
    let entry = DebugLog.Entry(id: 1, date: Date(timeIntervalSince1970: 1_793_714_700), level: .warning, source: "Install", message: "two\nlines")
    #expect(DebugLog.line(entry) == "2026-11-03T14:05:00Z WARN [Install] two\n    lines")
    DebugLog.append([DebugLog.line(entry)], to: file, maxBytes: 10)
    DebugLog.append(["second"], to: file, maxBytes: 10)
    #expect(try String(contentsOf: file, encoding: .utf8) == "second\n")
    let old = file.deletingLastPathComponent().appending(path: "launcher.1.log")
    #expect(try String(contentsOf: old, encoding: .utf8).hasPrefix("2026-11-03T14:05:00Z WARN"))
}
