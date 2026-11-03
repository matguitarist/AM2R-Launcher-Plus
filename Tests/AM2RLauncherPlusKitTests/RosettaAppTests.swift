import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let xdelta3 = ["/opt/homebrew/bin/xdelta3", "/usr/local/bin/xdelta3"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// A fake AM2R.exe, Rosetta patch data whose AM2R.xdelta turns it into "RUNNER", and a built profile folder.
private struct RosettaSetup {
    let dir = FileManager.default.temporaryDirectory.appending(path: "rosetta-\(UUID().uuidString)", directoryHint: .isDirectory)
    var game: URL { dir.appending(path: "AM2R_11", directoryHint: .isDirectory) }
    var patch: URL { dir.appending(path: "patchdata", directoryHint: .isDirectory) }
    var profile: URL { dir.appending(path: "Profiles/one", directoryHint: .isDirectory) }
    let id = "com.yoyogames.am2r.profile-test"

    init(validPatch: Bool = true) throws {
        let fm = FileManager.default
        func write(_ path: URL, _ text: String) throws {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
        }
        let exe = String(repeating: "windows runner ", count: 200)
        try write(game.appending(path: "AM2R.exe"), validPatch ? exe : "a different exe")
        try write(profile.appending(path: "game.ios"), "PATCHED")
        try write(profile.appending(path: "musending.ogg"), "new ending")
        try write(profile.appending(path: "lang/english.ini"), "[en]")
        try write(profile.appending(path: "profile.xml"), "<message />")
        try write(patch.appending(path: "data/Frameworks/libYoYoGamepad.dylib"), "dylib")
        try write(patch.appending(path: "data/PkgInfo"), "APPL????")
        let info: [String: Any] = ["CFBundleIdentifier": "com.yoyogames.am2r", "CFBundleExecutable": "Mac_Runner", "CFBundleName": "Mac_Runner"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: patch.appending(path: "data/Info.plist"))

        let source = dir.appending(path: "exe"), target = dir.appending(path: "runner")
        try write(source, exe)
        try write(target, "RUNNER " + String(repeating: "windows runner ", count: 190))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xdelta3!)
        process.arguments = ["-e", "-f", "-S", "lzma", "-s", source.path, target.path, patch.appending(path: "data/AM2R.xdelta").path]
        try process.run()
        process.waitUntilExit()
    }
}

@Test(.enabled(if: xdelta3 != nil))
func buildsTheRosettaApp() throws {
    let setup = try RosettaSetup()
    let app = try RosettaApp.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch,
                                   profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    let read = { (path: String) in try? String(contentsOf: app.appending(path: "Contents/" + path), encoding: .utf8) }
    #expect(app == setup.profile.appending(path: "AM2R.app", directoryHint: .isDirectory))
    #expect(read("MacOS/Mac_Runner")?.hasPrefix("RUNNER ") == true)
    #expect(FileManager.default.isExecutableFile(atPath: app.appending(path: "Contents/MacOS/Mac_Runner").path))
    #expect(read("Frameworks/libYoYoGamepad.dylib") == "dylib")
    #expect(read("PkgInfo") == "APPL????")
    #expect(read("Resources/game.ios") == "PATCHED")
    #expect(read("Resources/musending.ogg") == "new ending")
    #expect(read("Resources/lang/english.ini") == "[en]")
    #expect(read("Resources/profile.xml") == nil)
    #expect(read("Resources/AM2R.app/Contents/PkgInfo") == nil)
    let info = try #require(NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")))
    #expect(info["CFBundleIdentifier"] as? String == setup.id)
    #expect(info["CFBundleExecutable"] as? String == "Mac_Runner")
    #expect(RosettaApp.app(in: setup.profile) == app)

    // Building again replaces the app and never nests the old one in Resources.
    try RosettaApp.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    #expect(!FileManager.default.fileExists(atPath: app.appending(path: "Contents/Resources/AM2R.app").path))
}

@Test(.enabled(if: xdelta3 != nil))
func buildsTheRosettaAppFromAZip() throws {
    let setup = try RosettaSetup()
    let zip = setup.dir.appending(path: "AM2R_11.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = setup.dir
    process.arguments = ["-qr", zip.path, "AM2R_11"]
    try process.run()
    process.waitUntilExit()
    let app = try RosettaApp.build(source: zip, kind: .zip, root: "AM2R_11/", patchData: setup.patch,
                                   profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    #expect((try? String(contentsOf: app.appending(path: "Contents/MacOS/Mac_Runner"), encoding: .utf8))?.hasPrefix("RUNNER ") == true)
}

@Test(.enabled(if: xdelta3 != nil))
func aWrongExeLeavesNoRosettaApp() throws {
    let setup = try RosettaSetup(validPatch: false)
    #expect(throws: (any Error).self) {
        try RosettaApp.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    }
    #expect(RosettaApp.app(in: setup.profile) == nil)
    #expect(!FileManager.default.fileExists(atPath: setup.profile.appending(path: "AM2R.app.partial").path))
}

@Test(.enabled(if: xdelta3 != nil))
func rosettaNeedsTheExeAndTheRunnerPatch() throws {
    let setup = try RosettaSetup()
    try FileManager.default.removeItem(at: setup.game.appending(path: "AM2R.exe"))
    #expect(throws: RosettaApp.Failure.noWindowsGame) {
        try RosettaApp.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    }
    try FileManager.default.removeItem(at: setup.patch.appending(path: "data/AM2R.xdelta"))
    #expect(throws: RosettaApp.Failure.noRunnerPatch) {
        try RosettaApp.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, profileFolder: setup.profile, bundleIdentifier: setup.id, sign: false)
    }
}

@Test func rosettaLaunchesWithOpenAndWaits() {
    let args = RosettaApp.openArguments(app: URL(fileURLWithPath: "/p/AM2R.app"), log: URL(fileURLWithPath: "/l/run.log"))
    #expect(args == ["-W", "-n", "--stdout", "/l/run.log", "--stderr", "/l/run.log", "/p/AM2R.app"])
    let id = RosettaApp.bundleIdentifier(for: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!)
    #expect(id == "com.yoyogames.am2r.profile-e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
}

/// On the real files: the player's AM2R 1.1, downloaded Rosetta patch data and a built profile folder (a copy).
/// Set AM2R11_PATH, PATCH_DATA and ROSETTA_PROFILE to run. The runner is the official 1.4.1804 x86_64 binary.
@Test(.enabled(if: ["AM2R11_PATH", "PATCH_DATA", "ROSETTA_PROFILE"].allSatisfy { ProcessInfo.processInfo.environment[$0] != nil }))
func buildsTheRealRosettaApp() throws {
    let env = ProcessInfo.processInfo.environment
    let copy = try AM2R11.check(URL(fileURLWithPath: env["AM2R11_PATH"]!))
    let profile = URL(fileURLWithPath: env["ROSETTA_PROFILE"]!, isDirectory: true)
    let app = try RosettaApp.build(source: copy.url, kind: copy.kind, root: copy.root, patchData: URL(fileURLWithPath: env["PATCH_DATA"]!),
                                   profileFolder: profile, bundleIdentifier: "com.yoyogames.am2r.profile-test")
    #expect(AM2R11.md5(of: app.appending(path: "Contents/Resources/game.ios")) == "0de029951c94b04545c9c257053ad712")
    let file = Process()
    file.executableURL = URL(fileURLWithPath: "/usr/bin/file")
    file.arguments = [app.appending(path: "Contents/MacOS/Mac_Runner").path]
    let pipe = Pipe()
    file.standardOutput = pipe
    try file.run()
    file.waitUntilExit()
    #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("x86_64"))
    let verify = Process()
    verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    verify.arguments = ["--verify", app.path]
    try verify.run()
    verify.waitUntilExit()
    #expect(verify.terminationStatus == 0)
}
