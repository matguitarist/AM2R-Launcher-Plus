import Foundation

/// Zipped copies of a profile's save folder (saves and config.ini), and putting one back (S-023).
/// A backup is a plain zip with the save files at its root, named "<profile> – 2026-11-03 14-05.zip".
public enum SaveBackup {
    public struct Backup: Equatable, Sendable, Identifiable {
        public var url: URL
        public var date: Date
        public var size: Int64
        public var id: URL { url }
        /// File name without ".zip".
        public var name: String { url.deletingPathExtension().lastPathComponent }
    }

    public enum Failure: Error, Equatable, Sendable {
        case noSaves
        case notABackup
        case failed(String)

        public var message: String {
            switch self {
            case .noSaves: "This profile has no saves yet. Play once, then back up."
            case .notABackup: "This zip has no AM2R saves in it."
            case .failed(let reason): "Unable to finish: \(reason)"
            }
        }
    }

    /// Zips the contents of `saves` into `folder`. `label` is added to the name, e.g. "before restore".
    @discardableResult
    public static func backup(saves: URL, into folder: URL, profileName: String, label: String? = nil, date: Date = .now) throws(Failure) -> URL {
        let fm = FileManager.default
        let items = ((try? fm.contentsOfDirectory(atPath: saves.path)) ?? []).filter { !$0.hasPrefix(".") }
        guard !items.isEmpty else { throw .noSaves }
        var base = ProfileName.dated(profileName, date: date)
        if let label { base += " (\(label))" }
        var zip = folder.appending(path: base + ".zip")
        var number = 2
        while fm.fileExists(atPath: zip.path) {
            zip = folder.appending(path: "\(base) \(number).zip")
            number += 1
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // ditto -c -k zips like Finder; without --keepParent the files sit at the root of the zip.
            try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", saves.path, zip.path])
        } catch {
            try? fm.removeItem(at: zip)
            throw .failed("\(error)")
        }
        return zip
    }

    /// The backups in `folder`, newest first.
    public static func list(in folder: URL) -> [Backup] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "zip" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Backup(url: url, date: values?.contentModificationDate ?? .distantPast, size: Int64(values?.fileSize ?? 0))
        }
        .sorted { $0.date > $1.date }
    }

    /// Replaces the contents of `saves` with the backup. The zip is unpacked beside the save folder first
    /// and swapped in only when complete. A zip that holds one folder (a zipped save folder) works too.
    public static func restore(_ zip: URL, into saves: URL) throws(Failure) {
        let fm = FileManager.default
        let parent = saves.deletingLastPathComponent()
        let staging = parent.appending(path: saves.lastPathComponent + ".restoring", directoryHint: .isDirectory)
        let old = parent.appending(path: saves.lastPathComponent + ".old", directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try? fm.removeItem(at: old)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        } catch {
            try? fm.removeItem(at: staging)
            throw .notABackup
        }
        let content = savesRoot(in: staging)
        guard isSaveFolder(content) else {
            try? fm.removeItem(at: staging)
            throw .notABackup
        }
        do {
            if fm.fileExists(atPath: saves.path) { try fm.moveItem(at: saves, to: old) }
            try fm.moveItem(at: content, to: saves)
            try? fm.removeItem(at: old)
            try? fm.removeItem(at: staging)
        } catch {
            // Put the old saves back.
            if !fm.fileExists(atPath: saves.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: saves) }
            try? fm.removeItem(at: staging)
            throw .failed("\(error)")
        }
    }

    /// AM2R writes config.ini and save1…save3 (plus .bak and per-slot files) into its save folder.
    static func isSaveFolder(_ folder: URL) -> Bool {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map { $0.lowercased() }
        return names.contains { $0 == "config.ini" || $0.hasPrefix("save") }
    }

    /// The folder in an unpacked zip that holds the saves: the zip's root, or its only folder.
    private static func savesRoot(in staging: URL) -> URL {
        let items = ((try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
        if items.count == 1, (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, !isSaveFolder(staging) {
            return items[0]
        }
        return staging
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SaveBackup", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            ])
        }
    }
}
