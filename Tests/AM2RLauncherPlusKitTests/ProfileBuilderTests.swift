import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let xdelta3 = ["/opt/homebrew/bin/xdelta3", "/usr/local/bin/xdelta3"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// A fake AM2R 1.1 folder, fake patch data whose game.xdelta turns its data.win into "PATCHED", and a destination.
private struct Setup {
    let dir = FileManager.default.temporaryDirectory.appending(path: "builder-\(UUID().uuidString)", directoryHint: .isDirectory)
    var game: URL { dir.appending(path: "AM2R_11", directoryHint: .isDirectory) }
    var patch: URL { dir.appending(path: "patchdata", directoryHint: .isDirectory) }
    var destination: URL { dir.appending(path: "Profiles/one", directoryHint: .isDirectory) }

    init(validPatch: Bool = true) throws {
        let fm = FileManager.default
        func write(_ path: URL, _ text: String) throws {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
        }
        try write(game.appending(path: "data.win"), String(repeating: "original game ", count: 200))
        try write(game.appending(path: "musArea1A.ogg"), "old music 1A")
        try write(game.appending(path: "musEnding.ogg"), "old ending")
        try write(game.appending(path: "AM2R.exe"), "exe")
        let files = patch.appending(path: "data/files_to_copy", directoryHint: .isDirectory)
        try write(files.appending(path: "musEnding.ogg"), "new ending")
        try write(files.appending(path: "lang/english.ini"), "[en]")
        try write(files.appending(path: "lang/fonts/04b24.ttf"), "font")
        try write(files.appending(path: "mods/palettes/suits/power.png"), "png")
        try write(files.appending(path: "modifiers.ini"), "[m]")
        try write(patch.appending(path: "profile.xml"), #"<message Version="1.5.5" Name="Community Updates (Latest)" Author="AM2R Community Developers" />"#)

        // An invalid patch was made against another game: its copies read the wrong bytes.
        let other = dir.appending(path: "other.win")
        try write(other, String(repeating: "a different game build ", count: 200))
        let target = dir.appending(path: "target")
        try write(target, "PATCHED " + String(repeating: validPatch ? "original game " : "a different game build ", count: 190))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xdelta3!)
        let source = validPatch ? game.appending(path: "data.win") : other
        process.arguments = ["-e", "-f", "-S", "lzma", "-s", source.path, target.path, patch.appending(path: "data/game.xdelta").path]
        try process.run()
        process.waitUntilExit()
    }
}

@Test(.enabled(if: xdelta3 != nil))
func buildsAProfileFromAFolder() throws {
    let setup = try Setup()
    let result = try ProfileBuilder.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, destination: setup.destination)
    let out = result.folder
    let read = { (path: String) in try? String(contentsOf: out.appending(path: path), encoding: .utf8) }
    #expect(read("game.ios")?.hasPrefix("PATCHED ") == true)
    #expect(read("musarea1a.ogg") == "old music 1A")
    #expect(read("musending.ogg") == "new ending")
    #expect(read("lang/english.ini") == "[en]")
    #expect(read("mods/palettes/suits/power.png") == "png")
    #expect(read("modifiers.ini") == "[m]")
    #expect(!FileManager.default.fileExists(atPath: out.appending(path: "lang/fonts").path))
    #expect(!FileManager.default.fileExists(atPath: out.appending(path: "data.win").path))
    #expect(!FileManager.default.fileExists(atPath: out.appending(path: "AM2R.exe").path))
    #expect(result.info.version == "1.5.5")
}

@Test(.enabled(if: xdelta3 != nil))
func buildsAProfileFromANestedZip() throws {
    let setup = try Setup()
    let zip = setup.dir.appending(path: "AM2R_11.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = setup.dir
    process.arguments = ["-qr", zip.path, "AM2R_11"]
    try process.run()
    process.waitUntilExit()
    let result = try ProfileBuilder.build(source: zip, kind: .zip, root: "AM2R_11/", patchData: setup.patch, destination: setup.destination)
    #expect((try? String(contentsOf: result.folder.appending(path: "game.ios"), encoding: .utf8))?.hasPrefix("PATCHED ") == true)
    #expect(FileManager.default.fileExists(atPath: result.folder.appending(path: "musarea1a.ogg").path))
}

@Test(.enabled(if: xdelta3 != nil))
func aFailedPatchLeavesNoProfileAndKeepsTheOldOne() throws {
    let setup = try Setup(validPatch: false)
    try FileManager.default.createDirectory(at: setup.destination, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: setup.destination.appending(path: "game.ios"))
    #expect(throws: (any Error).self) {
        try ProfileBuilder.build(source: setup.game, kind: .folder, root: "", patchData: setup.patch, destination: setup.destination)
    }
    #expect((try? String(contentsOf: setup.destination.appending(path: "game.ios"), encoding: .utf8)) == "keep")
    #expect(!FileManager.default.fileExists(atPath: setup.destination.path + ".partial"))
}

/// End to end on the real files: latest patch data from GitHub + the player's AM2R 1.1 zip.
/// Set NETWORK_TESTS=1 and AM2R11_PATH to run. Checks game.ios against Community Updates 1.5.5.
@Test(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1" && ProcessInfo.processInfo.environment["AM2R11_PATH"] != nil))
func buildsTheRealCommunityUpdatesProfile() async throws {
    let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AM2R11_PATH"]!)
    let copy = try AM2R11.check(source)
    let manifest = try await PatchData.latestManifest(rosetta: false)
    let patch = try await PatchData.download(manifest, into: FileManager.default.temporaryDirectory.appending(path: "patchdata-e2e", directoryHint: .isDirectory))
    let destination = FileManager.default.temporaryDirectory.appending(path: "profile-e2e", directoryHint: .isDirectory)
    let result = try ProfileBuilder.build(source: copy.url, kind: copy.kind, root: copy.root, patchData: patch, destination: destination)
    #expect(result.info.version == "1.5.5")
    #expect(AM2R11.md5(of: result.folder.appending(path: "game.ios")) == "0de029951c94b04545c9c257053ad712")
    let oggs = try FileManager.default.contentsOfDirectory(atPath: result.folder.path).filter { $0.hasSuffix(".ogg") }
    #expect(oggs.count >= 45 && oggs.allSatisfy { $0 == $0.lowercased() })
}
