import Foundation
import ProcessKit
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
        _ = try Shell.runSync("/usr/bin/zip", ["-qr", zip.path, "."], in: source)
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

@Test func readsAFlatModZip() async throws {
    let mods = Mods()
    let zip = try mods.zip("flat", ["profile.xml": Mods.profile(), "data.xdelta": "d", "files_to_copy/lang/english.ini": "[en]"])
    let package = try await ModPackage.read(zip)
    #expect(package.root == "")
    #expect(package.name == "Test Mod")
    #expect(package.version == "1.2")
    #expect(package.author == "Jo & Sam")
    #expect(package.gamePatch == "data.xdelta")
    #expect(package.hasFilesToCopy)
}

@Test func readsAModZippedWithItsFolderFromFinder() async throws {
    let mods = Mods()
    let zip = try mods.zip("nested", ["Test Mod/profile.xml": Mods.profile(), "Test Mod/game.xdelta": "g", "Test Mod/data.xdelta": "d",
                                      "__MACOSX/Test Mod/._profile.xml": "junk"])
    let package = try await ModPackage.read(zip)
    #expect(package.root == "Test Mod/")
    #expect(package.gamePatch == "game.xdelta")
    #expect(!package.hasFilesToCopy)
}

@Test func refusesZipsThatAreNotPlayableMods() async throws {
    let mods = Mods()
    await #expect(throws: ModPackage.Failure.notAMod) { try await ModPackage.read(try mods.zip("none", ["readme.txt": "hi"])) }
    await #expect(throws: ModPackage.Failure.notAMod) { try await ModPackage.read(try mods.zip("deep", ["a/b/profile.xml": Mods.profile(), "a/b/game.xdelta": "g"])) }
    await #expect(throws: ModPackage.Failure.yyc(name: "Fast Mod")) {
        try await ModPackage.read(try mods.zip("yyc", ["profile.xml": Mods.profile(name: "Fast Mod", yyc: true), "AM2R.xdelta": "r"]))
    }
    await #expect(throws: ModPackage.Failure.noGamePatch(name: "Test Mod")) {
        try await ModPackage.read(try mods.zip("droid", ["profile.xml": Mods.profile(), "droid.xdelta": "a"]))
    }
    let notZip = mods.dir.appending(path: "fake.zip")
    try Data("plain text".utf8).write(to: notZip)
    await #expect(throws: ModPackage.Failure.unreadable) { try await ModPackage.read(notZip) }
}

@Test func refusesAModWithALinkPointingOut() async throws {
    let mods = Mods()
    let source = mods.dir.appending(path: "linked-src", directoryHint: .isDirectory)
    try mods.write(["profile.xml": Data(Mods.profile().utf8), "game.xdelta": Data("g".utf8)], in: source)
    try FileManager.default.createSymbolicLink(atPath: source.appending(path: "files_to_copy").path, withDestinationPath: "/tmp")
    let zip = mods.dir.appending(path: "linked.zip")
    try Shell.runSync("/usr/bin/zip", ["-qry", zip.path, "."], in: source).check()
    await #expect(throws: ModPackage.Failure.unreadable) { try await ModPackage.read(zip) }
}

@Test(.enabled(if: xdelta3 != nil))
func buildsAProfileFromAMod() async throws {
    let mods = Mods()
    let fm = FileManager.default
    let game = mods.dir.appending(path: "AM2R_11", directoryHint: .isDirectory)
    try mods.write(["data.win": Data(String(repeating: "original game ", count: 200).utf8), "musTitle.ogg": Data("title".utf8)], in: game)
    let target = mods.dir.appending(path: "target")
    try Data(("MODDED " + String(repeating: "original game ", count: 190)).utf8).write(to: target)
    let delta = mods.dir.appending(path: "data.xdelta")
    _ = try Shell.runSync(xdelta3!, ["-e", "-f", "-S", "lzma", "-s", game.appending(path: "data.win").path, target.path, delta.path])
    let zip = try mods.zip("real", data: ["My Mod/profile.xml": Data(Mods.profile().utf8), "My Mod/data.xdelta": try Data(contentsOf: delta),
                                          "My Mod/files_to_copy/musTitle.ogg": Data("mod title".utf8)])

    let package = try await ModPackage.read(zip)
    let extracted = mods.dir.appending(path: "Mods/one", directoryHint: .isDirectory)
    try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
    try await package.extract(into: extracted)
    #expect(fm.fileExists(atPath: extracted.appending(path: "profile.xml").path))
    #expect(!fm.fileExists(atPath: extracted.appending(path: ".unzip").path))

    let destination = mods.dir.appending(path: "Profiles/one", directoryHint: .isDirectory)
    let result = try await ProfileBuilder.build(source: game, kind: .folder, root: "", patch: .mod(extracted, package: package), destination: destination)
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
func installsARealMod() async throws {
    let env = ProcessInfo.processInfo.environment
    let zip = URL(fileURLWithPath: env["MOD_ZIP"]!)
    let game = URL(fileURLWithPath: env["AM2R11_PATH"]!, isDirectory: true)
    let package = try await ModPackage.read(zip)
    let work = FileManager.default.temporaryDirectory.appending(path: "realmod-\(UUID().uuidString)", directoryHint: .isDirectory)
    let extracted = work.appending(path: "mod", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
    try await package.extract(into: extracted)
    let destination = URL(fileURLWithPath: env["MOD_OUT"] ?? work.appending(path: "profile").path, isDirectory: true)
    let result = try await ProfileBuilder.build(source: game, kind: .folder, root: "", patch: .mod(extracted, package: package), destination: destination)
    let head = try FileHandle(forReadingFrom: result.folder.appending(path: "game.ios")).read(upToCount: 4)
    #expect(head == Data("FORM".utf8))
    print("REALMOD built on Community Updates: \(ModPackage.isBuiltOnCommunityUpdates(game: result.folder.appending(path: "game.ios")))")
    print("REALMOD \(package.name) \(package.version) by \(package.author), \(package.profile.operatingSystem), \(package.gamePatch) -> \(result.folder.path)")
}

// MARK: Zips as Atomic makes them (github.com/AM2R-Community-Developers/Atomic, AtomicLib/Core.cs)

/// profile.xml as .NET's XmlSerializer writes it for Atomic: a byte order mark, the xsi and xsd
/// namespaces on the root, attributes in ModProfileXML order, lowercase booleans.
private func atomicProfile(os: String = "Mac", name: String = "Atomic Mod", yyc: Bool = false,
                           android: Bool = false, installable: Bool = true, declaredEncoding: String = "utf-8") -> String {
    "\u{FEFF}<?xml version=\"1.0\" encoding=\"\(declaredEncoding)\"?>\r\n"
        + #"<message xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" "#
        + #"OperatingSystem="\#(os)" XMLVersion="1" Version="2.0" Name="\#(name)" Author="Jo" UsesCustomMusic="true" "#
        + #"SaveLocation="%localappdata%/AM2R/atomicmod" SupportsAndroid="\#(android)" UsesYYC="\#(yyc)" "#
        + #"Installable="\#(installable)" ProfileNotes="Line one&#xA;Line two" />"#
}

@Test func readsAtomicsProfileXML() throws {
    let profile = try #require(ProfileXML(atomicProfile().trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))))
    #expect(profile.name == "Atomic Mod")
    #expect(profile.version == "2.0")
    #expect(profile.operatingSystem == "Mac")
    #expect(profile.notes == "Line one\nLine two")
    #expect(profile.installable)
    #expect(!profile.usesYYC)
}

@Test func readsAtomicMacAndLinuxMods() async throws {
    let mods = Mods()
    for os in ["Mac", "Linux"] {
        var files = ["profile.xml": atomicProfile(os: os), "game.xdelta": "g", "AM2R.xdelta": "r",
                     "files_to_copy/lang/english.ini": "[en]", "files_to_copy/musarea1a.ogg": "o"]
        if os == "Mac" { files["Info.plist"] = "<plist/>" }
        let package = try await ModPackage.read(try mods.zip(os, files))
        #expect(package.root == "")
        #expect(package.name == "Atomic Mod")
        #expect(package.gamePatch == "game.xdelta")
        #expect(package.hasFilesToCopy)
    }
}

@Test func readsAnAtomicWindowsModThatAlsoSupportsAndroid() async throws {
    let mods = Mods()
    let zip = try mods.zip("android", ["profile.xml": atomicProfile(os: "Windows", android: true), "data.xdelta": "d", "AM2R.xdelta": "r",
                                       "droid.xdelta": "a", "android/AM2RWrapper.apk": "apk", "android/AM2R.ini": "[ini]"])
    let package = try await ModPackage.read(zip)
    #expect(package.gamePatch == "data.xdelta")
    #expect(!package.hasFilesToCopy)
}

@Test func readsAProfileXMLThatDeclaresUTF16() async throws {
    // .NET writers that serialize to a string declare utf-16 although the file is UTF-8.
    let mods = Mods()
    let zip = try mods.zip("utf16", ["profile.xml": atomicProfile(declaredEncoding: "utf-16"), "game.xdelta": "g"])
    #expect(try await ModPackage.read(zip).name == "Atomic Mod")
}

@Test func refusesAtomicYYCAndArchivedMods() async throws {
    let mods = Mods()
    // A Windows YYC mod has its code in the runner: only AM2R.xdelta, no data.xdelta.
    await #expect(throws: ModPackage.Failure.yyc(name: "Fast Mod")) {
        try await ModPackage.read(try mods.zip("yyc", ["profile.xml": atomicProfile(os: "Windows", name: "Fast Mod", yyc: true), "AM2R.xdelta": "r"]))
    }
    // Installable="false" marks archived Community Updates profiles that AM2RLauncher only lists.
    await #expect(throws: ModPackage.Failure.notInstallable(name: "Old Updates")) {
        try await ModPackage.read(try mods.zip("archived", ["profile.xml": atomicProfile(name: "Old Updates", installable: false), "game.xdelta": "g"]))
    }
}
