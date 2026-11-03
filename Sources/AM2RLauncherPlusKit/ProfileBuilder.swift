import Foundation

/// Builds a playable Community Updates profile from AM2R 1.1 and the patch data (S-003, S-004).
/// Mirrors AM2R-Autopatcher-Mac's patcher.command for the native engine: no runner, no Frameworks.
public enum ProfileBuilder {
    public enum Step: Int, CaseIterable, Sendable {
        case extract, patch, copy
    }

    public enum Failure: Error, Equatable, Sendable {
        case extractFailed
        case patchFailed(String)
        case copyFailed(String)

        public var message: String {
            switch self {
            case .extractFailed: "Unable to read the game files from AM2R 1.1."
            case .patchFailed: "Patching failed. The patch data doesn't match this copy of AM2R 1.1."
            case .copyFailed: "Unable to copy game files. There may not be enough space in the data folder."
            }
        }
    }

    /// What a finished profile folder holds, read back from it.
    public struct Result: Equatable, Sendable {
        public var folder: URL
        public var info: PatchData.ProfileInfo
    }

    /// Where the game patch, the extra files and profile.xml come from.
    public struct Patch: Sendable {
        /// An xdelta of AM2R 1.1's data.win.
        public var gameDelta: URL
        /// files_to_copy, when there is one.
        public var filesToCopy: URL?
        public var profileXML: URL

        public init(gameDelta: URL, filesToCopy: URL?, profileXML: URL) {
            self.gameDelta = gameDelta
            self.filesToCopy = filesToCopy
            self.profileXML = profileXML
        }

        /// A finished `PatchData.download` folder.
        public static func communityUpdates(_ patchData: URL) -> Patch {
            Patch(gameDelta: patchData.appending(path: "data/game.xdelta"),
                  filesToCopy: patchData.appending(path: "data/files_to_copy", directoryHint: .isDirectory),
                  profileXML: patchData.appending(path: "profile.xml"))
        }

        /// A folder holding an extracted `ModPackage` (S-033).
        public static func mod(_ folder: URL, package: ModPackage) -> Patch {
            Patch(gameDelta: folder.appending(path: package.gamePatch),
                  filesToCopy: package.hasFilesToCopy ? folder.appending(path: "files_to_copy", directoryHint: .isDirectory) : nil,
                  profileXML: folder.appending(path: "profile.xml"))
        }
    }

    /// Builds Community Updates from a finished `PatchData.download` folder.
    public static func build(source: URL, kind: AM2R11.Kind, root: String, patchData: URL, destination: URL,
                             step: (@Sendable (Step) -> Void)? = nil) throws -> Result {
        try build(source: source, kind: kind, root: root, patch: .communityUpdates(patchData), destination: destination, step: step)
    }

    /// Builds into `destination` (replaced only when the new build is complete).
    /// - Parameters:
    ///   - source: the AM2R 1.1 zip or folder, with `root` the folder inside it that holds data.win.
    public static func build(source: URL, kind: AM2R11.Kind, root: String, patch: Patch, destination: URL,
                             step: (@Sendable (Step) -> Void)? = nil) throws -> Result {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appending(path: destination.lastPathComponent + ".partial", directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let work = fm.temporaryDirectory.appending(path: "am2r-build-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }

        do {
            // 1. data.win and the music from AM2R 1.1
            step?(.extract)
            let original = try extract(source: source, kind: kind, root: root, into: work)

            // 2. data.win + the game patch = game.ios (the engine reads any system's game data)
            step?(.patch)
            do {
                try VCDiff.apply(source: original.appending(path: "data.win"), patch: patch.gameDelta,
                                 output: staging.appending(path: "game.ios"))
            } catch {
                throw Failure.patchFailed("\(error)")
            }

            // 3. music (lowercased, like the Mac release) and the Community Updates files
            step?(.copy)
            do {
                try copyMusic(from: original, to: staging)
                if let files = patch.filesToCopy { try copyFilesToCopy(from: files, to: staging) }
                try fm.copyItem(at: patch.profileXML, to: staging.appending(path: "profile.xml"))
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure.copyFailed("\(error)")
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        let xml = (try? String(contentsOf: staging.appending(path: "profile.xml"), encoding: .utf8)) ?? ""
        let info = PatchData.profileInfo(xml) ?? PatchData.ProfileInfo(name: "Community Updates", version: "?", author: "")
        do {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: destination)
        } catch {
            try? fm.removeItem(at: staging)
            throw Failure.copyFailed("\(error)")
        }
        return Result(folder: destination, info: info)
    }

    /// Puts data.win and every .ogg of AM2R 1.1 into `work` and returns that folder.
    private static func extract(source: URL, kind: AM2R11.Kind, root: String, into work: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        switch kind {
        case .zip:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", "-j", source.path, root + "data.win", root + "*.ogg", "-d", work.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.extractFailed }
            return work
        case .folder:
            let base = root.isEmpty ? source : source.appending(path: root, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: base.appending(path: "data.win").path) else { throw Failure.extractFailed }
            return base
        }
    }

    private static func copyMusic(from original: URL, to staging: URL) throws {
        let fm = FileManager.default
        for file in try fm.contentsOfDirectory(at: original, includingPropertiesForKeys: nil) where file.pathExtension.lowercased() == "ogg" {
            try fm.copyItem(at: file, to: staging.appending(path: file.lastPathComponent.lowercased()))
        }
    }

    /// files_to_copy: newer music replaces 1.1's, lang/fonts is left out (custom fonts aren't used on Mac).
    private static func copyFilesToCopy(from folder: URL, to staging: URL) throws {
        let fm = FileManager.default
        for item in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }
            let target = staging.appending(path: item.pathExtension.lowercased() == "ogg" ? name.lowercased() : name)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: item, to: target)
        }
        let fonts = staging.appending(path: "lang/fonts", directoryHint: .isDirectory)
        if fm.fileExists(atPath: fonts.path) { try fm.removeItem(at: fonts) }
    }
}
