import Foundation

/// An AM2R save slot (save1…save3) as Community Updates 1.5 writes it (sv6_save, S-037).
///
/// The file is XORed by the game's crypt() with a key made from the game's game_id, then holds
/// lines of text: an RC4-scrambled header, ten base64 ds_list_write strings (main, items, events,
/// logs, hints, monsters, inventory, map, randomizer, trooper logs) and the seed.
/// Only the main, items and inventory lists are edited; every other line is kept byte for byte.
public struct GameSave: Equatable, Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case unreadable
        case notASave
        case unwritable

        public var message: String {
            switch self {
            case .unreadable: "Unable to read this save."
            case .notASave: "This save isn't one Community Updates can load."
            case .unwritable: "Unable to write the save."
            }
        }
    }

    /// What "every upgrade" gives (owner's call, 2026-11-17: both, as two choices).
    public enum Upgrades: String, CaseIterable, Sendable, Identifiable {
        /// Every ability, beam and suit; missiles and tanks stay as found.
        case abilities
        /// The developers' full loadout (get_loadout case 10): abilities plus every tank.
        case everything

        public var id: String { rawValue }
    }

    static let fileKey = "XOR_DFJykQ8xX3PuNnkLt6QviqALOLF8cxIDx1D63DAdph4KGQ4rOJ7"
    static let header = "[AM2R SaveData V7.0]"

    enum Line {
        static let main = 1, items = 2, inventory = 7, randomizer = 9, seed = 11
    }

    /// The decrypted file split at "\n", the last element being what follows the final newline.
    var lines: [Data]

    // MARK: Reading and writing

    public init(decrypting data: Data, gameID: UInt32) throws(Failure) {
        let plain = Self.crypt(data, gameID: gameID)
        lines = plain.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { Data($0) }
        guard lines.count > Line.inventory, Self.readHeader(lines[0]) == Self.header else { throw .notASave }
        for index in [Line.main, Line.items, Line.inventory] {
            guard (try? list(at: index)) != nil else { throw .notASave }
        }
    }

    public func encrypted(gameID: UInt32) -> Data {
        Self.crypt(Data(lines.joined(separator: [UInt8(ascii: "\n")])), gameID: gameID)
    }

    /// Gives a slot's save every upgrade and writes it back in place.
    public static func giveUpgrades(_ upgrades: Upgrades, slot: URL, game: URL) throws(Failure) {
        guard let gameID = gameID(of: game), let data = try? Data(contentsOf: slot) else { throw .unreadable }
        var save = try GameSave(decrypting: data, gameID: gameID)
        try save.give(upgrades)
        do { try save.encrypted(gameID: gameID).write(to: slot, options: .atomic) } catch { throw .unwritable }
    }

    /// The slots a save folder holds, in slot order: save1, save2, save3.
    public static func slots(in saves: URL) -> [URL] {
        (1...3).map { saves.appending(path: "save\($0)") }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Randomizer

    /// How the slot's game was randomized, or nil for a game that wasn't (S-040). sv6_randomizer ends
    /// with mod_purerandombool, mod_randomgamebool, mod_splitrandom, mod_fusion, mod_diffmult,
    /// chozomessage, mod_gravity, global.gamemode and 25 zeros, so they are read from the end.
    public var randomizedGame: RandomizedGame? {
        guard let values = (try? list(at: Line.randomizer))?.values, values.count >= 33 else { return nil }
        let end = values.count - 25
        let gameMode = values[end - 1].number ?? 0
        let pureRandom = (values[end - 8].number ?? 0) != 0
        let randomGame = (values[end - 7].number ?? 0) != 0
        let splitRandom = (values[end - 6].number ?? 0) != 0
        let mode: RandomizedGame.Mode
        switch gameMode {
        case 3: mode = .classic
        case 4: mode = .am2Random
        case 5: mode = .splitRandom
        default:
            guard pureRandom || randomGame || splitRandom else { return nil }
            mode = splitRandom ? .splitRandom : pureRandom ? .randomGamePlus : .other
        }
        return RandomizedGame(mode: mode, seed: seed)
    }

    /// The seed line: base64 of string(oControl.seed), digits, maybe with GameMaker's decimals.
    var seed: String {
        guard lines.count > Line.seed else { return "0" }
        var line = lines[Line.seed]
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let text = Data(base64Encoded: line).flatMap { String(data: $0, encoding: .utf8) } ?? String(decoding: line, as: UTF8.self)
        return RandomizerOptions.cleanSeed(text)
    }

    /// The randomized game in a slot, or nil when the slot can't be read or isn't randomized.
    public static func randomizedGame(slot: URL, game: URL) -> RandomizedGame? {
        guard let gameID = gameID(of: game), let data = try? Data(contentsOf: slot),
              let save = try? GameSave(decrypting: data, gameID: gameID) else { return nil }
        return save.randomizedGame
    }

    // MARK: Upgrades

    /// inventory: currentsuit, then cbeam, ibeam, wbeam, pbeam, sbeam, morphball, jumpball, powergrip,
    /// spacejump, screwattack, hijump, spiderball, speedbooster, bomb (sv6_add_inventory).
    static let abilityFlags = 1...14
    /// Gravity Suit; it keeps Varia's protection.
    static let bestSuit = 2.0
    /// items 0…14 mark the major upgrades as collected, so their pickups are gone (get_loadout 10).
    static let majorItems = 0...14
    /// main: etanks, mtanks, stanks, ptanks at 4…7 (sv6_add_main). The game turns tanks into maximums
    /// when it loads: 10 energy tanks give 1099 energy, 44 missile tanks 250 missiles, 10 super and
    /// 10 power bomb tanks 20 each.
    static let tanks: [(index: Int, count: Double)] = [(4, 10), (5, 44), (6, 10), (7, 10)]

    public mutating func give(_ upgrades: Upgrades) throws(Failure) {
        var inventory = try list(at: Line.inventory)
        var items = try list(at: Line.items)
        guard inventory.values.count > Self.abilityFlags.upperBound, items.values.count > Self.majorItems.upperBound else { throw .notASave }
        inventory.values[0] = .real(Self.bestSuit)
        for index in Self.abilityFlags { inventory.values[index] = .real(1) }
        for index in Self.majorItems { items.values[index] = .real(1) }
        setList(inventory, at: Line.inventory)
        setList(items, at: Line.items)
        if upgrades == .everything {
            var main = try list(at: Line.main)
            guard main.values.count > 7 else { throw .notASave }
            for tank in Self.tanks { main.values[tank.index] = .real(tank.count) }
            setList(main, at: Line.main)
        }
    }

    /// The numbers the game reads from a slot, for checks: inventory and the tank counts.
    public func value(inventory index: Int) -> Double? { (try? list(at: Line.inventory))?.values[safe: index]?.number }
    public func value(main index: Int) -> Double? { (try? list(at: Line.main))?.values[safe: index]?.number }
    public func value(items index: Int) -> Double? { (try? list(at: Line.items))?.values[safe: index]?.number }

    private func list(at index: Int) throws(Failure) -> DSList {
        var line = lines[index]
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        guard let hex = Data(base64Encoded: line).flatMap({ String(data: $0, encoding: .ascii) }),
              let list = DSList(hex: hex) else { throw .notASave }
        return list
    }

    private mutating func setList(_ list: DSList, at index: Int) {
        let carriageReturn = lines[index].last == UInt8(ascii: "\r")
        var line = Data(list.hex.utf8).base64EncodedData()
        if carriageReturn { line.append(UInt8(ascii: "\r")) }
        lines[index] = line
    }

    // MARK: Samples

    /// A small save the game would load, for self-tests and snapshots: the header, ten ds_list
    /// lines, the seed and a final newline, as sv6_save writes them.
    public static func sample(gameID: UInt32) -> Data { sample(gameID: gameID, inventory: nil) }

    /// A sample save of a randomized game: global.gamemode and the seed line as sv6_save writes them.
    public static func sampleRandomized(gameID: UInt32, gameMode: Double, seed: String) -> Data {
        let randomizer = Array(repeating: DSList.Value.real(0), count: 70) + [.real(gameMode)] + Array(repeating: .real(0), count: 25)
        return sample(gameID: gameID, inventory: nil, randomizer: randomizer, seedLine: Data(seed.utf8).base64EncodedString())
    }

    static func sample(gameID: UInt32, inventory: [DSList.Value]?, randomizer: [DSList.Value] = [.int32(7)], seedLine: String = "12345") -> Data {
        let header = String(String.UnicodeScalarView(rc4(Array(Self.header.utf8), key: "HEADER_KEY").map { Unicode.Scalar($0) }))
        func list(_ values: [DSList.Value]) -> String {
            var list = DSList(hex: "2F01000000000000")!
            list.values = values
            return Data(list.hex.utf8).base64EncodedString()
        }
        let main: [DSList.Value] = [.real(2), .real(1), .real(10054), .real(3), .real(1), .real(2), .real(0), .real(0)]
            + Array(repeating: .real(0), count: 6) + Array(repeating: .int32(0), count: 36)
        let inventory = inventory ?? [.real(0), .real(0), .real(0), .real(0), .real(0), .real(0), .real(1), .real(0), .real(1)]
            + Array(repeating: .real(0), count: 6) + Array(repeating: .int32(0), count: 35)
        let lines = [header, list(main), list(Array(repeating: .real(0), count: 350)), list([.real(1), .string(Data("note".utf8))]),
                     list([.undefined, .int64(5), .bool(1)]), list([.array([.real(1), .real(2)])]), list([.real(47)]),
                     list(inventory), list(Array(repeating: .real(0), count: 20)), list(randomizer), list([.real(0)]), seedLine, ""]
        return crypt(Data(lines.joined(separator: "\n").utf8), gameID: gameID)
    }

    /// Game data holding only a GEN8 chunk with this game_id, for self-tests.
    public static func sampleGameData(gameID: UInt32) -> Data {
        var gen8 = Data(count: 24)
        withUnsafeBytes(of: gameID.littleEndian) { gen8.replaceSubrange(20..<24, with: $0) }
        var chunk = Data("GEN8".utf8)
        withUnsafeBytes(of: UInt32(gen8.count).littleEndian) { chunk.append(contentsOf: $0) }
        chunk.append(gen8)
        var form = Data("FORM".utf8)
        withUnsafeBytes(of: UInt32(chunk.count).littleEndian) { form.append(contentsOf: $0) }
        return form + chunk
    }

    // MARK: Game id and ciphers

    /// game_id from the game data's GEN8 chunk; the save key is made from it.
    public static func gameID(of game: URL) -> UInt32? {
        guard let handle = try? FileHandle(forReadingFrom: game) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8), head.prefix(4) == Data("FORM".utf8) else { return nil }
        var offset: UInt64 = 8
        while let chunk = try? { try handle.seek(toOffset: offset); return try handle.read(upToCount: 8) }(), chunk.count == 8 {
            let size = UInt64(chunk.uint32(at: 4))
            if chunk.prefix(4) == Data("GEN8".utf8) {
                guard let gen8 = try? handle.read(upToCount: 24), gen8.count == 24 else { return nil }
                return gen8.uint32(at: 20)
            }
            offset += 8 + size
        }
        return nil
    }

    /// The game's crypt(file, key, 2): XORs every (rate + 1)th byte with a key built from game_id.
    /// It is its own inverse. rate depends on the file's size, rounded half to even as the engine does.
    static func crypt(_ data: Data, gameID: UInt32) -> Data {
        let gmid = Array(String(repeating: String(gameID), count: 32).utf8)
        let key = Array(fileKey.utf8)
        let count = String(gameID).count * 5
        var keys = [UInt8](), keyPosition = 0
        for position in 0..<count {
            // string_copy(gmid, 0, 2) and string_char_at(key, 0) both read the first character.
            let a = Int(gmid[max(position, 1) - 1])
            let c = Int(key[max(keyPosition, 1) - 1])
            keys.append(UInt8(truncatingIfNeeded: a ^ (c - position / 3)))
            keyPosition += 1
            if keyPosition > key.count { keyPosition = 1 }
        }
        var bytes = [UInt8](data)
        guard !bytes.isEmpty else { return data }
        let rate = Int((2 * Double(bytes.count) / 10000).rounded(.toNearestOrEven))
        var position = 0, keyIndex = 0
        repeat {
            bytes[position] ^= keys[keyIndex]
            position += 1 + rate
            keyIndex += 1
            if keyIndex > count - 1 { keyIndex = 1 }
        } while position < bytes.count
        return Data(bytes)
    }

    /// The header line holds rc4(header) written one character per byte value, as UTF-8.
    static func readHeader(_ line: Data) -> String? {
        var line = line
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        guard let text = String(data: line, encoding: .utf8) else { return nil }
        let bytes = text.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }
        return String(bytes: rc4(bytes, key: "HEADER_KEY"), encoding: .isoLatin1)
    }

    static func rc4(_ input: [UInt8], key: String) -> [UInt8] {
        let key = Array(key.utf8)
        var s = Array(0...255).map { UInt8($0) }, j = 0
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(key[i % key.count])) % 256
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        return input.map { byte in
            i = (i + 1) % 256
            j = (j + Int(s[i])) % 256
            s.swapAt(i, j)
            return byte ^ s[(Int(s[i]) + Int(s[j])) % 256]
        }
    }
}

/// GameMaker's ds_list_write string: hex of version 303, the count, then each value as a type tag
/// and its payload (Butterscotch's dsStreamWriteValue: 0 real, 1 string, 2 array, 3 pointer,
/// 5 undefined, 7 int32, 10 int64, 13 bool).
struct DSList: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case real(Double), string(Data), array([Value]), pointer(Int64), undefined, int32(Int32), int64(Int64), bool(Double)

        var number: Double? {
            switch self {
            case .real(let value), .bool(let value): value
            case .int32(let value): Double(value)
            case .int64(let value), .pointer(let value): Double(value)
            default: nil
            }
        }
    }

    var version: UInt32
    var values: [Value]
    var uppercase = true

    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8](), index = hex.startIndex
        bytes.reserveCapacity(hex.count / 2)
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        var reader = Reader(bytes: bytes)
        guard let version = reader.u32(), let count = reader.u32() else { return nil }
        var values = [Value]()
        for _ in 0..<count {
            guard let value = reader.value() else { return nil }
            values.append(value)
        }
        guard reader.position == bytes.count else { return nil }
        self.version = version
        self.values = values
        uppercase = hex == hex.uppercased()
    }

    var hex: String {
        var bytes = [UInt8]()
        bytes.append(u32: version)
        bytes.append(u32: UInt32(values.count))
        for value in values { bytes.append(value: value) }
        let text = bytes.map { String(format: "%02x", $0) }.joined()
        return uppercase ? text.uppercased() : text
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
            guard position + count <= bytes.count else { return nil }
            defer { position += count }
            return bytes[position..<position + count]
        }

        mutating func u32() -> UInt32? { take(4).map { $0.reversed().reduce(0) { $0 << 8 | UInt32($1) } } }
        mutating func u64() -> UInt64? { take(8).map { $0.reversed().reduce(0) { $0 << 8 | UInt64($1) } } }

        mutating func value() -> Value? {
            guard let tag = u32() else { return nil }
            switch tag {
            case 0: return u64().map { .real(Double(bitPattern: $0)) }
            case 13: return u64().map { .bool(Double(bitPattern: $0)) }
            case 7: return u32().map { .int32(Int32(bitPattern: $0)) }
            case 10: return u64().map { .int64(Int64(bitPattern: $0)) }
            case 3: return u64().map { .pointer(Int64(bitPattern: $0)) }
            case 5: return .undefined
            case 1:
                guard let length = u32(), let text = take(Int(length)) else { return nil }
                return .string(Data(text))
            case 2:
                guard let count = u32() else { return nil }
                var values = [Value]()
                for _ in 0..<count {
                    guard let value = value() else { return nil }
                    values.append(value)
                }
                return .array(values)
            default: return nil
            }
        }
    }
}

private extension [UInt8] {
    mutating func append(u32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(u64 value: UInt64) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }

    mutating func append(value: DSList.Value) {
        switch value {
        case .real(let number): append(u32: 0); append(u64: number.bitPattern)
        case .bool(let number): append(u32: 13); append(u64: number.bitPattern)
        case .int32(let number): append(u32: 7); append(u32: UInt32(bitPattern: number))
        case .int64(let number): append(u32: 10); append(u64: UInt64(bitPattern: number))
        case .pointer(let number): append(u32: 3); append(u64: UInt64(bitPattern: number))
        case .undefined: append(u32: 5)
        case .string(let text): append(u32: 1); append(u32: UInt32(text.count)); append(contentsOf: text)
        case .array(let values):
            append(u32: 2)
            append(u32: UInt32(values.count))
            for value in values { append(value: value) }
        }
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
