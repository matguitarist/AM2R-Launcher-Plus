import Foundation

/// Moves the data folder somewhere else, such as an external drive (S-013).
/// Copies into a staging folder, checks every file arrived with its size, then deletes the old
/// folder. If anything fails, the old folder stays and the partial copy is removed.
public enum FolderMove {
    public enum Failure: Error, Equatable, Sendable {
        case destinationExists(String)
        case insideItself
        case notEnoughSpace(needed: Int64, available: Int64)
        case copyFailed(String)
        case verifyFailed(String)

        public var message: String {
            switch self {
            case .destinationExists(let name): "That folder already has an item named “\(name)”. Choose another folder."
            case .insideItself: "Choose a folder outside the current data folder."
            case .notEnoughSpace(let needed, let available):
                "Not enough space: the data needs \(needed.formatted(.byteCount(style: .file))), the disk has \(available.formatted(.byteCount(style: .file)))."
            case .copyFailed: "Unable to copy the data. The old folder is unchanged."
            case .verifyFailed(let path): "The copy doesn't match the original (\(path)). The old folder is unchanged."
            }
        }
    }

    /// Moves `source` into `parent`, keeping its name. Returns the new location.
    @discardableResult
    public static func move(_ source: URL, into parent: URL, progress: (@Sendable (Int64, Int64) -> Void)? = nil) throws(Failure) -> URL {
        let fm = FileManager.default
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let parent = parent.standardizedFileURL.resolvingSymlinksInPath()
        let destination = parent.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        if parent.path == source.path || parent.path.hasPrefix(source.path + "/") { throw .insideItself }
        if destination.path == source.path { return source }
        if fm.fileExists(atPath: destination.path) { throw .destinationExists(source.lastPathComponent) }

        let files = listFiles(in: source)
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        progress?(0, total)

        // Same disk: a rename is instant and can't half-fail.
        if volume(of: source) == volume(of: parent) {
            do { try fm.moveItem(at: source, to: destination) } catch { throw .copyFailed("\(error)") }
            progress?(total, total)
            return destination
        }

        let available = (try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if available < total { throw .notEnoughSpace(needed: total, available: available) }

        let staging = parent.appending(path: source.lastPathComponent + ".partial", directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var done: Int64 = 0
            for file in files {
                let target = staging.appending(path: file.path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source.appending(path: file.path), to: target)
                done += file.size
                progress?(done, total)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw .copyFailed("\(error)")
        }
        let copied = Dictionary(uniqueKeysWithValues: listFiles(in: staging).map { ($0.path, $0.size) })
        for file in files where copied[file.path] != file.size {
            try? fm.removeItem(at: staging)
            throw .verifyFailed(file.path)
        }
        do { try fm.moveItem(at: staging, to: destination) } catch {
            try? fm.removeItem(at: staging)
            throw .copyFailed("\(error)")
        }
        try? fm.removeItem(at: source)
        return destination
    }

    public struct File: Equatable, Sendable { public var path: String; public var size: Int64 }

    /// Every regular file under `folder`, with paths relative to it.
    public static func listFiles(in folder: URL) -> [File] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        var files: [File] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            files.append(File(path: String(path.dropFirst(base.count + 1)), size: Int64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func size(of folder: URL) -> Int64 {
        listFiles(in: folder).reduce(0) { $0 + $1.size }
    }

    private static func volume(of url: URL) -> URL? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        return try? probe.resourceValues(forKeys: [.volumeURLKey]).volume
    }
}
