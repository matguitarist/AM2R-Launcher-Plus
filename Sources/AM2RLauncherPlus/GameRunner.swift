import AM2RLauncherPlusKit
import AppKit

/// Starts and watches the game for one profile (S-005).
/// Native: the bundled helper app Contents/Helpers/AM2R.app (Butterscotch, S-007).
/// Rosetta: the profile's own AM2R.app with the official runner, started with `open -W` (S-014).
@MainActor
final class GameRunner {
    let profileID: UUID
    let startedAt = Date.now
    let log: URL
    private let process: Process
    /// Set for Rosetta: `open` only waits, the game is the app with this bundle id.
    private let rosettaBundleID: String?
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
        case engineMissing, gameMissing, rosettaMissing, rosettaAppMissing, couldNotStart(String)

        var message: String {
            switch self {
            case .engineMissing: "Native engine not found. Reinstall AM2R Launcher Plus."
            case .rosettaMissing: "Rosetta isn't installed on this Mac. Install it, or choose the Native engine."
            case .rosettaAppMissing: "The Rosetta app of this profile is missing. Choose Native, then Rosetta again."
            case .gameMissing: "The game files of this profile are missing. Install it again."
            case .couldNotStart(let reason): "Unable to start AM2R: \(reason)"
            }
        }
    }

    /// Launches the game. `extraArguments` lets the self-test run the engine headless.
    /// `gamepadKeys` is BUTTERSCOTCH_GAMEPAD_KEYS, controller buttons that also press keys (S-011).
    init(profile: Profile, extraArguments: [String] = [], gamepadKeys: String? = nil, environment extra: [String: String] = [:], onExit: @escaping @MainActor (Int32) -> Void) throws(StartError) {
        let fm = FileManager.default
        let game = profile.folder.appending(path: "game.ios")
        guard fm.fileExists(atPath: game.path) else { throw .gameMissing }
        process = Process()
        switch profile.engine {
        case .native:
            guard let engine = Self.engine else { throw .engineMissing }
            process.executableURL = engine
            rosettaBundleID = nil
        case .rosetta:
            guard Rosetta.isInstalled else { throw .rosettaMissing }
            guard RosettaApp.app(in: profile.folder) != nil else { throw .rosettaAppMissing }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            rosettaBundleID = RosettaApp.bundleIdentifier(for: profile.uuid)
        }
        let saves = Self.saveFolder(for: profile)
        let logs = Self.logFolder(for: profile)
        try? fm.createDirectory(at: saves, withIntermediateDirectories: true)
        try? fm.createDirectory(at: logs, withIntermediateDirectories: true)
        Self.pruneLogs(in: logs, keep: 4)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        log = logs.appending(path: "\(stamp).log")
        fm.createFile(atPath: log.path, contents: nil)
        profileID = profile.uuid

        if let rosettaBundleID, let app = RosettaApp.app(in: profile.folder) {
            // The runner keeps saves in Application Support/<bundle id>: point that at the profile's save folder,
            // so both engines share one save folder and config.ini.
            do { try Self.linkRunnerData(Self.runnerDataFolder(bundleID: rosettaBundleID), to: saves) } catch {
                throw .couldNotStart(error.localizedDescription)
            }
            process.arguments = RosettaApp.openArguments(app: app, log: log)
        } else {
            process.currentDirectoryURL = profile.folder
            process.arguments = extraArguments + ["--save-folder", saves.path, game.path]
            var environment = ProcessInfo.processInfo.environment
            environment["BUTTERSCOTCH_GAMEPAD_KEYS"] = gamepadKeys
            environment.merge(extra) { _, new in new }
            process.environment = environment
            if let handle = try? FileHandle(forWritingTo: log) {
                process.standardOutput = handle
                process.standardError = handle
            }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor in onExit(status) }
        }
        do { try process.run() } catch { throw .couldNotStart(error.localizedDescription) }
    }

    /// Where the official runner keeps saves for a bundle id.
    static func runnerDataFolder(bundleID: String) -> URL {
        URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
    }

    /// Makes `link` a symlink to `saves`. A real folder the runner made earlier is merged into `saves` first.
    static func linkRunnerData(_ link: URL, to saves: URL) throws {
        let fm = FileManager.default
        if let target = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if target == saves.path { return }
            try fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            for item in try fm.contentsOfDirectory(at: link, includingPropertiesForKeys: nil) {
                let target = saves.appending(path: item.lastPathComponent)
                if !fm.fileExists(atPath: target.path) { try fm.moveItem(at: item, to: target) }
            }
            try fm.removeItem(at: link)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: saves)
    }

    var isRunning: Bool { process.isRunning }

    func stop() {
        stoppedByUser = true
        guard let rosettaBundleID else {
            process.terminate()
            return
        }
        // `open -W` ends when the app quits.
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: rosettaBundleID)
        apps.forEach { $0.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(3))
            apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }
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
