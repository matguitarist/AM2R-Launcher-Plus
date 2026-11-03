import CryptoKit
import Foundation

/// Recognizes the player's own AM2R 1.1 (a zip or an extracted folder).
/// The rule follows AM2RLauncher's CheckIfZipIsAM2R11, relaxed for the native engine:
/// `data.win` must be the 1.1 file; `AM2R.exe` is only needed for the Rosetta engine.
public enum AM2R11 {
    public static let dataWinMD5 = "f2b84fe5ba64cb64e284be1066ca08ee"
    public static let exeMD5 = "15253f7a66d6ea3feef004ebbee9b438"

    public enum Kind: String, Codable, Sendable { case zip, folder }

    /// A checked AM2R 1.1 copy.
    public struct Copy: Equatable, Sendable {
        public var url: URL
        public var kind: Kind
        /// Path inside the zip or folder that holds data.win ("" or "AM2R_11/").
        public var root: String
        /// False when AM2R.exe is missing or modified: Rosetta can't be used, Native still can.
        public var hasWindowsGame: Bool

        public init(url: URL, kind: Kind, root: String, hasWindowsGame: Bool) {
            self.url = url
            self.kind = kind
            self.root = root
            self.hasWindowsGame = hasWindowsGame
        }
    }

    /// Why a file isn't AM2R 1.1. The messages are UI text (docs/STORIES.md S-001).
    public enum Problem: Error, Equatable, Sendable {
        case notZipOrFolder
        case unreadableZip
        case missingDataWin
        case wrongDataWin

        public var message: String {
            switch self {
            case .notZipOrFolder: "Choose a .zip file or a folder."
            case .unreadableZip: "Unable to open this zip. It may be damaged."
            case .missingDataWin: "No data.win in this folder or zip. Choose the AM2R 1.1 game files."
            case .wrongDataWin: "This isn't AM2R 1.1. Its data.win doesn't match the 1.1 release."
            }
        }
    }

    /// Checks a zip or folder. Hashes are cached by path, size and modified date.
    public static func check(_ url: URL, cache: HashCache? = nil) throws(Problem) -> Copy {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw .notZipOrFolder }
        if isDirectory.boolValue {
            return try checkFolder(url, cache: cache)
        }
        guard url.pathExtension.lowercased() == "zip" else { throw .notZipOrFolder }
        return try checkZip(url, cache: cache)
    }

    // MARK: Folder

    private static func checkFolder(_ url: URL, cache: HashCache?) throws(Problem) -> Copy {
        guard let root = folderRoot(url) else { throw .missingDataWin }
        let base = root.isEmpty ? url : url.appending(path: root, directoryHint: .isDirectory)
        let dataWin = base.appending(path: "data.win")
        guard let hash = cachedMD5(of: dataWin, cache: cache) else { throw .missingDataWin }
        guard hash == dataWinMD5 else { throw .wrongDataWin }
        let exe = base.appending(path: "AM2R.exe")
        return Copy(url: url, kind: .folder, root: root, hasWindowsGame: cachedMD5(of: exe, cache: cache) == exeMD5)
    }

    /// "" when data.win is at the top, "<name>/" when it's inside exactly one subfolder, nil otherwise.
    private static func folderRoot(_ url: URL) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appending(path: "data.win").path) { return "" }
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let folders = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard folders.count == 1, fm.fileExists(atPath: folders[0].appending(path: "data.win").path) else { return nil }
        return folders[0].lastPathComponent + "/"
    }

    // MARK: Zip

    private static func checkZip(_ url: URL, cache: HashCache?) throws(Problem) -> Copy {
        guard let entries = Zip.list(url) else { throw .unreadableZip }
        guard let root = zipRoot(entries) else { throw .missingDataWin }
        let key = HashCache.Key(url: url, member: root + "data.win")
        let hash: String
        if let cached = key.flatMap({ cache?.value(for: $0) }) {
            hash = cached
        } else {
            guard let computed = Zip.md5(of: root + "data.win", in: url) else { throw .unreadableZip }
            hash = computed
            if let key { cache?.store(computed, for: key) }
        }
        guard hash == dataWinMD5 else { throw .wrongDataWin }
        var exeHash: String?
        if entries.contains(root + "AM2R.exe") {
            let exeKey = HashCache.Key(url: url, member: root + "AM2R.exe")
            exeHash = exeKey.flatMap { cache?.value(for: $0) } ?? Zip.md5(of: root + "AM2R.exe", in: url)
            if let exeKey, let exeHash { cache?.store(exeHash, for: exeKey) }
        }
        return Copy(url: url, kind: .zip, root: root, hasWindowsGame: exeHash == exeMD5)
    }

    static func zipRoot(_ entries: [String]) -> String? {
        if entries.contains("data.win") { return "" }
        let nested = entries.filter { $0.hasSuffix("/data.win") && $0.split(separator: "/").count == 2 }
        guard nested.count == 1 else { return nil }
        return String(nested[0].dropLast("data.win".count))
    }

    // MARK: Hashing

    private static func cachedMD5(of file: URL, cache: HashCache?) -> String? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let key = HashCache.Key(url: file, member: "")
        if let key, let cached = cache?.value(for: key) { return cached }
        guard let hash = md5(of: file) else { return nil }
        if let key { cache?.store(hash, for: key) }
        return hash
    }

    /// Streams a file through MD5 in 1 MB chunks.
    public static func md5(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.MD5()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Remembers file hashes so a 48 MB data.win isn't hashed on every check.
public final class HashCache: @unchecked Sendable {
    public struct Key: Hashable, Codable, Sendable {
        var path: String
        var member: String
        var size: Int
        var modified: Double

        public init?(url: URL, member: String) {
            // URL caches resource values; a file changed since the last read would keep its old size and date.
            var url = url
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
            path = url.standardizedFileURL.path
            self.member = member
            self.size = size
            self.modified = modified.timeIntervalSinceReferenceDate
        }

        var id: String { "\(path)|\(member)|\(size)|\(modified)" }
    }

    private let file: URL?
    private var values: [String: String]
    private let lock = NSLock()

    /// `file` nil keeps the cache in memory only.
    public init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    public func value(for key: Key) -> String? {
        lock.withLock { values[key.id] }
    }

    public func store(_ hash: String, for key: Key) {
        lock.withLock {
            values[key.id] = hash
            guard let file, let data = try? JSONEncoder().encode(values) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// Reads zips with the system's /usr/bin/unzip (no third-party code, streams large members).
enum Zip {
    static func list(_ zip: URL) -> [String]? {
        guard let output = zipinfo(["-1", zip.path]) else { return nil }
        return String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func md5(of member: String, in zip: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", zip.path, member]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        var hasher = Insecure.MD5()
        var bytes = 0
        let reader = pipe.fileHandleForReading
        while let chunk = try? reader.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            bytes += chunk.count
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, bytes > 0 else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func zipinfo(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
