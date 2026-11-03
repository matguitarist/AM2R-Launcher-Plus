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
enum DataFolder {
    static var url: URL {
        let base = Store.isOverridden
            ? Store.url.deletingLastPathComponent().appending(path: Store.url.deletingPathExtension().lastPathComponent + "-data", directoryHint: .isDirectory)
            : URL.applicationSupportDirectory.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var hashCache: URL { url.appending(path: "Caches/hashes.json") }
}

/// The welcome page's state while the player picks AM2R 1.1.
enum WelcomeState: Equatable {
    case empty
    case checking(String)
    case failed(AM2R11.Problem, String)
    case ready
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

    /// Records an installed profile and selects it. The install itself (S-002 to S-004) calls this when done.
    @discardableResult
    func addProfile(name: String, version: String) -> Profile {
        let profile = Profile(name: ProfileName.clean(name), version: version)
        container.mainContext.insert(profile)
        selection = profile.id
        return profile
    }
}
