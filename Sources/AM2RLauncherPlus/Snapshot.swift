import AM2RLauncherPlusKit
import AppKit
import AppTestKit
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
        // Snapshots never run against the real database: without APP_STORE in /tmp, this refuses and quits.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            await run.start()
            await run.shootPages(SidebarItem.allCases.map(\.rawValue)) { model.sidebar = SidebarItem(rawValue: $0)! }
            // Welcome page states (S-001): welcome, welcome-checking, welcome-error, welcome-ready.
            let welcomeStates: [(String, WelcomeState)] = [
                ("welcome", .empty),
                ("welcome-checking", .checking("AM2R_11.zip")),
                ("welcome-error", .failed(.wrongDataWin, "AM2R_11.zip")),
                ("welcome-ready", .ready),
            ]
            let savedWelcome = model.welcome
            for (name, state) in welcomeStates {
                await run.shoot(name, settle: .seconds(0.8)) {
                    model.sidebar = .play
                    model.forceWelcome = true
                    model.welcome = state
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
            // S-036: a Randovania export being imported, and a folder with no seed.
            var importing = InstallState()
            importing.importFolder = URL(fileURLWithPath: "/tmp/My Seed")
            importing.modName = "Randovania Chozo Baby Spider"
            importing.step = .copy
            var importFailed = InstallState()
            importFailed.importFolder = URL(fileURLWithPath: "/tmp/Downloads")
            importFailed.step = .copy
            importFailed.failure = RandovaniaGame.Failure.notAnExport.message
            for (name, state) in [("install-progress", downloading), ("install-error", failed),
                                  ("install-mod", modding), ("install-mod-error", modFailed),
                                  ("install-randovania", importing), ("install-randovania-error", importFailed)] {
                await run.shoot(name, settle: .seconds(0.8)) {
                    model.sidebar = .play
                    model.install = state
                }
            }
            model.install = nil
            if run.wantsAny(["play-mod", "play-mod-full"]),
               let mod = ((try? model.container.mainContext.fetch(FetchDescriptor<Profile>())) ?? []).first(where: \.isMod) {
                let saved = model.selection
                model.sidebar = .play
                model.selection = mod.id
                await run.shoot("play-mod", settle: .seconds(0.8))
                // S-042: the whole page, down to the Engine section's note, in a tall window, in light only.
                if run.wants("play-mod-full"), let window = WindowShot.mainWindow() {
                    let frame = window.frame
                    let tall = min(1500, (window.screen ?? NSScreen.main)?.visibleFrame.height ?? frame.height)
                    window.setFrame(NSRect(x: frame.minX, y: frame.maxY - tall, width: frame.width, height: tall), display: true)
                    Appearance.light.apply()
                    await run.pause()
                    await run.capture("play-mod-full", .light)
                    window.setFrame(frame, display: true)
                }
                model.selection = saved
            }
            // S-040: the whole Extras page, Randomizer and Save Slots included, in a window tall enough to hold it.
            if run.wants("extras-randomizer"), let window = WindowShot.mainWindow() {
                let frame = window.frame
                let tall = min(1500, (window.screen ?? NSScreen.main)?.visibleFrame.height ?? frame.height)
                window.setFrame(NSRect(x: frame.minX, y: frame.maxY - tall, width: frame.width, height: tall), display: true)
                await run.shoot("extras-randomizer", settle: .seconds(0.8)) { model.sidebar = .extras }
                window.setFrame(frame, display: true)
            }
            await run.shoot("play-running", settle: .seconds(0.8)) {
                model.sidebar = .play
                model.previewPlaying = true
            }
            model.previewPlaying = false
            // S-023: saves-backups, the Saves Backups sheet with two backups.
            if let profile = model.currentProfile, run.wants("saves-backups") {
                let saves = GameRunner.saveFolder(for: profile)
                try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
                try? Data("slot 1".utf8).write(to: saves.appending(path: "save1"))
                let folder = DataFolder.backups(for: profile.uuid)
                _ = try? await SaveBackup.backup(saves: saves, into: folder, profileName: profile.name, date: .now.addingTimeInterval(-7 * 86_400))
                _ = try? await SaveBackup.backup(saves: saves, into: folder, profileName: profile.name, label: "before restore")
                model.sidebar = .profiles
                await run.shoot("saves-backups", window: { WindowShot.mainWindow()?.attachedSheet },
                                show: { model.backupsFor = profile }, hide: { model.backupsFor = nil })
            }
            // S-022: the delete dialog on the Profiles page, its sheet over the window.
            if let profile = model.currentProfile {
                await run.shoot("profiles-delete", area: .screen,
                                show: { model.sidebar = .profiles; model.deleteTarget = profile }, hide: { model.deleteTarget = nil })
            }
            // S-020: update-banner, a newer release than the seeded profile.
            if run.wants("update-banner") {
                let saved = model.latestUpdate
                await run.shoot("update-banner", settle: .seconds(0.8)) {
                    model.sidebar = .play
                    model.latestUpdate = UpdateCheck.Latest(manifest: PatchData.Manifest(commit: String(repeating: "6", count: 40), files: []),
                                                            version: "1.5.6", checkedAt: .now)
                }
                model.latestUpdate = saved
            }
            // S-014: the engine picker when Rosetta isn't installed.
            if run.wants("play-no-rosetta") {
                model.sidebar = .play
                let installed = model.rosettaInstalled
                model.rosettaInstalled = false
                // Tall enough to show the Engine section under the other settings.
                let main = WindowShot.mainWindow()
                let frame = main?.frame
                if let main, let screen = main.screen?.visibleFrame {
                    main.setFrame(NSRect(x: main.frame.minX, y: screen.minY, width: main.frame.width, height: screen.height), display: true)
                }
                await run.shoot("play-no-rosetta", settle: .seconds(0.8))
                model.rosettaInstalled = installed
                if let main, let frame { main.setFrame(frame, display: true) }
            }
            // S-006: play-failed (banner) and log-sheet.
            if let profile = model.currentProfile, run.wantsAny(["play-failed", "log-sheet"]) {
                let logs = GameRunner.logFolder(for: profile)
                try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let log = logs.appending(path: "2026-11-03T10-00-00Z.log")
                try? sampleLog.write(to: log, atomically: true, encoding: .utf8)
                model.sidebar = .play
                model.lastGameFailure = GameFailure(profile: profile.uuid, log: log, status: 1)
                await run.shoot("play-failed", settle: .seconds(0.8))
                await run.shoot("log-sheet", window: { WindowShot.mainWindow()?.attachedSheet },
                                show: { model.showLog() }, hide: { model.logSheet = nil })
                model.lastGameFailure = nil
            }
            // The Log page with sample entries: log-launcher, log-game and log-rooms (S-043).
            if let profile = model.currentProfile, run.wantsAny(DebugLogSource.allCases.map { "log-\($0.rawValue)" } + ["log-rooms-off"]) {
                let saves = GameRunner.saveFolder(for: profile)
                try? RoomLog.set(true, saves: saves)
                try? sampleRoomLog.write(to: RoomLog.file(in: saves), atomically: true, encoding: .utf8)
                for (level, source, message) in sampleEvents { log(level, source, message) }
                let logs = GameRunner.logFolder(for: profile)
                try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                try? sampleGameLog.write(to: logs.appending(path: "2026-11-03T18-29-40.log"), atomically: true, encoding: .utf8)
                model.sidebar = .log
                for source in DebugLogSource.allCases {
                    await run.shoot("log-\(source.rawValue)", settle: .seconds(1.5)) { model.debugLogSource = source }
                }
                if run.wants("log-rooms-off") {
                    try? RoomLog.set(false, saves: saves)
                    model.debugLogSource = .game
                    try? await Task.sleep(for: .seconds(0.3))
                    model.debugLogSource = .rooms
                    await run.shoot("log-rooms-off")
                }
                model.debugLogSource = .launcher
                model.sidebar = .play
            }
            await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                    select: { model.settingsTab = SettingsTab(rawValue: $0)! })
            run.finish()
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

    /// A short trip from the title screen into Area 1, as the game writes am2r_log.txt (room numbers match SeedData's game).
    static let sampleRoomLog = """
        November 18th 2026, 14:02.51: Options Loaded
        November 18th 2026, 14:02.51: Loading Room 0
        November 18th 2026, 14:02.53: UnLoading Room 0
        November 18th 2026, 14:02.53: Loading Room 1
        November 18th 2026, 14:03.20: UnLoading Room 1
        November 18th 2026, 14:03.20: Reset map start
        November 18th 2026, 14:03.20: Resetting 3,4
        November 18th 2026, 14:03.20: Reset map end
        November 18th 2026, 14:03.21: Loading Room 2
        November 18th 2026, 14:04.07: UnLoading Room 2
        November 18th 2026, 14:04.07: Loading Room 3
        November 18th 2026, 14:05.12: UnLoading Room 3
        November 18th 2026, 14:05.12: Loading Room 4

        """
}
