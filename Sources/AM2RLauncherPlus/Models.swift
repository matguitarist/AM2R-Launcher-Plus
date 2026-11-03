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

    init(container: ModelContainer) {
        self.container = container
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
