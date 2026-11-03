import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let xdelta3 = ["/opt/homebrew/bin/xdelta3", "/usr/local/bin/xdelta3"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// Mod zips made the way people make them: flat, inside a folder, from Finder (with __MACOSX).
private struct Mods {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mods-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

    static func profile(name: String = "Test Mod", yyc: Bool = false) -> String {
        #"<?xml version="1.0" encoding="utf-8"?><message XMLVersion="1" OperatingSystem="Windows" Version="1.2" Name="\#(name)" Author="Jo &amp; Sam" UsesCustomMusic="false" UsesYYC="\#(yyc ? "True" : "False")" ProfileNotes="Line one&#xA;Line two" />"#
    }

    func write(_ files: [String: Data], in folder: URL) throws {
        for (path, data) in files {
            let file = folder.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
    }

    func zip(_ name: String, _ files: [String: String]) throws -> URL {
        try zip(name, data: files.mapValues { Data($0.utf8) })
    }

    func zip(_ name: String, data files: [String: Data]) throws -> URL {
        let source = dir.appending(path: name + "-src", directoryHint: .isDirectory)
        try write(files, in: source)
        let zip = dir.appending(path: name + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-qr", zip.path, "."]
        try process.run()
        process.waitUntilExit()
        return zip
    }
}

@Test func readsProfileAttributesByName() throws {
    let profile = try #require(ProfileXML(Mods.profile()))
    #expect(profile.version == "1.2")
    #expect(profile.name == "Test Mod")
    #expect(profile.author == "Jo & Sam")
    #expect(profile.notes == "Line one\nLine two")
    #expect(profile.operatingSystem == "Windows")
    #expect(!profile.usesYYC)
    #expect(ProfileXML("not xml") == nil)
}

@Test func patchDataProfileInfoSkipsXMLVersion() {
    let info = PatchData.profileInfo(#"<message XMLVersion="1" Version="1.5.5" Name="Community Updates (Latest)" Author="AM2R Community Developers" />"#)
    #expect(info?.version == "1.5.5")
    #expect(info?.name == "Community Updates (Latest)")
}

@Test func readsAFlatModZip() throws {
    let mods = Mods()
    let zip = try mods.zip("flat", ["profile.xml": Mods.profile(), "data.xdelta": "d", "files_to_copy/lang/english.ini": "[en]"])
    let package = try ModPackage.read(zip)
    #expect(package.root == "")
    #expect(package.name == "Test Mod")
    #expect(package.version == "1.2")
    #expect(package.author == "Jo & Sam")
    #expect(package.gamePatch == "data.xdelta")
    #expect(package.hasFilesToCopy)
}

@Test func readsAModZippedWithItsFolderFromFinder() throws {
    let mods = Mods()
    let zip = try mods.zip("nested", ["Test Mod/profile.xml": Mods.profile(), "Test Mod/game.xdelta": "g", "Test Mod/data.xdelta": "d",
                                      "__MACOSX/Test Mod/._profile.xml": "junk"])
    let package = try ModPackage.read(zip)
    #expect(package.root == "Test Mod/")
    #expect(package.gamePatch == "game.xdelta")
    #expect(!package.hasFilesToCopy)
}

@Test func refusesZipsThatAreNotPlayableMods() throws {
    let mods = Mods()
    #expect(throws: ModPackage.Failure.notAMod) { try ModPackage.read(try mods.zip("none", ["readme.txt": "hi"])) }
    #expect(throws: ModPackage.Failure.notAMod) { try ModPackage.read(try mods.zip("deep", ["a/b/profile.xml": Mods.profile(), "a/b/game.xdelta": "g"])) }
    #expect(throws: ModPackage.Failure.yyc(name: "Fast Mod")) {
        try ModPackage.read(try mods.zip("yyc", ["profile.xml": Mods.profile(name: "Fast Mod", yyc: true), "AM2R.xdelta": "r"]))
    }
    #expect(throws: ModPackage.Failure.noGamePatch(name: "Test Mod")) {
        try ModPackage.read(try mods.zip("droid", ["profile.xml": Mods.profile(), "droid.xdelta": "a"]))
    }
    let notZip = mods.dir.appending(path: "fake.zip")
    try Data("plain text".utf8).write(to: notZip)
    #expect(throws: ModPackage.Failure.unreadable) { try ModPackage.read(notZip) }
}

@Test(.enabled(if: xdelta3 != nil))
func buildsAProfileFromAMod() throws {
    let mods = Mods()
    let fm = FileManager.default
    let game = mods.dir.appending(path: "AM2R_11", directoryHint: .isDirectory)
    try mods.write(["data.win": Data(String(repeating: "original game ", count: 200).utf8), "musTitle.ogg": Data("title".utf8)], in: game)
    let target = mods.dir.appending(path: "target")
    try Data(("MODDED " + String(repeating: "original game ", count: 190)).utf8).write(to: target)
    let delta = mods.dir.appending(path: "data.xdelta")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: xdelta3!)
    process.arguments = ["-e", "-f", "-S", "lzma", "-s", game.appending(path: "data.win").path, target.path, delta.path]
    try process.run()
    process.waitUntilExit()
    let zip = try mods.zip("real", data: ["My Mod/profile.xml": Data(Mods.profile().utf8), "My Mod/data.xdelta": try Data(contentsOf: delta),
                                          "My Mod/files_to_copy/musTitle.ogg": Data("mod title".utf8)])

    let package = try ModPackage.read(zip)
    let extracted = mods.dir.appending(path: "Mods/one", directoryHint: .isDirectory)
    try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
    try package.extract(into: extracted)
    #expect(fm.fileExists(atPath: extracted.appending(path: "profile.xml").path))
    #expect(!fm.fileExists(atPath: extracted.appending(path: ".unzip").path))

    let destination = mods.dir.appending(path: "Profiles/one", directoryHint: .isDirectory)
    let result = try ProfileBuilder.build(source: game, kind: .folder, root: "", patch: .mod(extracted, package: package), destination: destination)
    let read = { (path: String) in try? String(contentsOf: result.folder.appending(path: path), encoding: .utf8) }
    #expect(read("game.ios")?.hasPrefix("MODDED ") == true)
    // A test game has none of Community Updates' code: it counts as built on AM2R 1.1.
    #expect(!ModPackage.isBuiltOnCommunityUpdates(game: result.folder.appending(path: "game.ios")))
    #expect(read("mustitle.ogg") == "mod title")
    #expect(result.info.version == "1.2")
    #expect(result.info.name == "Test Mod")
}

/// A real community mod: MOD_ZIP=<zip> AM2R11_PATH=<AM2R 1.1 folder> swift test --filter installsARealMod
@Test(.enabled(if: ProcessInfo.processInfo.environment["MOD_ZIP"] != nil && ProcessInfo.processInfo.environment["AM2R11_PATH"] != nil))
func installsARealMod() throws {
    let env = ProcessInfo.processInfo.environment
    let zip = URL(fileURLWithPath: env["MOD_ZIP"]!)
    let game = URL(fileURLWithPath: env["AM2R11_PATH"]!, isDirectory: true)
    let package = try ModPackage.read(zip)
    let work = FileManager.default.temporaryDirectory.appending(path: "realmod-\(UUID().uuidString)", directoryHint: .isDirectory)
    let extracted = work.appending(path: "mod", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
    try package.extract(into: extracted)
    let destination = URL(fileURLWithPath: env["MOD_OUT"] ?? work.appending(path: "profile").path, isDirectory: true)
    let result = try ProfileBuilder.build(source: game, kind: .folder, root: "", patch: .mod(extracted, package: package), destination: destination)
    let head = try FileHandle(forReadingFrom: result.folder.appending(path: "game.ios")).read(upToCount: 4)
    #expect(head == Data("FORM".utf8))
    print("REALMOD built on Community Updates: \(ModPackage.isBuiltOnCommunityUpdates(game: result.folder.appending(path: "game.ios")))")
    print("REALMOD \(package.name) \(package.version) by \(package.author), \(package.profile.operatingSystem), \(package.gamePatch) -> \(result.folder.path)")
}
