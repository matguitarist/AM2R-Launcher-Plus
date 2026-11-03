import CryptoKit
import Foundation

/// The Community Updates patch data for Mac, from GitHub (S-002).
/// Downloads only the files a profile needs and checks each one against its Git blob hash.
public enum PatchData {
    public static let owner = "Miepee"
    public static let repo = "AM2R-Autopatcher-Mac"
    public static let branch = "master"

    public struct File: Equatable, Sendable, Codable {
        public var path: String
        /// Git blob SHA-1 of the content.
        public var blob: String
        public var size: Int
    }

    /// One commit of the patch data and the files to download from it.
    public struct Manifest: Equatable, Sendable, Codable {
        public var commit: String
        public var files: [File]
        public var totalSize: Int { files.reduce(0) { $0 + $1.size } }

        public init(commit: String, files: [File]) {
            self.commit = commit
            self.files = files
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case offline
        case github(Int)
        case badResponse
        case corruptDownload(String)

        public var message: String {
            switch self {
            case .offline: "Unable to reach GitHub. Check your connection, then try again."
            case .github(let status) where status == 403 || status == 429: "GitHub is limiting downloads right now. Try again in a few minutes."
            case .github(let status): "GitHub answered with an error (\(status)). Try again later."
            case .badResponse: "GitHub sent an unexpected answer. Try again later."
            case .corruptDownload(let path): "A download was damaged (\(path)). Try again."
            }
        }
    }

    /// Which files a profile needs. The Android patch and the optional HQ music are left out.
    public static func isNeeded(_ path: String, rosetta: Bool) -> Bool {
        if path == "profile.xml" || path == "data/game.xdelta" { return true }
        if path.hasPrefix("data/files_to_copy/") { return true }
        if rosetta {
            return path == "data/AM2R.xdelta" || path == "data/Info.plist" || path == "data/PkgInfo" || path.hasPrefix("data/Frameworks/")
        }
        return false
    }

    // MARK: Manifest

    struct CommitResponse: Decodable { var sha: String }
    struct TreeResponse: Decodable {
        struct Entry: Decodable { var path: String; var type: String; var sha: String; var size: Int? }
        var tree: [Entry]
        var truncated: Bool
    }

    /// Reads the latest commit and its file list (two GitHub API calls).
    public static func latestManifest(rosetta: Bool = true, session: URLSession = .shared) async throws(Failure) -> Manifest {
        let commit: CommitResponse = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)/commits/\(branch)", session: session)
        let tree: TreeResponse = try await getJSON("https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(commit.sha)?recursive=1", session: session)
        return try manifest(commit: commit.sha, tree: tree, rosetta: rosetta)
    }

    static func manifest(commit: String, tree: TreeResponse, rosetta: Bool) throws(Failure) -> Manifest {
        guard !tree.truncated else { throw .badResponse }
        let files = tree.tree
            .filter { $0.type == "blob" && isNeeded($0.path, rosetta: rosetta) }
            .map { File(path: $0.path, blob: $0.sha, size: $0.size ?? 0) }
        guard files.contains(where: { $0.path == "data/game.xdelta" }), files.contains(where: { $0.path == "profile.xml" }) else {
            throw .badResponse
        }
        return Manifest(commit: commit, files: files)
    }

    private static func getJSON<T: Decodable>(_ url: String, session: URLSession) async throws(Failure) -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AM2RLauncherPlus", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request, session: session)
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard http.statusCode == 200 else { throw .github(http.statusCode) }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw .badResponse }
    }

    private static func fetch(_ request: URLRequest, session: URLSession) async throws(Failure) -> (Data, URLResponse) {
        do { return try await session.data(for: request) } catch { throw .offline }
    }

    /// profile.xml of a commit, read without downloading the rest (S-020).
    public static func profileInfo(commit: String, session: URLSession = .shared) async throws(Failure) -> ProfileInfo {
        var request = URLRequest(url: URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(commit)/profile.xml")!)
        request.setValue("AM2RLauncherPlus", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request, session: session)
        guard let http = response as? HTTPURLResponse else { throw .badResponse }
        guard http.statusCode == 200 else { throw .github(http.statusCode) }
        guard let info = profileInfo(String(decoding: data, as: UTF8.self)) else { throw .badResponse }
        return info
    }

    /// The manifest a finished download was made from, nil for a folder without one.
    public static func installedManifest(in patchFolder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: patchFolder.appending(path: "manifest.json")) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    // MARK: Download

    /// Downloads every file of the manifest into `folder/<commit>/`, reusing a finished download.
    /// Files go to a `.partial` folder first, so a cancelled download never looks complete.
    /// `progress` gets bytes done and bytes total.
    public static func download(_ manifest: Manifest, into folder: URL, session: URLSession = .shared,
                                progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> URL {
        let fm = FileManager.default
        let final = folder.appending(path: manifest.commit, directoryHint: .isDirectory)
        if fm.fileExists(atPath: final.appending(path: ".complete").path) { return final }
        let partial = folder.appending(path: manifest.commit + ".partial", directoryHint: .isDirectory)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)

        let total = manifest.totalSize
        var done = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = partial.appending(path: file.path)
            if fm.fileExists(atPath: destination.path), (try? blobSHA(of: Data(contentsOf: destination))) == file.blob {
                done += file.size
                progress?(done, total)
                continue
            }
            var request = URLRequest(url: URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(manifest.commit)/\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)")!)
            request.setValue("AM2RLauncherPlus", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await fetch(request, session: session)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.github((response as? HTTPURLResponse)?.statusCode ?? 0) }
            guard blobSHA(of: data) == file.blob else { throw Failure.corruptDownload(file.path) }
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            done += file.size
            progress?(done, total)
        }
        // Another download of the same commit may have finished first.
        if fm.fileExists(atPath: final.appending(path: ".complete").path) {
            try? fm.removeItem(at: partial)
            return final
        }
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: partial.appending(path: "manifest.json"))
        FileManager.default.createFile(atPath: partial.appending(path: ".complete").path, contents: nil)
        if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
        try fm.moveItem(at: partial, to: final)
        return final
    }

    /// Git's object hash: SHA-1 of "blob <size>\0" followed by the content.
    public static func blobSHA(of data: Data) -> String {
        var hasher = Insecure.SHA1()
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: profile.xml

    /// The attributes of the patch data's profile.xml, e.g. Version="1.5.5".
    public struct ProfileInfo: Equatable, Sendable {
        public var name: String
        public var version: String
        public var author: String
    }

    public static func profileInfo(_ xml: String) -> ProfileInfo? {
        guard let profile = ProfileXML(xml), let version = profile.version else { return nil }
        return ProfileInfo(name: profile.name ?? "Community Updates", version: version, author: profile.author)
    }
}
