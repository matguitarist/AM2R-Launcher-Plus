import AM2RLauncherPlusKit
import AppKit
import SwiftData

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/AM2RLauncherPlus-self.store ~/Applications/AM2RLauncherPlus.app/Contents/MacOS/AM2RLauncherPlus --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            func profiles() -> [Profile] { (try? context.fetch(FetchDescriptor<Profile>())) ?? [] }

            let before = profiles().count
            let profile = model.addProfile(name: "  Community   Updates 1.5.5 ", version: "1.5.5")
            check("adding a profile stores it", profiles().count == before + 1)
            check("the new profile is selected", model.selection == profile.id)
            check("profile names are cleaned", profile.name == "Community Updates 1.5.5")
            check("new profiles use the native engine", profile.engine == .native)
            context.delete(profile)
            try? context.save()
            check("deleting the profile removes it", profiles().count == before)

            // S-006: a game that fails to start is reported with its log.
            if GameRunner.engine != nil {
                let broken = model.addProfile(name: "Broken", version: "0")
                try? FileManager.default.createDirectory(at: broken.folder, withIntermediateDirectories: true)
                try? Data("not a game".utf8).write(to: broken.folder.appending(path: "game.ios"))
                model.play(extraArguments: ["--headless"])
                for _ in 0..<100 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                check("a game that fails is reported", model.lastGameFailure?.profile == broken.uuid, "\(String(describing: model.lastGameFailure))")
                check("the failure points at its log", model.currentLog == model.lastGameFailure?.log && model.currentLog != nil)
                model.showLog()
                check("Show Log opens the failed run's log", model.logSheet?.log == model.lastGameFailure?.log)
                model.logSheet = nil
                model.play(extraArguments: ["--headless"])
                check("Play Again clears the banner", model.lastGameFailure == nil)
                for _ in 0..<100 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                model.lastGameFailure = nil
                for folder in [broken.folder, GameRunner.logFolder(for: broken), GameRunner.saveFolder(for: broken)] {
                    try? FileManager.default.removeItem(at: folder)
                }
                context.delete(broken)
                try? context.save()
            }

            // S-010 to S-012: game settings in the profile's config.ini.
            do {
                let tuned = model.addProfile(name: "Tuned", version: "1.5.5")
                let saves = GameRunner.saveFolder(for: tuned)
                try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
                // An older profile that the game set up with its own layout and a custom key.
                try? "[Screen]\nScale=\"3\"\n\n[Control]\nXBJoypadButtonStart=\"32778\"\nXBJoypadButtonExit=\"32780\"\nAimStyle=\"1\"\n"
                    .write(to: GameSettings.configFile(in: saves), atomically: true, encoding: .utf8)
                model.applyFirstSettings(to: tuned)
                let first = GameSettings.read(from: saves)
                check("an existing profile switches to the Mac controller layout once", first.controller == .mac && tuned.controllerLayoutSet)
                check("the switch keeps the game's other settings", first.scale == 3
                      && ((try? String(contentsOf: GameSettings.configFile(in: saves), encoding: .utf8))?.contains("AimStyle=\"1\"") ?? false))
                var original = first
                original.controller = .original
                try? original.write(to: saves)
                model.applyFirstSettings(to: tuned)
                check("the player's later layout choice stands", GameSettings.read(from: saves).controller == .original)
                // S-034: Automatic prompts follow the controller; a picked set stays.
                model.applyAutomaticPrompts(to: tuned, connected: .playStation)
                check("automatic button prompts follow the connected controller", GameSettings.read(from: saves).buttonPrompts == .playStation)
                tuned.automaticPrompts = false
                model.applyAutomaticPrompts(to: tuned, connected: .nintendo)
                check("a picked prompt set is kept", GameSettings.read(from: saves).buttonPrompts == .playStation
                      && GameSettings.read(from: saves).controller == .original)
                try? FileManager.default.removeItem(at: saves)
                context.delete(tuned)
                try? context.save()
            }

            // S-013: moving the data folder.
            do {
                let moving = model.addProfile(name: "Moving", version: "1.5.5")
                try? FileManager.default.createDirectory(at: moving.folder, withIntermediateDirectories: true)
                try? Data("game".utf8).write(to: moving.folder.appending(path: "game.ios"))
                // The Play page loads (and may write) the new profile's config.ini; let it finish before the move.
                try? await Task.sleep(for: .seconds(1))
                let original = DataFolder.url
                let target = URL.temporaryDirectory.appending(path: "selftest-move-\(UUID().uuidString)", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                await model.moveDataFolder(into: target)
                check("the data folder moves", model.dataMoveError == nil && DataFolder.url.deletingLastPathComponent().path == target.resolvingSymlinksInPath().path,
                      model.dataMoveError ?? DataFolder.url.path)
                check("profiles follow the data folder", FileManager.default.fileExists(atPath: moving.folder.appending(path: "game.ios").path))
                check("the old data folder is gone", !FileManager.default.fileExists(atPath: original.path))
                await model.moveDataFolder(into: original.deletingLastPathComponent())
                check("the data folder moves back", DataFolder.url.path == original.resolvingSymlinksInPath().path || DataFolder.url.path == original.path, DataFolder.url.path)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.removeItem(at: moving.folder)
                context.delete(moving)
                try? context.save()
            }

            // S-022: rename, duplicate, delete with or without the saves.
            do {
                let fm = FileManager.default
                let original = model.addProfile(name: "Managed", version: "1.5.5")
                try? fm.createDirectory(at: original.folder, withIntermediateDirectories: true)
                try? Data("game".utf8).write(to: original.folder.appending(path: "game.ios"))
                let saves = GameRunner.saveFolder(for: original)
                try? fm.createDirectory(at: saves, withIntermediateDirectories: true)
                try? Data("[Screen]\n".utf8).write(to: GameSettings.configFile(in: saves))
                try? Data("save".utf8).write(to: saves.appending(path: "save1"))
                model.rename(original, to: "  My   Run ")
                check("rename cleans and keeps the name", original.name == "My Run")
                let copy = await model.duplicate(original)
                check("duplicate adds a selected copy", copy != nil && copy?.name == "My Run Copy" && model.selection == copy?.id)
                if let copy {
                    check("the copy has the game files and saves", fm.fileExists(atPath: copy.folder.appending(path: "game.ios").path)
                          && fm.fileExists(atPath: GameRunner.saveFolder(for: copy).appending(path: "save1").path))
                    model.deleteTarget = copy
                    check("Delete asks first", fm.fileExists(atPath: copy.folder.path) && profiles().contains { $0.uuid == copy.uuid })
                    model.deleteTarget = nil
                    let copySaves = GameRunner.saveFolder(for: copy), copyFolder = copy.folder
                    model.delete(copy, keepSaves: false)
                    check("Delete without saves removes files and saves", !fm.fileExists(atPath: copyFolder.path) && !fm.fileExists(atPath: copySaves.path))
                }
                let folder = original.folder, id = original.uuid
                model.delete(original, keepSaves: true)
                let kept = model.keptSaves?.folder
                check("Delete, Keep Saves moves the saves to Kept Saves",
                      kept.map { fm.fileExists(atPath: $0.appending(path: "save1").path) && fm.fileExists(atPath: $0.appending(path: "config.ini").path) } == true
                      && kept?.deletingLastPathComponent().lastPathComponent == "Kept Saves", kept?.path ?? "none")
                check("the deleted profile and its files are gone", !fm.fileExists(atPath: folder.path) && !profiles().contains { $0.uuid == id })
                if let kept { try? fm.removeItem(at: kept) }
                model.keptSaves = nil
            }

            // S-023: back up and restore saves.
            do {
                let fm = FileManager.default
                let backed = model.addProfile(name: "Backed", version: "1.5.5")
                let saves = GameRunner.saveFolder(for: backed)
                try? fm.createDirectory(at: saves, withIntermediateDirectories: true)
                try? Data("slot 1".utf8).write(to: saves.appending(path: "save1"))
                let zip = await model.backUpSaves(backed)
                check("Back Up Saves zips the save folder", zip.map { fm.fileExists(atPath: $0.path) } == true, model.backupError ?? "")
                try? Data("slot 1 later".utf8).write(to: saves.appending(path: "save1"))
                if let zip {
                    let restored = await model.restoreSaves(backed, from: zip)
                    check("Restore puts the backup back", restored && (try? String(contentsOf: saves.appending(path: "save1"), encoding: .utf8)) == "slot 1",
                          model.backupError ?? "")
                    let list = SaveBackup.list(in: DataFolder.backups(for: backed.uuid))
                    check("Restore backs up the current saves first", list.count == 2 && list.contains { $0.name.hasSuffix("(before restore)") })
                }
                let backups = DataFolder.backups(for: backed.uuid)
                model.delete(backed, keepSaves: false)
                check("deleting a profile with its saves removes its backups", !fm.fileExists(atPath: backups.path))
                model.backupMessage = nil
            }

            // S-020: the banner shows only for a profile built from older patch data.
            do {
                let old = model.addProfile(name: "Old", version: "1.5.5")
                old.patchCommit = String(repeating: "a", count: 40)
                let saved = model.latestUpdate
                model.latestUpdate = UpdateCheck.Latest(manifest: PatchData.Manifest(commit: String(repeating: "b", count: 40), files: []),
                                                        version: "1.5.6", checkedAt: .now)
                check("a newer release shows the update banner", model.availableUpdate(for: old) == "Community Updates 1.5.6 is available")
                old.patchCommit = String(repeating: "b", count: 40)
                check("an up-to-date profile shows no banner", model.availableUpdate(for: old) == nil)
                model.latestUpdate = saved
                context.delete(old)
                try? context.save()
            }

            // S-014: Rosetta needs AM2R.exe and the patch data; the runner's data folder links to the profile's saves.
            do {
                let plain = model.addProfile(name: "Plain", version: "1.5.5")
                let switched = await model.useRosetta(plain)
                check("Rosetta without AM2R.exe or patch data says why and keeps Native",
                      !switched && plain.engine == .native && model.engineError?.profile == plain.uuid, model.engineError?.message ?? "no error")
                model.engineError = nil
                let base = URL.temporaryDirectory.appending(path: "selftest-runner-\(UUID().uuidString)", directoryHint: .isDirectory)
                let saves = base.appending(path: "Saves", directoryHint: .isDirectory), runner = base.appending(path: "com.yoyogames.am2r.profile-x", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
                try? Data("old save".utf8).write(to: runner.appending(path: "save1"))
                try? Data("ours".utf8).write(to: saves.appending(path: "config.ini"))
                try? Data("theirs".utf8).write(to: runner.appending(path: "config.ini"))
                try? GameRunner.linkRunnerData(runner, to: saves)
                try? GameRunner.linkRunnerData(runner, to: saves)
                check("the runner's data folder links to the profile's saves",
                      (try? FileManager.default.destinationOfSymbolicLink(atPath: runner.path)) == saves.path)
                check("saves the runner made earlier move into the profile, ours win",
                      (try? String(contentsOf: saves.appending(path: "save1"), encoding: .utf8)) == "old save"
                      && (try? String(contentsOf: saves.appending(path: "config.ini"), encoding: .utf8)) == "ours")
                try? FileManager.default.removeItem(at: base)
                context.delete(plain)
                try? context.save()
            }

            // S-001: choosing AM2R 1.1
            let fake = URL.temporaryDirectory.appending(path: "selftest-fake-am2r", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
            try? Data("not the game".utf8).write(to: fake.appending(path: "data.win"))
            await model.choose(fake)
            check("a modified data.win is rejected with its reason", model.welcome == .failed(.wrongDataWin, fake.lastPathComponent))
            check("a rejected copy isn't kept", model.source == nil)
            if let real = ProcessInfo.processInfo.environment["AM2R11_PATH"] {
                await model.choose(URL(fileURLWithPath: real))
                check("the real AM2R 1.1 is accepted", model.welcome == .ready, "\(model.welcome)")
                check("the accepted copy is kept with its bookmark", model.source?.bookmark != nil && model.source?.url.path == real)
                check("AM2R.exe is recognized for Rosetta", model.source?.hasWindowsGame == true)
                let reopened = AppModel(container: model.container)
                check("the copy is still chosen after a restart", reopened.welcome == .ready && reopened.source?.path == real)

                // S-002 to S-004: a real install (network). APP_SELFTEST_INSTALL=1 runs it.
                if ProcessInfo.processInfo.environment["APP_SELFTEST_INSTALL"] == "1" {
                    let profilesBefore = profiles().count
                    model.startInstall()
                    check("install starts with the download step", model.install?.step == .download)
                    var sawPatch = false
                    for _ in 0..<1200 where model.install != nil && model.install?.failure == nil {
                        if model.install?.step == .patch || model.install?.step == .copy { sawPatch = true }
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    check("install finishes without an error", model.install == nil, model.install?.failure ?? "still running")
                    check("install went through patching", sawPatch)
                    let installed = profiles().first { $0.id == model.selection }
                    check("the new profile is added and selected", profiles().count == profilesBefore + 1 && installed != nil)
                    check("the profile is named after its version", installed?.name == "Community Updates 1.5.5", installed?.name ?? "none")
                    if let installed {
                        let gameIOS = installed.folder.appending(path: "game.ios")
                        check("game.ios is Community Updates 1.5.5", AM2R11.md5(of: gameIOS) == "0de029951c94b04545c9c257053ad712")
                        check("the patch commit is recorded", installed.patchCommit.count == 40)

                        // S-005: play on the bundled engine (headless, so no window opens).
                        check("the native engine is bundled", GameRunner.engine != nil)
                        model.play(extraArguments: ["--headless", "--exit-at-frame", "120"])
                        check("Play starts the game", model.game != nil, model.playError ?? "")
                        for _ in 0..<300 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                        check("the game ends on its own", model.game == nil)
                        check("a clean exit isn't reported as a failure", model.lastGameFailure == nil)
                        check("play time and last played are recorded", installed.playTime > 0 && installed.lastPlayedAt != nil)
                        let logs = (try? FileManager.default.contentsOfDirectory(at: GameRunner.logFolder(for: installed), includingPropertiesForKeys: nil)) ?? []
                        let logText = logs.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
                        check("the game log is written", logText.contains("Loaded \"AM2R\""), "\(logs.count) logs")
                        check("saves go to the profile's save folder", FileManager.default.fileExists(atPath: GameRunner.saveFolder(for: installed).path))

                        model.play() // windowed for two seconds: headless AM2R quits by itself
                        try? await Task.sleep(for: .seconds(2))
                        check("the game is still running before Stop", model.game?.isRunning == true)
                        model.stopGame()
                        for _ in 0..<100 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                        check("Stop ends the game", model.game == nil)
                        check("stopping isn't reported as a failure", model.lastGameFailure == nil)
                        // S-014: switch to Rosetta, play on the official runner, stop it.
                        let switched = await model.useRosetta(installed)
                        check("Rosetta builds the profile's AM2R.app", switched && installed.engine == .rosetta && RosettaApp.app(in: installed.folder) != nil,
                              model.engineError?.message ?? "")
                        let runnerData = GameRunner.runnerDataFolder(bundleID: RosettaApp.bundleIdentifier(for: installed.uuid))
                        if switched && Rosetta.isInstalled {
                            model.play()
                            check("Play starts the Rosetta app", model.game != nil, model.playError ?? "")
                            try? await Task.sleep(for: .seconds(4))
                            check("the Rosetta game is running", model.game?.isRunning == true)
                            check("the runner saves into the profile's save folder",
                                  (try? FileManager.default.destinationOfSymbolicLink(atPath: runnerData.path)) == GameRunner.saveFolder(for: installed).path)
                            model.stopGame()
                            for _ in 0..<100 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                            check("Stop ends the Rosetta game", model.game == nil)
                        }
                        model.setEngine(.native, for: installed)
                        check("switching back to Native keeps the Rosetta app for next time", installed.engine == .native && RosettaApp.app(in: installed.folder) != nil)
                        try? FileManager.default.removeItem(at: runnerData)

                        // S-021: Update rebuilds the profile in place and keeps its saves and settings.
                        let saves = GameRunner.saveFolder(for: installed)
                        let configBefore = try? Data(contentsOf: GameSettings.configFile(in: saves))
                        try? Data("save".utf8).write(to: saves.appending(path: "save1"))
                        let commit = installed.patchCommit, count = profiles().count
                        installed.patchCommit = String(repeating: "0", count: 40)
                        installed.version = "1.5.4"
                        installed.name = "Community Updates 1.5.4"
                        model.startInstall(updating: installed.uuid)
                        check("Update shows the install page for this profile", model.install?.updating == installed.uuid)
                        for _ in 0..<1200 where model.install != nil && model.install?.failure == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        check("Update finishes without an error", model.install == nil, model.install?.failure ?? "still running")
                        check("Update keeps the same profile", profiles().count == count && installed.patchCommit == commit)
                        check("Update renames a default name to the new version", installed.version == "1.5.5" && installed.name == "Community Updates 1.5.5", installed.name)
                        check("the updated game.ios is 1.5.5", AM2R11.md5(of: installed.folder.appending(path: "game.ios")) == "0de029951c94b04545c9c257053ad712")
                        check("Update keeps the saves and config.ini",
                              (try? String(contentsOf: saves.appending(path: "save1"), encoding: .utf8)) == "save"
                              && (try? Data(contentsOf: GameSettings.configFile(in: saves))) == configBefore)
                        for _ in 0..<6 { GameRunner.pruneLogs(in: GameRunner.logFolder(for: installed), keep: 4) }
                        let kept = (try? FileManager.default.contentsOfDirectory(atPath: GameRunner.logFolder(for: installed).path))?.count ?? 0
                        check("at most five logs are kept", kept <= 5)

                        // S-033: a mod zip built from the same patch, the way the mod packer writes it.
                        let patchFolder = DataFolder.patchData.appending(path: installed.patchCommit, directoryHint: .isDirectory)
                        let modProfile = #"<message XMLVersion="1" OperatingSystem="Linux" Version="2.0" Name="Self-Test Mod" Author="Self &amp; Test" UsesYYC="False" />"#
                        let modZip = makeZip("Self-Test Mod", files: ["profile.xml": Data(modProfile.utf8)],
                                             copying: ["game.xdelta": patchFolder.appending(path: "data/game.xdelta"),
                                                       "files_to_copy": patchFolder.appending(path: "data/files_to_copy")])
                        let before = profiles().count
                        model.startModInstall(zip: modZip)
                        check("a mod install shows the mod's page", model.install?.modZip == modZip)
                        for _ in 0..<1200 where model.install != nil && model.install?.failure == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        check("the mod installs without an error", model.install == nil, model.install?.failure ?? "still running")
                        let mod = profiles().first { $0.id == model.selection }
                        check("the mod is a new, selected profile", profiles().count == before + 1 && mod?.isMod == true)
                        check("the mod profile has the mod's name, version and author",
                              mod?.name == "Self-Test Mod 2.0" && mod?.version == "2.0" && mod?.author == "Self & Test", mod?.name ?? "none")
                        if let mod {
                            check("the mod's game.ios is patched", AM2R11.md5(of: mod.folder.appending(path: "game.ios")) == "0de029951c94b04545c9c257053ad712")
                            check("a mod shows no Community Updates update", model.availableUpdate(for: mod) == nil)
                            model.setEngine(.rosetta, for: mod)
                            check("a mod stays on the native engine", mod.engine == .native)
                            check("the unpacked mod is removed after install",
                                  ((try? FileManager.default.contentsOfDirectory(atPath: DataFolder.mods.path)) ?? []).isEmpty)
                            let modSaves = GameRunner.saveFolder(for: mod)
                            let modConfig = GameSettings.configFile(in: modSaves)
                            check("a new mod gets no partial config.ini (AM2R 1.1 mods break on one)",
                                  !FileManager.default.fileExists(atPath: modConfig.path) && !model.canWriteSettings(for: mod))
                            // A config.ini an earlier build wrote is removed when the mod starts.
                            try? GameSettings().write(to: modSaves)
                            model.play(extraArguments: ["--headless", "--exit-at-frame", "120"])
                            for _ in 0..<300 where model.game != nil { try? await Task.sleep(for: .milliseconds(100)) }
                            check("the mod plays and ends cleanly", model.lastGameFailure == nil && mod.lastPlayedAt != nil)
                            check("a partial config.ini is gone, or the mod's own one has the Mac layout",
                                  GameSettings.gameHasWritten(in: modSaves)
                                      ? GameSettings.read(from: modSaves).controller == .mac
                                      : !FileManager.default.fileExists(atPath: modConfig.path))
                            try? FileManager.default.removeItem(at: mod.folder)
                            try? FileManager.default.removeItem(at: GameRunner.saveFolder(for: mod))
                            try? FileManager.default.removeItem(at: GameRunner.logFolder(for: mod))
                            context.delete(mod)
                            try? context.save()
                        }
                        let yyc = makeZip("Fast Mod", files: ["profile.xml": Data(#"<message Version="1.0" Name="Fast Mod" UsesYYC="True" />"#.utf8),
                                                              "AM2R.xdelta": Data("runner".utf8)], copying: [:])
                        model.startModInstall(zip: yyc)
                        for _ in 0..<100 where model.install?.failure == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        check("a YYC mod is refused with a reason", model.install?.failure == ModPackage.Failure.yyc(name: "Fast Mod").message,
                              model.install?.failure ?? "no failure")
                        check("a refused mod adds no profile", profiles().count == before)
                        model.cancelInstall()

                        // A mod built on AM2R 1.1 (here: a patch that keeps 1.1's game as it is) is refused.
                        if let real = ProcessInfo.processInfo.environment["AM2R11_PATH"],
                           let xdelta = ["/opt/homebrew/bin/xdelta3", "/usr/local/bin/xdelta3"].first(where: FileManager.default.isExecutableFile) {
                            let dataWin = URL(fileURLWithPath: real).appending(path: "data.win")
                            let delta = FileManager.default.temporaryDirectory.appending(path: "old-mod-\(UUID().uuidString).xdelta")
                            let encode = Process()
                            encode.executableURL = URL(fileURLWithPath: xdelta)
                            encode.arguments = ["-e", "-f", "-s", dataWin.path, dataWin.path, delta.path]
                            try? encode.run()
                            encode.waitUntilExit()
                            let oldMod = makeZip("Old Mod", files: ["profile.xml": Data(#"<message Version="1.0" Name="Old Mod" OperatingSystem="Windows" UsesYYC="False" />"#.utf8)],
                                                 copying: ["data.xdelta": delta])
                            let beforeOld = profiles().count
                            model.startModInstall(zip: oldMod)
                            for _ in 0..<1200 where model.install != nil && model.install?.failure == nil { try? await Task.sleep(for: .milliseconds(100)) }
                            check("a mod built on AM2R 1.1 is refused with a reason",
                                  model.install?.failure == ModPackage.Failure.builtOnAM2R11(name: "Old Mod 1.0").message, model.install?.failure ?? "installed")
                            check("a refused AM2R 1.1 mod leaves no profile or files", profiles().count == beforeOld
                                  && ((try? FileManager.default.contentsOfDirectory(atPath: DataFolder.profiles.path)) ?? []).count == beforeOld)
                            model.cancelInstall()
                            model.install = nil
                            try? FileManager.default.removeItem(at: delta)
                        }

                        // S-036: the folder Randovania asks for, and its export imported back as a profile.
                        let rdv = FileManager.default.temporaryDirectory.appending(path: "rdv-selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
                        let rdvApp = try? RandovaniaGame.prepare(profile: installed.folder, into: rdv)
                        check("Randovania's input folder has AM2R.app with game.ios and Mac_Runner",
                              rdvApp.map { FileManager.default.fileExists(atPath: $0.appending(path: "Contents/Resources/game.ios").path)
                                  && FileManager.default.isExecutableFile(atPath: $0.appending(path: "Contents/MacOS/Mac_Runner").path) } == true)
                        model.importRandovania(folder: rdv)
                        for _ in 0..<600 where model.install?.finishedName == nil && model.install?.failure == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        let seed = profiles().first { $0.name == "Randovania \(rdv.lastPathComponent)" }
                        check("an exported seed imports as its own profile", seed?.isMod == true && seed?.author == "Randovania", model.install?.failure ?? "none")
                        for _ in 0..<50 where model.install != nil { try? await Task.sleep(for: .milliseconds(100)) }
                        model.importRandovania(folder: FileManager.default.temporaryDirectory)
                        check("a folder without a seed is refused with a reason", model.install?.failure == RandovaniaGame.Failure.notAnExport.message)
                        model.install = nil
                        if let seed {
                            try? FileManager.default.removeItem(at: seed.folder)
                            context.delete(seed)
                            try? context.save()
                        }
                        try? FileManager.default.removeItem(at: rdv)
                        // Only this profile's folders: Logs/ also holds launcher.log.
                        try? FileManager.default.removeItem(at: GameRunner.saveFolder(for: installed))
                        try? FileManager.default.removeItem(at: GameRunner.logFolder(for: installed))
                        try? FileManager.default.removeItem(at: installed.folder)
                        context.delete(installed)
                        try? context.save()
                    }
                }
            }

            // Debug Log: launcher events are kept and written to launcher.log.
            check("the launcher log records events", LauncherLog.shared.entries.contains { $0.source == "Profiles" && $0.message.hasPrefix("Deleted") })
            LauncherLog.shared.flush()
            try? await Task.sleep(for: .seconds(0.5))
            check("the launcher log is written to launcher.log",
                  (try? String(contentsOf: LauncherLog.file, encoding: .utf8))?.contains("INFO [App] AM2R Launcher Plus") == true, LauncherLog.file.path)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// A zip in the temp folder holding `files` and copies of `copying` (files or folders), at its top level.
    private static func makeZip(_ name: String, files: [String: Data], copying: [String: URL]) -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "selftest-\(UUID().uuidString)", directoryHint: .isDirectory)
        let content = dir.appending(path: name, directoryHint: .isDirectory)
        try? fm.createDirectory(at: content, withIntermediateDirectories: true)
        for (path, data) in files { try? data.write(to: content.appending(path: path)) }
        for (path, source) in copying { try? fm.copyItem(at: source, to: content.appending(path: path)) }
        let zip = dir.appending(path: name + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = content
        process.arguments = ["-qr", zip.path, "."]
        try? process.run()
        process.waitUntilExit()
        return zip
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
