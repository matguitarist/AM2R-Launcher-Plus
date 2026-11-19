import Foundation

/// Moves the data folder somewhere else, such as an external drive (S-013).
/// Another disk: copies into a staging folder, checks every file arrived with its size, then deletes
/// the old items. Same disk: renames each item. If anything fails, the old folder stays as it was.
/// Top-level items named in `keeping` stay where they are: the database, which sits in the default folder.
public enum FolderMove {
    public enum Failure: Error, Equatable, Sendable {
        /// The chosen folder already has an item of that name where the data would go.
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

    /// The database's files when it sits in `folder` (the default data folder holds it), so a move leaves them.
    public static func databaseFiles(store: URL, in folder: URL) -> Set<String> {
        guard store.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
                == folder.standardizedFileURL.resolvingSymlinksInPath().path else { return [] }
        let name = store.lastPathComponent
        return [name, name + "-shm", name + "-wal"]
    }

    /// Moves `source` into `parent`, keeping its name. Returns the new location.
    /// The new folder may already exist (the default folder that holds the database) as long as
    /// none of the moved items is in it.
    @discardableResult
    public static func move(_ source: URL, into parent: URL, keeping: Set<String> = [],
                            progress: (@Sendable (Int64, Int64) -> Void)? = nil) throws(Failure) -> URL {
        let fm = FileManager.default
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let parent = parent.standardizedFileURL.resolvingSymlinksInPath()
        let destination = parent.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        if parent.path == source.path || parent.path.hasPrefix(source.path + "/") { throw .insideItself }
        if destination.path == source.path { return source }

        let items = ((try? fm.contentsOfDirectory(atPath: source.path)) ?? []).filter { !keeping.contains($0) }.sorted()
        var isFolder: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isFolder) {
            guard isFolder.boolValue else { throw .destinationExists(source.lastPathComponent) }
            if let clash = items.first(where: { fm.fileExists(atPath: destination.appending(path: $0).path) }) {
                throw .destinationExists(source.lastPathComponent + "/" + clash)
            }
        }

        let files = listFiles(in: source, excluding: keeping)
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        progress?(0, total)

        // Same disk: a rename is instant. Undo the renames done so far if one fails.
        if volume(of: source) == volume(of: parent) {
            var moved: [String] = []
            do {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                for item in items {
                    try fm.moveItem(at: source.appending(path: item), to: destination.appending(path: item))
                    moved.append(item)
                }
            } catch {
                for item in moved { try? fm.moveItem(at: destination.appending(path: item), to: source.appending(path: item)) }
                removeIfEmpty(destination)
                throw .copyFailed("\(error)")
            }
            removeIfEmpty(source)
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
        let copied = Dictionary(listFiles(in: staging).map { ($0.path, $0.size) }) { first, _ in first }
        for file in files where copied[file.path] != file.size {
            try? fm.removeItem(at: staging)
            throw .verifyFailed(file.path)
        }
        do {
            if fm.fileExists(atPath: destination.path) {
                // Into the existing folder: the staging folder is on the same disk, so these are renames.
                var moved: [String] = []
                do {
                    for item in items {
                        try fm.moveItem(at: staging.appending(path: item), to: destination.appending(path: item))
                        moved.append(item)
                    }
                } catch {
                    for item in moved { try? fm.removeItem(at: destination.appending(path: item)) }
                    throw error
                }
                try? fm.removeItem(at: staging)
            } else {
                try fm.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw .copyFailed("\(error)")
        }
        for item in items { try? fm.removeItem(at: source.appending(path: item)) }
        removeIfEmpty(source)
        return destination
    }

    public struct File: Equatable, Sendable {
        public var path: String
        public var size: Int64
        public init(path: String, size: Int64) { self.path = path; self.size = size }
    }

    /// Every regular file under `folder`, with paths relative to it, leaving out the top-level
    /// items named in `excluding`.
    public static func listFiles(in folder: URL, excluding: Set<String> = []) -> [File] {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys) else { return [] }
        var files: [File] = []
        for case let url as URL in walker {
            let relative = relativePath(of: url, in: base)
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if walker.level == 1, excluding.contains(relative) {
                // skipDescendants after a file would skip the last folder seen instead.
                if values.isRegularFile != true, values.isSymbolicLink != true { walker.skipDescendants() }
                continue
            }
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            files.append(File(path: relative, size: Int64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func size(of folder: URL, excluding: Set<String> = []) -> Int64 {
        listFiles(in: folder, excluding: excluding).reduce(0) { $0 + $1.size }
    }

    private static func relativePath(of url: URL, in base: URL) -> String {
        let path = url.standardizedFileURL.path, root = base.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : url.lastPathComponent
    }

    private static func removeIfEmpty(_ folder: URL) {
        let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if left.allSatisfy({ $0 == ".DS_Store" }) { try? FileManager.default.removeItem(at: folder) }
    }

    private static func volume(of url: URL) -> URL? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        return try? probe.resourceValues(forKeys: [.volumeURLKey]).volume
    }
}
