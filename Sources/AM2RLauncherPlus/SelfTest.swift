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
                        for _ in 0..<6 { GameRunner.pruneLogs(in: GameRunner.logFolder(for: installed), keep: 4) }
                        let kept = (try? FileManager.default.contentsOfDirectory(atPath: GameRunner.logFolder(for: installed).path))?.count ?? 0
                        check("at most five logs are kept", kept <= 5)
                        try? FileManager.default.removeItem(at: GameRunner.saveFolder(for: installed).deletingLastPathComponent())
                        try? FileManager.default.removeItem(at: GameRunner.logFolder(for: installed).deletingLastPathComponent())
                        try? FileManager.default.removeItem(at: installed.folder)
                        context.delete(installed)
                        try? context.save()
                    }
                }
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
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
