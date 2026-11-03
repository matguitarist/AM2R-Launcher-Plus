import AM2RLauncherPlusKit
import AppKit
import IOKit.pwr_mgt
import SwiftData
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/AM2RLauncherPlus.app/Contents/MacOS/AM2RLauncherPlus
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction, openWindow: OpenWindowAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            // Welcome page states (S-001): welcome, welcome-checking, welcome-error, welcome-ready.
            let welcomeStates: [(String, WelcomeState)] = [
                ("welcome", .empty),
                ("welcome-checking", .checking("AM2R_11.zip")),
                ("welcome-error", .failed(.wrongDataWin, "AM2R_11.zip")),
                ("welcome-ready", .ready),
            ]
            let savedWelcome = model.welcome
            for (name, state) in welcomeStates where only?.contains(name) ?? true {
                model.sidebar = .play
                model.forceWelcome = true
                model.welcome = state
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(name)-\(mode).png")
                }
            }
            model.forceWelcome = false
            model.welcome = savedWelcome
            // Install states (S-002 to S-004): install-progress, install-error.
            var downloading = InstallState()
            downloading.bytesDone = 18_400_000
            downloading.bytesTotal = 36_300_000
            var failed = InstallState()
            failed.failure = PatchData.Failure.offline.message
            // S-033: a mod install, and a mod the native engine can't run.
            var modding = InstallState()
            modding.modZip = URL(fileURLWithPath: "/tmp/Sample Mod.zip")
            modding.modName = "Sample Mod 1.2"
            modding.step = .patch
            var modFailed = InstallState()
            modFailed.modZip = URL(fileURLWithPath: "/tmp/Fast Mod.zip")
            modFailed.failure = ModPackage.Failure.yyc(name: "Fast Mod").message
            for (name, state) in [("install-progress", downloading), ("install-error", failed),
                                  ("install-mod", modding), ("install-mod-error", modFailed)] where only?.contains(name) ?? true {
                model.sidebar = .play
                model.install = state
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(name)-\(mode).png")
                }
            }
            model.install = nil
            if only?.contains("play-mod") ?? true,
               let mod = ((try? model.container.mainContext.fetch(FetchDescriptor<Profile>())) ?? []).first(where: \.isMod) {
                let saved = model.selection
                model.sidebar = .play
                model.selection = mod.id
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/play-mod-\(mode).png")
                }
                model.selection = saved
            }
            if only?.contains("play-running") ?? true {
                model.sidebar = .play
                model.previewPlaying = true
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/play-running-\(mode).png")
                }
                model.previewPlaying = false
            }
            // S-023: saves-backups, the Saves Backups sheet with two backups.
            if let profile = model.currentProfile, only?.contains("saves-backups") ?? true {
                let saves = GameRunner.saveFolder(for: profile)
                try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
                try? Data("slot 1".utf8).write(to: saves.appending(path: "save1"))
                let folder = DataFolder.backups(for: profile.uuid)
                _ = try? SaveBackup.backup(saves: saves, into: folder, profileName: profile.name, date: .now.addingTimeInterval(-7 * 86_400))
                _ = try? SaveBackup.backup(saves: saves, into: folder, profileName: profile.name, label: "before restore")
                model.sidebar = .profiles
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.backupsFor = profile
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/saves-backups-\(mode).png", window: main?.attachedSheet)
                    model.backupsFor = nil
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
            // S-022: the delete dialog on the Profiles page.
            if let profile = model.currentProfile, only?.contains("profiles-delete") ?? true {
                model.sidebar = .profiles
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.deleteTarget = profile
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/profiles-delete-\(mode).png", window: main, withSheet: true)
                    model.deleteTarget = nil
                    try? await Task.sleep(for: .seconds(0.5))
                }
            }
            // S-020: update-banner, a newer release than the seeded profile.
            if only?.contains("update-banner") ?? true {
                model.sidebar = .play
                let saved = model.latestUpdate
                model.latestUpdate = UpdateCheck.Latest(manifest: PatchData.Manifest(commit: String(repeating: "6", count: 40), files: []),
                                                        version: "1.5.6", checkedAt: .now)
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/update-banner-\(mode).png")
                }
                model.latestUpdate = saved
            }
            // S-014: the engine picker when Rosetta isn't installed.
            if only?.contains("play-no-rosetta") ?? true {
                model.sidebar = .play
                let installed = model.rosettaInstalled
                model.rosettaInstalled = false
                // Tall enough to show the Engine section under the other settings.
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                let frame = main?.frame
                if let main, let screen = main.screen?.visibleFrame {
                    main.setFrame(NSRect(x: main.frame.minX, y: screen.minY, width: main.frame.width, height: screen.height), display: true)
                }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/play-no-rosetta-\(mode).png")
                }
                model.rosettaInstalled = installed
                if let main, let frame { main.setFrame(frame, display: true) }
            }
            // S-006: play-failed (banner) and log-sheet.
            if let profile = model.currentProfile, only?.contains("play-failed") ?? true || only?.contains("log-sheet") ?? true {
                let logs = GameRunner.logFolder(for: profile)
                try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let log = logs.appending(path: "2026-11-03T10-00-00Z.log")
                try? sampleLog.write(to: log, atomically: true, encoding: .utf8)
                model.sidebar = .play
                model.lastGameFailure = GameFailure(profile: profile.uuid, log: log, status: 1)
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    if only?.contains("play-failed") ?? true {
                        try? await Task.sleep(for: .seconds(0.8))
                        capture(to: "\(dir)/play-failed-\(mode).png")
                    }
                    if only?.contains("log-sheet") ?? true {
                        model.showLog()
                        try? await Task.sleep(for: .seconds(1))
                        let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                        capture(to: "\(dir)/log-sheet-\(mode).png", window: main?.attachedSheet)
                        model.logSheet = nil
                        try? await Task.sleep(for: .seconds(0.5))
                    }
                }
                model.lastGameFailure = nil
            }
            // The Log page with sample entries: log-launcher and log-game.
            if let profile = model.currentProfile, only?.contains("log-launcher") ?? true || only?.contains("log-game") ?? true {
                for (level, source, message) in sampleEvents { log(level, source, message) }
                let logs = GameRunner.logFolder(for: profile)
                try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                try? sampleGameLog.write(to: logs.appending(path: "2026-11-03T18-29-40.log"), atomically: true, encoding: .utf8)
                model.sidebar = .log
                for source in DebugLogSource.allCases where only?.contains("log-\(source.rawValue)") ?? true {
                    model.debugLogSource = source
                    for mode in ["light", "dark"] {
                        NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                        try? await Task.sleep(for: .seconds(1.5))
                        capture(to: "\(dir)/log-\(source.rawValue)-\(mode).png")
                    }
                }
                model.debugLogSource = .launcher
                model.sidebar = .play
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    private static let sampleEvents: [(DebugLog.Level, String, String)] = [
        (.info, "Source", "AM2R 1.1 accepted: /Users/player/Downloads/AM2R_11.zip (zip, with AM2R.exe)"),
        (.info, "Install", "Installing Community Updates from /Users/player/Downloads/AM2R_11.zip"),
        (.info, "Install", "Patch data 7e5ff84: 92 files, 36,3 MB"),
        (.info, "Install", "Community Updates 1.5.5 is ready"),
        (.warning, "Update", "Check failed: Unable to reach GitHub. Check your connection, then try again."),
        (.info, "Play", "Starting Community Updates 1.5.5 (1.5.5, Native)"),
        (.error, "Play", "The game ended after 42 s with status 1."),
        (.info, "Backups", "Backed up Community Updates 1.5.5"),
    ]

    private static let sampleGameLog = """
        Loading /Users/player/Library/Application Support/AM2RLauncherPlus/Profiles/game.ios...
        Loaded "AM2R" (971912648) successfully! [WAD Version 16 / GameMaker version 1.0.0.1763]
        VM: Initialized with 10122 functions mapped
        OpenGL Version: 2.1 Metal - 91.7
        GL: Compiling default vertex shader
        GL: Shader default succesfully linked!
        Warning: Runner: Builtin function string_split has the same name as a GML script!
        Warning: VM: [gml_Object_oControl_Step_0] Stubbed function "os_is_paused"!
        Warning: VM: [gml_Script_check_keys] Unknown function "gamepad_set_vibration"!
        Room changed: rm_loading -> titleroom
        Error: VM: surface_save is not implemented
        """

    private static let sampleLog = """
        Butterscotch \u{2014} GameMaker runner
        Loaded "AM2R" (bytecode 16, GMS 1.4.1804)
        Room: rm_subscreen
        Room: rm_a0h01
        ERROR: surface_save is not implemented
        Fatal error in action number 1 of Draw Event for object oControl
        """

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    /// `withSheet` captures the window's area of the screen, so an alert sheet on it shows too.
    private static func capture(to path: String, window: NSWindow? = nil, withSheet: Bool = false) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            if withSheet, let screen = NSScreen.screens.first {
                let f = window.frame
                shot.arguments = ["-x", "-R", "\(Int(f.minX)),\(Int(screen.frame.maxY - f.maxY)),\(Int(f.width)),\(Int(f.height))", path]
            } else {
                shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            }
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
