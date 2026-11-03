import Foundation
import SwiftData
import AM2RLauncherPlusKit

/// What runs the game. See docs/GLOSSARY.md: "Native" and "Rosetta".
enum Engine: String, Codable, CaseIterable, Identifiable {
    case native, rosetta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native: "Native"
        case .rosetta: "Rosetta"
        }
    }

    var help: String {
        switch self {
        case .native: "Runs natively on Apple silicon"
        case .rosetta: "Runs the official game runner with Rosetta"
        }
    }
}

/// One installed, playable game with its own saves and settings.
@Model
final class Profile {
    var name: String
    /// Community Updates version from the patch data's profile.xml, e.g. "1.5.5".
    var version: String
    var engineRaw: String = Engine.native.rawValue
    /// Commit of the patch data this profile was installed from.
    var patchCommit: String = ""
    var installedAt: Date = Date.now
    var lastPlayedAt: Date?
    /// Total play time in seconds.
    var playTime: Double = 0
    /// A stable id for folders, links and the agent CLI.
    var uuid: UUID = UUID()

    var engine: Engine {
        get { Engine(rawValue: engineRaw) ?? .native }
        set { engineRaw = newValue.rawValue }
    }

    /// The installed game files: <data folder>/Profiles/<uuid>.
    var folder: URL { DataFolder.profiles.appending(path: uuid.uuidString, directoryHint: .isDirectory) }

    init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// The player's AM2R 1.1 copy (S-001). There is at most one.
@Model
final class GameSource {
    var path: String
    /// Bookmark so the copy is found again after it's renamed or moved on the same disk.
    var bookmark: Data?
    var kindRaw: String
    /// Folder inside the zip or folder that holds data.win ("" or "AM2R_11/").
    var root: String
    /// AM2R.exe is the 1.1 file, so the Rosetta engine can be built.
    var hasWindowsGame: Bool
    var checkedAt: Date = Date.now

    init(copy: AM2R11.Copy) {
        path = copy.url.path
        bookmark = try? copy.url.bookmarkData(options: .minimalBookmark)
        kindRaw = copy.kind.rawValue
        root = copy.root
        hasWindowsGame = copy.hasWindowsGame
    }

    /// The current location: follows the bookmark, falls back to the saved path.
    var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) { return resolved }
        }
        return URL(fileURLWithPath: path)
    }

    var name: String { url.lastPathComponent }
}

/// Where profiles, patch data, logs and caches live (S-013 makes it movable).
nonisolated enum DataFolder {
    static var url: URL {
        let base = Store.isOverridden
            ? Store.url.deletingLastPathComponent().appending(path: Store.url.deletingPathExtension().lastPathComponent + "-data", directoryHint: .isDirectory)
            : URL.applicationSupportDirectory.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var hashCache: URL { url.appending(path: "Caches/hashes.json") }
    static var patchData: URL { url.appending(path: "PatchData", directoryHint: .isDirectory) }
    static var profiles: URL { url.appending(path: "Profiles", directoryHint: .isDirectory) }
}

/// The welcome page's state while the player picks AM2R 1.1.
enum WelcomeState: Equatable {
    case empty
    case checking(String)
    case failed(AM2R11.Problem, String)
    case ready
}

/// Progress of installing Community Updates (S-002 to S-004).
struct InstallState: Equatable {
    enum Step: Int, CaseIterable, Comparable {
        case download, patch, copy

        var title: String {
            switch self {
            case .download: "Downloading patch data"
            case .patch: "Patching AM2R 1.1"
            case .copy: "Copying game files"
            }
        }

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    var step: Step = .download
    var bytesDone = 0
    var bytesTotal = 0
    var failure: String?
    /// Set when the profile is ready; the page shows it briefly, then Play.
    var finishedName: String?
}

/// A game run that ended with an error (S-006).
struct GameFailure: Equatable {
    var profile: UUID
    var log: URL
    var status: Int32
}

/// What the log sheet shows.
struct LogSheetItem: Identifiable, Equatable {
    var log: URL
    var profileName: String
    var id: URL { log }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case play, profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: "Play"
        case .profiles: "Profiles"
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.circle"
        case .profiles: "square.stack"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .play
    var selection: PersistentIdentifier?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    var welcome: WelcomeState = .empty
    var install: InstallState?
    /// The running game, if any (S-005).
    var game: GameRunner?
    /// Set when the game quit with an error (S-006 shows it with the log).
    var lastGameFailure: GameFailure?
    /// The log shown in the log sheet (S-006).
    var logSheet: LogSheetItem?
    var playError: String?
    /// Asks before stopping a running game.
    var confirmStop = false
    /// Snapshot mode shows the "Playing…" state without starting the game.
    var previewPlaying = false
    var isPlaying: Bool { game != nil || previewPlaying }
    private var installTask: Task<Void, Never>?
    /// Opens the file chooser for AM2R 1.1 (File > Choose AM2R 1.1…, ⌘O).
    var showChooser = false
    /// Snapshot mode shows the welcome page even when profiles exist.
    var forceWelcome = false
    private let hashCache = HashCache(file: DataFolder.hashCache)

    init(container: ModelContainer) {
        self.container = container
        if source != nil { welcome = .ready }
    }

    var source: GameSource? {
        (try? container.mainContext.fetch(FetchDescriptor<GameSource>()))?.first
    }

    /// Checks a zip or folder and, when it's AM2R 1.1, keeps it as the game source (S-001).
    func choose(_ url: URL) async {
        welcome = .checking(url.lastPathComponent)
        let cache = hashCache
        let result = await Task.detached(priority: .userInitiated) { () -> Result<AM2R11.Copy, AM2R11.Problem> in
            Result { () throws(AM2R11.Problem) in try AM2R11.check(url, cache: cache) }
        }.value
        switch result {
        case .success(let copy):
            let context = container.mainContext
            for old in (try? context.fetch(FetchDescriptor<GameSource>())) ?? [] { context.delete(old) }
            context.insert(GameSource(copy: copy))
            try? context.save()
            welcome = .ready
        case .failure(let problem):
            welcome = .failed(problem, url.lastPathComponent)
        }
    }

    /// Downloads the patch data, patches AM2R 1.1 and adds the new profile (S-002 to S-004).
    func startInstall() {
        guard let source, installTask == nil else { return }
        install = InstallState()
        let sourceURL = source.url, kind = AM2R11.Kind(rawValue: source.kindRaw) ?? .zip, root = source.root
        let rosetta = source.hasWindowsGame
        installTask = Task {
            defer { installTask = nil }
            do {
                let manifest = try await PatchData.latestManifest(rosetta: rosetta)
                install?.bytesTotal = manifest.totalSize
                let patchFolder = try await PatchData.download(manifest, into: DataFolder.patchData) { done, total in
                    Task { @MainActor in self.install?.bytesDone = done; self.install?.bytesTotal = total }
                }
                try Task.checkCancellation()
                install?.step = .patch
                let uuid = UUID()
                let destination = DataFolder.profiles.appending(path: uuid.uuidString, directoryHint: .isDirectory)
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProfileBuilder.build(source: sourceURL, kind: kind, root: root, patchData: patchFolder, destination: destination) { step in
                        if step == .copy { Task { @MainActor in self.install?.step = .copy } }
                    }
                }.value
                let profile = addProfile(name: "Community Updates \(result.info.version)", version: result.info.version)
                profile.uuid = uuid
                profile.patchCommit = manifest.commit
                try? container.mainContext.save()
                install?.finishedName = profile.name
                try? await Task.sleep(for: .seconds(1))
                install = nil
                sidebar = .play
            } catch is CancellationError {
                install = nil
            } catch let failure as PatchData.Failure {
                install?.failure = failure.message
            } catch let failure as ProfileBuilder.Failure {
                install?.failure = failure.message
            } catch {
                install?.failure = "Unable to install: \(error.localizedDescription)"
            }
        }
    }

    /// Stops an install; partial files are removed or reused by the next try.
    func cancelInstall() {
        installTask?.cancel()
        if install?.failure != nil { install = nil }
    }

    /// The selected profile, or the most recently installed one.
    var currentProfile: Profile? {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.installedAt, order: .reverse)]))) ?? []
        return all.first { $0.id == selection } ?? all.first
    }

    /// Plays the current profile on the native engine (S-005).
    func play(extraArguments: [String] = []) {
        guard game == nil, let profile = currentProfile else { return }
        playError = nil
        lastGameFailure = nil
        do {
            game = try GameRunner(profile: profile, extraArguments: extraArguments) { [weak self] status in
                self?.gameEnded(status: status)
            }
        } catch {
            playError = error.message
        }
    }

    func stopGame() {
        game?.stop()
    }

    /// The log to show for the current profile: the failed run's, or else the newest.
    var currentLog: URL? {
        guard let profile = currentProfile else { return nil }
        if let failure = lastGameFailure, failure.profile == profile.uuid { return failure.log }
        return LogTail.newest(in: GameRunner.logFolder(for: profile))
    }

    /// Game > Show Log (⌘L) and the failure banner's Show Log.
    func showLog() {
        guard let profile = currentProfile, let log = currentLog else { return }
        sidebar = .play
        logSheet = LogSheetItem(log: log, profileName: profile.name)
    }

    private func gameEnded(status: Int32) {
        guard let game else { return }
        let profiles = (try? container.mainContext.fetch(FetchDescriptor<Profile>())) ?? []
        if let profile = profiles.first(where: { $0.uuid == game.profileID }) {
            profile.playTime += Date.now.timeIntervalSince(game.startedAt)
            profile.lastPlayedAt = .now
            try? container.mainContext.save()
        }
        if status != 0 && !game.stoppedByUser {
            lastGameFailure = GameFailure(profile: game.profileID, log: game.log, status: status)
        }
        self.game = nil
    }

    /// Records an installed profile and selects it. The install itself (S-002 to S-004) calls this when done.
    @discardableResult
    func addProfile(name: String, version: String) -> Profile {
        let profile = Profile(name: ProfileName.clean(name), version: version)
        container.mainContext.insert(profile)
        // Saving first gives the profile its permanent id; a temporary one would leave the selection dangling.
        try? container.mainContext.save()
        selection = profile.id
        return profile
    }
}
