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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { LauncherUpdater.shared.checkForUpdates() }
                    .disabled(!LauncherUpdater.shared.canCheck)
            }
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Choose AM2R 1.1…") { model.showChooser = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { model.sidebar = page }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Divider()
            }
            CommandMenu("Profile") {
                Button("Install Mod…") { model.showModChooser = true }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                    .disabled(model.source == nil || model.install != nil || model.isPlaying)
                    .help(model.source == nil ? "Install AM2R first" : "Install an AM2R mod zip as its own profile")
                Divider()
                let profile = model.currentProfile
                let off = profile == nil || model.renameTarget != nil || model.install != nil || model.backupsFor != nil
                Button("Rename…") { model.renameTarget = profile }
                    .keyboardShortcut("r")
                    .disabled(off)
                Button("Duplicate") { if let profile { model.startDuplicate(profile) } }
                    .keyboardShortcut("d")
                    .disabled(off || model.duplicating)
                Button("Show in Finder") { if let profile { model.reveal(profile) } }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(off)
                Divider()
                Button("Back Up Saves") { if let profile { model.startBackup(profile) } }
                    .keyboardShortcut("b")
                    .disabled(off || model.backingUp)
                Button("Saves Backups…") { model.backupsFor = profile }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(off)
                Divider()
                Button("Delete…") { model.deleteTarget = profile }
                    .keyboardShortcut(.delete)
                    .disabled(off || (model.game != nil && model.game?.profileID == profile?.uuid))
            }
            CommandMenu("Game") {
                Button("Play") { model.play() }
                    .keyboardShortcut("p")
                    .disabled(model.game != nil || model.currentProfile == nil)
                Button("Stop") { model.confirmStop = true; model.sidebar = .play }
                    .keyboardShortcut(".")
                    .disabled(model.game == nil)
                Button(model.checkingForUpdates ? "Checking for Game Updates…" : "Check for Game Updates") {
                    model.sidebar = .play
                    Task { await model.checkForUpdates(force: true) }
                }
                .keyboardShortcut("u")
                .disabled(model.checkingForUpdates || model.currentProfile == nil)
                Button("Update Profile") {
                    if let profile = model.currentProfile { model.sidebar = .play; model.startInstall(updating: profile.uuid) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model.isPlaying || model.install != nil || model.source == nil
                          || model.currentProfile.flatMap { model.availableUpdate(for: $0) } == nil)
                Divider()
                Menu("Engine") {
                    ForEach(Engine.allCases) { engine in
                        Toggle(engine.title, isOn: Binding(
                            get: { model.currentProfile?.engine == engine },
                            set: { _ in if let profile = model.currentProfile { model.setEngine(engine, for: profile) } }))
                            .keyboardShortcut(engine == .native ? "1" : "2", modifiers: [.command, .option])
                            .disabled(model.isPlaying || model.rosettaBuild != nil
                                      || (engine == .rosetta && (model.currentProfile?.isMod == true
                                          || !(model.rosettaInstalled && model.source?.hasWindowsGame == true))))
                    }
                    if !model.rosettaInstalled {
                        Divider()
                        Button("Install Rosetta…") { model.sidebar = .play; model.confirmRosettaInstall = true }
                            .disabled(model.installingRosetta)
                    }
                }
                .disabled(model.currentProfile == nil)
                Divider()
                Button("Show Log") { model.showLog() }
                    .keyboardShortcut("l")
                    .disabled(model.currentLog == nil)
                Button("Debug Log") { model.sidebar = .log }
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
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
nonisolated enum Store {
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
            return try ModelContainer(for: Profile.self, GameSource.self, configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
