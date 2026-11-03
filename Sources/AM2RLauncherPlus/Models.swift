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

/// Rosetta 2 on this Mac (S-014). APP_ROSETTA=missing shows the not-installed state in snapshots.
enum Rosetta {
    static var isInstalled: Bool {
        ProcessInfo.processInfo.environment["APP_ROSETTA"] == "missing" ? false : RosettaApp.isRosettaInstalled
    }
}

/// Why a profile can't use Rosetta (S-014), shown under the engine picker.
struct EngineError: Equatable {
    var profile: UUID
    var message: String
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
    /// The Mac controller layout was written once (S-011); after that the player's choice stands.
    var controllerLayoutSet: Bool = false
    /// Scanlines or CRT drawn over the game by the engine.
    var displayFilterRaw: String = DisplayFilter.none.rawValue

    var displayFilter: DisplayFilter {
        get { DisplayFilter(rawValue: displayFilterRaw) ?? .none }
        set { displayFilterRaw = newValue.rawValue }
    }

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

/// Where profiles, patch data, saves, logs and caches live. The player can move it (S-013).
nonisolated enum DataFolder {
    static let defaultsKey = "dataFolder"
    /// Test and snapshot runs keep their moved location in memory, never in the real defaults.
    nonisolated(unsafe) static var testLocation: URL?

    static var defaultURL: URL {
        Store.isOverridden
            ? Store.url.deletingLastPathComponent().appending(path: Store.url.deletingPathExtension().lastPathComponent + "-data", directoryHint: .isDirectory)
            : URL.applicationSupportDirectory.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
    }

    /// The chosen location, or the default.
    static var url: URL {
        let chosen = Store.isOverridden ? testLocation : UserDefaults.standard.string(forKey: defaultsKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let base = chosen ?? defaultURL
        // Never recreate a folder on a disk that's unplugged: that would make a fake /Volumes/<disk>.
        if FileManager.default.fileExists(atPath: base.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        }
        return base
    }

    /// Remembers a new location; the default location is stored as no choice.
    static func setLocation(_ url: URL) {
        let isDefault = url.standardizedFileURL.path == defaultURL.standardizedFileURL.path
        if Store.isOverridden {
            testLocation = isDefault ? nil : url
        } else if isDefault {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(url.path, forKey: defaultsKey)
        }
    }

    /// The data was on a disk that isn't connected now.
    static var isMissing: Bool {
        let chosen = Store.isOverridden ? testLocation : UserDefaults.standard.string(forKey: defaultsKey).map { URL(fileURLWithPath: $0) }
        guard let chosen else { return false }
        return !FileManager.default.fileExists(atPath: chosen.deletingLastPathComponent().path)
    }

    static var hashCache: URL { url.appending(path: "Caches/hashes.json") }
    /// The last update check (S-020).
    static var latestUpdate: URL { url.appending(path: "Caches/latest-update.json") }
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
    /// Updating this profile in place (S-021) instead of installing a new one.
    var updating: UUID?
    var updatingName: String?
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
    private var hashCache = HashCache(file: DataFolder.hashCache)
    /// Moving the data folder (S-013): bytes done and total, or a failure.
    var dataMove: (done: Int64, total: Int64)?
    var dataMoveError: String?
    /// The profile whose Rosetta app is being built (S-014).
    var rosettaBuild: UUID?
    var engineError: EngineError?
    var rosettaInstalled = Rosetta.isInstalled
    var installingRosetta = false
    /// Asks before installing Rosetta (engine picker, Game > Engine > Install Rosetta…).
    var confirmRosettaInstall = false
    var rosettaInstallError: String?
    /// The newest patch data on GitHub at the last check (S-020).
    var latestUpdate: UpdateCheck.Latest? = UpdateCheck.read(from: DataFolder.latestUpdate)
    var checkingForUpdates = false
    /// Only a check the player asked for reports a failure or "up to date".
    var updateCheckMessage: String?

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
    /// With `updating`, rebuilds that profile from the latest patch data instead (S-021): the new files are
    /// built beside the old ones and swapped in only when complete; saves and config.ini live elsewhere.
    func startInstall(updating: UUID? = nil) {
        guard let source, installTask == nil, game == nil else { return }
        let existing = updating.flatMap { id in ((try? container.mainContext.fetch(FetchDescriptor<Profile>())) ?? []).first { $0.uuid == id } }
        if updating != nil && existing == nil { return }
        var state = InstallState()
        state.updating = existing?.uuid
        state.updatingName = existing?.name
        install = state
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
                let uuid = existing?.uuid ?? UUID()
                let destination = DataFolder.profiles.appending(path: uuid.uuidString, directoryHint: .isDirectory)
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProfileBuilder.build(source: sourceURL, kind: kind, root: root, patchData: patchFolder, destination: destination) { step in
                        if step == .copy { Task { @MainActor in self.install?.step = .copy } }
                    }
                }.value
                let profile: Profile
                if let existing {
                    // A name the app gave follows the version; a name the player chose stays.
                    if existing.name == "Community Updates \(existing.version)" { existing.name = "Community Updates \(result.info.version)" }
                    existing.version = result.info.version
                    existing.patchCommit = manifest.commit
                    profile = existing
                    // The swap replaced the Rosetta app too; build it again from the new files.
                    if existing.engine == .rosetta, await !useRosetta(existing) { existing.engine = .native }
                } else {
                    profile = addProfile(name: "Community Updates \(result.info.version)", version: result.info.version)
                    profile.uuid = uuid
                    applyFirstSettings(to: profile)
                }
                profile.patchCommit = manifest.commit
                try? container.mainContext.save()
                selection = profile.id
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

    /// New profiles start with the Mac controller layout: Select = map, Start = pause (S-011).
    func applyFirstSettings(to profile: Profile) {
        guard !profile.controllerLayoutSet else { return }
        let saves = GameRunner.saveFolder(for: profile)
        var settings = GameSettings.read(from: saves)
        settings.controller = .mac
        try? settings.write(to: saves)
        profile.controllerLayoutSet = true
        try? container.mainContext.save()
    }

    /// Plays the current profile on its engine (S-005, S-014).
    func play(extraArguments: [String] = []) {
        guard game == nil, let profile = currentProfile else { return }
        playError = nil
        lastGameFailure = nil
        applyFirstSettings(to: profile)
        let settings = GameSettings.read(from: GameRunner.saveFolder(for: profile))
        // Keeps the layout's keys current, e.g. a profile set up by an earlier build of the Mac layout.
        if settings.controller == .mac { try? settings.write(to: GameRunner.saveFolder(for: profile)) }
        do {
            game = try GameRunner(profile: profile, extraArguments: extraArguments,
                                  gamepadKeys: settings.controller.engineKeys,
                                  environment: profile.displayFilter.engineEnvironment) { [weak self] status in
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

    /// Asks GitHub for the latest patch data, at most daily unless `force` (Game > Check for Game Updates).
    func checkForUpdates(force: Bool = false) async {
        guard !checkingForUpdates, force || UpdateCheck.isDue(lastCheck: latestUpdate?.checkedAt) else { return }
        guard ((try? container.mainContext.fetchCount(FetchDescriptor<Profile>())) ?? 0) > 0 else { return }
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        updateCheckMessage = nil
        do {
            let latest = try await UpdateCheck.fetch(rosetta: source?.hasWindowsGame ?? false, known: latestUpdate)
            latestUpdate = latest
            try? UpdateCheck.write(latest, to: DataFolder.latestUpdate)
            if force, let profile = currentProfile, availableUpdate(for: profile) == nil {
                updateCheckMessage = "\(profile.name) is up to date."
            }
        } catch {
            if force { updateCheckMessage = error.message }
        }
    }

    /// The banner's title when the latest patch data is newer than what `profile` was built from.
    func availableUpdate(for profile: Profile) -> String? {
        guard let latestUpdate else { return nil }
        let installed = PatchData.installedManifest(in: DataFolder.patchData.appending(path: profile.patchCommit, directoryHint: .isDirectory))
        guard UpdateCheck.isNewer(latestUpdate.manifest, than: installed, installedCommit: profile.patchCommit) else { return nil }
        return UpdateCheck.title(latestVersion: latestUpdate.version, installedVersion: profile.version)
    }

    /// Game > Engine and the engine picker (S-014). Rosetta builds the profile's AM2R.app first, once.
    func setEngine(_ engine: Engine, for profile: Profile) {
        guard !isPlaying, rosettaBuild == nil, engine != profile.engine else { return }
        engineError = nil
        if engine == .native || RosettaApp.app(in: profile.folder) != nil {
            profile.engine = engine
            try? container.mainContext.save()
        } else {
            Task { await useRosetta(profile) }
        }
    }

    /// Builds `<profile>/AM2R.app` from AM2R 1.1's AM2R.exe and the profile's patch data, then switches to Rosetta.
    @discardableResult
    func useRosetta(_ profile: Profile) async -> Bool {
        guard rosettaBuild == nil else { return false }
        guard let source, source.hasWindowsGame else {
            engineError = EngineError(profile: profile.uuid, message: RosettaApp.Failure.noWindowsGame.message)
            return false
        }
        guard !profile.patchCommit.isEmpty else {
            engineError = EngineError(profile: profile.uuid, message: RosettaApp.Failure.noRunnerPatch.message)
            return false
        }
        rosettaBuild = profile.uuid
        defer { rosettaBuild = nil }
        let sourceURL = source.url, kind = AM2R11.Kind(rawValue: source.kindRaw) ?? .zip, root = source.root
        let patch = DataFolder.patchData.appending(path: profile.patchCommit, directoryHint: .isDirectory)
        let folder = profile.folder, id = RosettaApp.bundleIdentifier(for: profile.uuid)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, RosettaApp.Failure> in
            Result { () throws(RosettaApp.Failure) in
                try RosettaApp.build(source: sourceURL, kind: kind, root: root, patchData: patch, profileFolder: folder, bundleIdentifier: id)
            }
        }.value
        switch result {
        case .success:
            profile.engine = .rosetta
            try? container.mainContext.save()
            return true
        case .failure(let failure):
            engineError = EngineError(profile: profile.uuid, message: failure.message)
            return false
        }
    }

    /// Installs Rosetta 2 with Apple's softwareupdate, after the system asks for an administrator password.
    func installRosetta() async {
        guard !installingRosetta else { return }
        installingRosetta = true
        rosettaInstallError = nil
        let output = await Task.detached { () -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
        installingRosetta = false
        rosettaInstalled = Rosetta.isInstalled
        // -128: the person cancelled the password prompt.
        if !rosettaInstalled && !output.contains("-128") {
            rosettaInstallError = "Unable to install Rosetta. Check your connection, then try again."
        }
    }

    /// Moves the data folder into `parent` (S-013). Not while the game runs or an install is going.
    func moveDataFolder(into parent: URL) async {
        guard game == nil, install == nil, dataMove == nil else { return }
        dataMoveError = nil
        dataMove = (0, 0)
        let source = DataFolder.url
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, FolderMove.Failure> in
            Result { () throws(FolderMove.Failure) in
                try FolderMove.move(source, into: parent) { done, total in
                    Task { @MainActor in self.dataMove = (done, total) }
                }
            }
        }.value
        switch result {
        case .success(let moved):
            DataFolder.setLocation(moved)
            hashCache = HashCache(file: DataFolder.hashCache)
        case .failure(let failure):
            dataMoveError = failure.message
        }
        dataMove = nil
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
