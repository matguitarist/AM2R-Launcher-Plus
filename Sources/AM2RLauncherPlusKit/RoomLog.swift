import Foundation
import LogKit

/// The game's own trace (S-043): with config.ini [Debug] WriteLog=1, AM2R appends to am2r_log.txt in
/// its save folder each room it loads and leaves, map resets and option loads (writelog). Each line is
/// the engine's date_datetime_string, ": ", then the text, e.g. "November 18th 2026, 14:03.22: Loading Room 42".
public enum RoomLog {
    public static func file(in saves: URL) -> URL { saves.appending(path: "am2r_log.txt") }

    /// config.ini [Debug] WriteLog. The game reads it at start (load_gameoptions) and keeps it when it saves options.
    public static func isOn(saves: URL) -> Bool {
        let ini = IniFile(text: (try? String(contentsOf: saves.appending(path: "config.ini"), encoding: .utf8)) ?? "")
        return ini.value("WriteLog", in: "Debug").flatMap(Double.init).map { $0 != 0 } ?? false
    }

    public static func set(_ on: Bool, saves: URL) throws {
        let file = saves.appending(path: "config.ini")
        var ini = IniFile(text: (try? String(contentsOf: file, encoding: .utf8)) ?? "")
        ini.set("WriteLog", to: on ? "1" : "0", in: "Debug")
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try ini.text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Reads am2r_log.txt; `roomNames` turns room numbers into names (GameData.roomNames).
    public static func parser(roomNames: [String]) -> LineLogParser {
        LineLogParser { line(String($0), roomNames: roomNames) }
    }

    /// Room loads are info under Rooms, leaving a room and each map cell reset are debug (hidden at first).
    public static func line(_ text: String, roomNames: [String]) -> ParsedLine? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var time: String?
        var message = Substring(trimmed)
        // The date has no ": " of its own ("14:03.22"), so the first one ends it.
        if let separator = trimmed.range(of: ": ") {
            let date = trimmed[..<separator.lowerBound]
            if let comma = date.lastIndex(of: ",") {
                time = date[date.index(after: comma)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ":")
            }
            message = trimmed[separator.upperBound...]
        }
        func room(_ prefix: String) -> String? {
            guard message.hasPrefix(prefix), let number = Int(message.dropFirst(prefix.count)) else { return nil }
            return roomNames.indices.contains(number) ? "\(roomNames[number]) (\(number))" : "room \(number)"
        }
        if let name = room("Loading Room ") {
            return ParsedLine(time: time, level: .info, source: "Rooms", message: "Entered \(name)")
        }
        if let name = room("UnLoading Room ") {
            return ParsedLine(time: time, level: .debug, source: "Rooms", message: "Left \(name)")
        }
        if message.hasPrefix("Reset") {
            return ParsedLine(time: time, level: message.hasPrefix("Resetting") ? .debug : .info, source: "Map", message: String(message))
        }
        return ParsedLine(time: time, level: .info, source: "Game", message: String(message))
    }
}

/// What the launcher reads from the game data (game.ios) besides GEN8.
public enum GameData {
    /// Room names by number, from the ROOM chunk: a count, then a file offset per room whose first field
    /// is the offset of its name in STRG (the characters, after a 32-bit length). Empty when unreadable.
    public static func roomNames(of game: URL) -> [String] {
        guard let data = try? Data(contentsOf: game, options: .mappedIfSafe), data.count >= 8,
              data.prefix(4) == Data("FORM".utf8) else { return [] }
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= data.count else { return nil }
            let base = data.startIndex + at
            return Int(UInt32(data[base]) | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24)
        }
        func string(_ at: Int) -> String? {
            guard let length = u32(at - 4), length < 256, at + length <= data.count else { return nil }
            return String(data: data[(data.startIndex + at)..<(data.startIndex + at + length)], encoding: .utf8)
        }
        var offset = 8
        while offset + 8 <= data.count, let size = u32(offset + 4) {
            if data[(data.startIndex + offset)..<(data.startIndex + offset + 4)] == Data("ROOM".utf8) {
                guard let count = u32(offset + 8), count < 10_000 else { return [] }
                var names: [String] = []
                for index in 0..<count {
                    guard let entry = u32(offset + 12 + index * 4), let nameOffset = u32(entry), let name = string(nameOffset) else { return [] }
                    names.append(name)
                }
                return names
            }
            offset += 8 + size
        }
        return []
    }

    /// Game data with only a ROOM chunk (and the strings it points to), for tests and samples.
    /// With `gameID`, a GEN8 chunk comes first, so saves can be made for it too.
    public static func sample(roomNames: [String], gameID: UInt32? = nil) -> Data {
        func le(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        let gen8 = gameID.map { Data(GameSave.sampleGameData(gameID: $0).dropFirst(8)) } ?? Data()
        // FORM(8) [GEN8] ROOM header(8) count(4) pointers(4n) entries(4n) strings
        let pointers = gen8.count + 20, entries = pointers + 4 * roomNames.count
        var strings = Data(), nameOffsets: [Int] = []
        var at = entries + 4 * roomNames.count
        for name in roomNames {
            let bytes = Data(name.utf8)
            nameOffsets.append(at + 4)
            strings += le(bytes.count) + bytes + Data([0])
            at += 4 + bytes.count + 1
        }
        var room = le(roomNames.count)
        for index in roomNames.indices { room += le(entries + 4 * index) }
        for offset in nameOffsets { room += le(offset) }
        room += strings
        let chunk = gen8 + Data("ROOM".utf8) + le(room.count) + room
        return Data("FORM".utf8) + le(chunk.count) + chunk
    }
}
