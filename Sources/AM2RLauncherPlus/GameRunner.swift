import Foundation

/// Starts and watches the game for one profile (S-005).
/// The engine is the bundled helper app Contents/Helpers/AM2R.app (Butterscotch, S-007).
@MainActor
final class GameRunner {
    let profileID: UUID
    let startedAt = Date.now
    let log: URL
    private let process: Process
    private(set) var stoppedByUser = false

    /// The engine inside this app. Nil when it's missing (a dev build without the helper).
    static var engine: URL? {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Helpers/AM2R.app/Contents/MacOS/butterscotch")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Saves live outside the game files, so updating a profile never touches them.
    static func saveFolder(for profile: Profile) -> URL {
        DataFolder.url.appending(path: "Saves/\(profile.uuid.uuidString)", directoryHint: .isDirectory)
    }

    static func logFolder(for profile: Profile) -> URL {
        DataFolder.url.appending(path: "Logs/\(profile.uuid.uuidString)", directoryHint: .isDirectory)
    }

    enum StartError: Error {
        case engineMissing, gameMissing, couldNotStart(String)

        var message: String {
            switch self {
            case .engineMissing: "Native engine not found. Reinstall AM2R Launcher Plus."
            case .gameMissing: "The game files of this profile are missing. Install it again."
            case .couldNotStart(let reason): "Unable to start AM2R: \(reason)"
            }
        }
    }

    /// Launches the game. `extraArguments` lets the self-test run the engine headless.
    init(profile: Profile, extraArguments: [String] = [], onExit: @escaping @MainActor (Int32) -> Void) throws(StartError) {
        guard let engine = Self.engine else { throw .engineMissing }
        let game = profile.folder.appending(path: "game.ios")
        guard FileManager.default.fileExists(atPath: game.path) else { throw .gameMissing }
        let fm = FileManager.default
        let saves = Self.saveFolder(for: profile)
        let logs = Self.logFolder(for: profile)
        try? fm.createDirectory(at: saves, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        Self.pruneLogs(in: logs, keep: 4)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        log = logs.appending(path: "\(stamp).log")
        fm.createFile(atPath: log.path, contents: nil)

        profileID = profile.uuid
        process = Process()
        process.executableURL = engine
        process.currentDirectoryURL = profile.folder
        process.arguments = extraArguments + ["--save-folder", saves.path, game.path]
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in onExit(status) }
        }
        do { try process.run() } catch { throw .couldNotStart(error.localizedDescription) }
    }

    var isRunning: Bool { process.isRunning }

    func stop() {
        stoppedByUser = true
        process.terminate()
    }

    /// Keeps the newest `keep` logs, so with the new one there are at most keep + 1.
    static func pruneLogs(in folder: URL, keep: Int) {
        let fm = FileManager.default
        let logs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(keep) { try? fm.removeItem(at: old) }
    }
}
