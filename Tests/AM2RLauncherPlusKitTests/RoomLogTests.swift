import Foundation
import LogKit
import Testing
@testable import AM2RLauncherPlusKit

@Test func roomNamesComeFromTheRoomChunk() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "rooms-\(UUID().uuidString).ios")
    defer { try? FileManager.default.removeItem(at: file) }
    try GameData.sample(roomNames: ["rm_splash", "titleroom", "rm_a0h01"]).write(to: file)
    #expect(GameData.roomNames(of: file) == ["rm_splash", "titleroom", "rm_a0h01"])
    try GameData.sample(roomNames: ["initroom", "titleroom"], gameID: 971_912_648).write(to: file)
    #expect(GameData.roomNames(of: file) == ["initroom", "titleroom"])
    #expect(GameSave.gameID(of: file) == 971_912_648)
    try Data("not a game".utf8).write(to: file)
    #expect(GameData.roomNames(of: file).isEmpty)
}

@Test func roomLogLinesReadAsTheGameWritesThem() {
    let names = ["rm_splash", "titleroom", "rm_a0h01"]
    #expect(RoomLog.line("November 18th 2026, 14:03.22: Loading Room 2", roomNames: names)
        == ParsedLine(time: "14:03:22", level: .info, source: "Rooms", message: "Entered rm_a0h01 (2)"))
    #expect(RoomLog.line("November 18th 2026, 14:03.21: UnLoading Room 1\r", roomNames: names)
        == ParsedLine(time: "14:03:21", level: .debug, source: "Rooms", message: "Left titleroom (1)"))
    #expect(RoomLog.line("November 18th 2026, 14:03.22: Loading Room 400", roomNames: names)?.message == "Entered room 400")
    #expect(RoomLog.line("November 1st 2026, 09:00.00: Resetting 3,4", roomNames: [])?.level == .debug)
    #expect(RoomLog.line("November 1st 2026, 09:00.00: Reset map start", roomNames: [])?.source == "Map")
    #expect(RoomLog.line("November 1st 2026, 09:00.00: Options Loaded", roomNames: [])
        == ParsedLine(time: "09:00:00", level: .info, source: "Game", message: "Options Loaded"))
    #expect(RoomLog.line("  ", roomNames: []) == nil)
}

@Test func writeLogIsTheDebugKeyOfConfigIni() throws {
    let saves = FileManager.default.temporaryDirectory.appending(path: "roomlog-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: saves) }
    #expect(!RoomLog.isOn(saves: saves))
    try RoomLog.set(true, saves: saves)
    #expect(RoomLog.isOn(saves: saves))
    try "[Screen]\r\nFullscreen=\"1\"\r\n".write(to: saves.appending(path: "config.ini"), atomically: true, encoding: .utf8)
    try RoomLog.set(true, saves: saves)
    let text = try String(contentsOf: saves.appending(path: "config.ini"), encoding: .utf8)
    #expect(text == "[Screen]\r\nFullscreen=\"1\"\r\n\r\n[Debug]\r\nWriteLog=\"1\"\r\n")
    try RoomLog.set(false, saves: saves)
    #expect(!RoomLog.isOn(saves: saves))
}
