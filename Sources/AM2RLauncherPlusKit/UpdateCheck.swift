import Foundation

/// Whether a newer Community Updates release exists (S-020). Checked at most once a day; the answer is
/// kept in a small file so every profile can be compared offline until the next check.
public enum UpdateCheck {
    public static let interval: TimeInterval = 24 * 3600

    /// The newest patch data on GitHub when it was last checked.
    public struct Latest: Equatable, Sendable, Codable {
        public var manifest: PatchData.Manifest
        public var version: String
        public var checkedAt: Date

        public init(manifest: PatchData.Manifest, version: String, checkedAt: Date) {
            self.manifest = manifest
            self.version = version
            self.checkedAt = checkedAt
        }

        public var commit: String { manifest.commit }
    }

    /// True when there was no check yet, or the last one is a day old (or in the future: the clock moved).
    public static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        let age = now.timeIntervalSince(lastCheck)
        return age >= interval || age < 0
    }

    /// True when the latest patch data changes what a profile is built from. A commit that only touches
    /// the readme or the Android files isn't an update. `installed` is the profile's own manifest.
    public static func isNewer(_ latest: PatchData.Manifest, than installed: PatchData.Manifest?, installedCommit: String) -> Bool {
        guard !installedCommit.isEmpty, latest.commit != installedCommit else { return false }
        guard let installed else { return true }
        let game = { (manifest: PatchData.Manifest) in
            Dictionary(manifest.files.filter { PatchData.isNeeded($0.path, rosetta: false) }.map { ($0.path, $0.blob) }, uniquingKeysWith: { a, _ in a })
        }
        return game(latest) != game(installed)
    }

    /// The banner's words: "Community Updates 1.5.6 is available", or for a fix to the same version,
    /// "An update to Community Updates 1.5.5 is available".
    public static func title(latestVersion: String, installedVersion: String) -> String {
        latestVersion == installedVersion
            ? "An update to Community Updates \(latestVersion) is available"
            : "Community Updates \(latestVersion) is available"
    }

    /// Asks GitHub for the latest manifest; reads profile.xml only when its blob differs from `known`.
    public static func fetch(rosetta: Bool, known: Latest?, session: URLSession = .shared, now: Date = .now) async throws(PatchData.Failure) -> Latest {
        let manifest = try await PatchData.latestManifest(rosetta: rosetta, session: session)
        let blob = { (m: PatchData.Manifest) in m.files.first { $0.path == "profile.xml" }?.blob }
        if let known, blob(known.manifest) == blob(manifest) {
            return Latest(manifest: manifest, version: known.version, checkedAt: now)
        }
        let info = try await PatchData.profileInfo(commit: manifest.commit, session: session)
        return Latest(manifest: manifest, version: info.version, checkedAt: now)
    }

    public static func read(from file: URL) -> Latest? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Latest.self, from: data)
    }

    public static func write(_ latest: Latest, to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(latest).write(to: file, options: .atomic)
    }
}
