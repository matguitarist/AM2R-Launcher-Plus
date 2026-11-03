import AM2RLauncherPlusKit
import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/AM2RLauncherPlus.app/Contents/MacOS/AM2RLauncherPlus
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
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
            for (name, state) in [("install-progress", downloading), ("install-error", failed)] where only?.contains(name) ?? true {
                model.sidebar = .play
                model.install = state
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(name)-\(mode).png")
                }
            }
            model.install = nil
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
    private static func capture(to path: String, window: NSWindow? = nil) {
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
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
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
