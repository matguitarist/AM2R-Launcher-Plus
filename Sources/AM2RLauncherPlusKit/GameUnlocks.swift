import Foundation

/// What finishing AM2R unlocks, kept in two files beside the save slots (S-044).
///
/// - data.sav (save_stats): the header, then four ds_lists: unlocks (50), gallery (50), stats (100)
///   and achievements (100). The score screen sets unlock[difficulty] (0 Easy, 1 Normal, 2 Hard and
///   up), which shows collected items on the map, and gallery[0…2] by finishing time.
/// - extras.sav (save_stats2): the header, then one ds_list of 20 whose first value is Fusion
///   unlocked (the Fusion difficulty and the Samus Returns Fusion Suit option). The game counts
///   itself beaten (New Game+, Random Game+, the IGT option) whenever extras.sav loads.
///
/// Both use the save slots' cipher (GameSave.crypt) and the header "[AM2R UnlockData V7.0]".
/// Unlocking keeps stats, achievements and anything else already in the files.
public enum GameUnlocks {
    public typealias Failure = GameSave.Failure

    static let header = "[AM2R UnlockData V7.0]"
    static let dataFile = "data.sav", extrasFile = "extras.sav"
    static let unlocks = 0...2, gallery = 0...2

    /// Whether the save folder already has everything this unlocks.
    public static func isEverythingUnlocked(saves: URL, game: URL) -> Bool {
        guard let gameID = GameSave.gameID(of: game),
              let data = try? read(saves.appending(path: dataFile), gameID: gameID, lists: 4),
              let extras = try? read(saves.appending(path: extrasFile), gameID: gameID, lists: 1) else { return false }
        return unlocks.allSatisfy { data[0].values[safe: $0]?.number == 1 }
            && gallery.allSatisfy { data[1].values[safe: $0]?.number == 1 }
            && extras[0].values.first?.number == 1
    }

    /// Unlocks every ending's reward in the save folder, as if the game was finished on every
    /// difficulty in the best time. Missing files are made; values already there are kept.
    public static func unlockEverything(saves: URL, game: URL) throws(Failure) {
        guard let gameID = GameSave.gameID(of: game) else { throw .unreadable }
        let dataURL = saves.appending(path: dataFile), extrasURL = saves.appending(path: extrasFile)
        var data = try readOrMake(dataURL, gameID: gameID, counts: [50, 50, 100, 100])
        for index in unlocks { data[0].values[index] = .real(1) }
        for index in gallery { data[1].values[index] = .real(1) }
        var extras = try readOrMake(extrasURL, gameID: gameID, counts: [20])
        extras[0].values[0] = .real(1)
        do {
            try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
            try encrypted(data, gameID: gameID).write(to: dataURL, options: .atomic)
            try encrypted(extras, gameID: gameID).write(to: extrasURL, options: .atomic)
        } catch { throw .unwritable }
    }

    // MARK: Files

    private static func readOrMake(_ url: URL, gameID: UInt32, counts: [Int]) throws(Failure) -> [DSList] {
        var lists: [DSList]
        if FileManager.default.fileExists(atPath: url.path) {
            lists = try read(url, gameID: gameID, lists: counts.count)
        } else {
            lists = counts.map { _ in DSList.empty }
        }
        // A short list (an older file) grows with zeros, as the game reads missing values as 0.
        for (index, count) in counts.enumerated() where lists[index].values.count < count {
            lists[index].values += Array(repeating: .real(0), count: count - lists[index].values.count)
        }
        return lists
    }

    static func read(_ url: URL, gameID: UInt32, lists count: Int) throws(Failure) -> [DSList] {
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        let lines = GameSave.crypt(data, gameID: gameID).split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        guard lines.count > count, GameSave.readHeader(Data(lines[0])) == header else { throw .notASave }
        var lists = [DSList]()
        for line in lines[1...count] {
            var line = Data(line)
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            guard let decoded = Data(base64Encoded: line), let hex = String(data: decoded, encoding: .ascii),
                  let list = DSList(hex: hex) else { throw .notASave }
            lists.append(list)
        }
        return lists
    }

    /// The file as the game writes it: the header, one base64 line per list, and a final newline.
    static func encrypted(_ lists: [DSList], gameID: UInt32) -> Data {
        let lines = [GameSave.encodedHeader(header)] + lists.map { Data($0.hex.utf8).base64EncodedString() } + [""]
        return GameSave.crypt(Data(lines.joined(separator: "\n").utf8), gameID: gameID)
    }
}

extension DSList {
    /// ds_list_write of an empty list: version 303, no values.
    static var empty: DSList { DSList(hex: "2F01000000000000")! }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
