import AppKit
import SwiftData
import SwiftUI

// AM2RLauncherPlus
//   AM2RLauncherPlus                      the app
//   APP_STORE=<file> AM2RLauncherPlus     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> AM2RLauncherPlus   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 AM2RLauncherPlus           fill an empty /tmp store with sample profiles (tools/snap.sh)
//   AM2RLauncherPlus --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> AM2RLauncherPlus      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 AM2RLauncherPlus           draw the 8 pt grid and the layout probes over the window

@main
struct AM2RLauncherPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("AM2R Launcher Plus", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            // Install Profile… (⌘N) and Play (⌘P) arrive with S-001 and S-005.
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/AM2RLauncherPlus/AM2RLauncherPlus.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "AM2RLauncherPlus", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "AM2RLauncherPlus.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Profile.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
