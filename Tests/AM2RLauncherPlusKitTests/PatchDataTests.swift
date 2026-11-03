import Foundation
import Testing
@testable import AM2RLauncherPlusKit

@Test func blobSHAMatchesGit() {
    #expect(PatchData.blobSHA(of: Data()) == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
    #expect(PatchData.blobSHA(of: Data("hello\n".utf8)) == "ce013625030ba8dba906f756967f9e9ca394464a")
}

@Test func readsTheVersionFromProfileXML() {
    let xml = #"<message xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OperatingSystem="Mac" Version="1.5.5" Name="Community Updates (Latest)" Author="AM2R Community Developers" UsesCustomMusic="false" />"#
    #expect(PatchData.profileInfo(xml) == .init(name: "Community Updates (Latest)", version: "1.5.5", author: "AM2R Community Developers"))
    #expect(PatchData.profileInfo("<message />") == nil)
}

@Test("Downloads only what a profile needs", arguments: [
    ("profile.xml", false, true),
    ("data/game.xdelta", false, true),
    ("data/files_to_copy/lang/english.ini", false, true),
    ("data/droid.xdelta", true, false),
    ("data/HDR_HQ_in-game_music/musArea1A.ogg", true, false),
    ("utilities/android/apktool.jar", true, false),
    ("data/AM2R.xdelta", false, false),
    ("data/AM2R.xdelta", true, true),
    ("data/Frameworks/libyoyo.dylib", true, true),
])
func neededFiles(path: String, rosetta: Bool, expected: Bool) {
    #expect(PatchData.isNeeded(path, rosetta: rosetta) == expected)
}

@Test func buildsAManifestFromTheTree() throws {
    let json = #"{"truncated":false,"tree":[{"path":"profile.xml","type":"blob","sha":"a","size":3},{"path":"data","type":"tree","sha":"b"},{"path":"data/game.xdelta","type":"blob","sha":"c","size":10},{"path":"data/droid.xdelta","type":"blob","sha":"d","size":99}]}"#
    let tree = try JSONDecoder().decode(PatchData.TreeResponse.self, from: Data(json.utf8))
    let manifest = try PatchData.manifest(commit: "abc", tree: tree, rosetta: false)
    #expect(manifest.files.map(\.path) == ["profile.xml", "data/game.xdelta"])
    #expect(manifest.totalSize == 13)
}

@Test func rejectsATreeWithoutThePatch() throws {
    let json = #"{"truncated":false,"tree":[{"path":"profile.xml","type":"blob","sha":"a","size":3}]}"#
    let tree = try JSONDecoder().decode(PatchData.TreeResponse.self, from: Data(json.utf8))
    #expect(throws: PatchData.Failure.badResponse) { try PatchData.manifest(commit: "abc", tree: tree, rosetta: false) }
}

/// Real download from GitHub (about 36 MB). Set NETWORK_TESTS=1 to run.
@Test(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"))
func downloadsTheRealPatchData() async throws {
    let manifest = try await PatchData.latestManifest(rosetta: false)
    let folder = FileManager.default.temporaryDirectory.appending(path: "patchdata-test", directoryHint: .isDirectory)
    let result = try await PatchData.download(manifest, into: folder)
    #expect(FileManager.default.fileExists(atPath: result.appending(path: "data/game.xdelta").path))
    let xml = try String(contentsOf: result.appending(path: "profile.xml"), encoding: .utf8)
    #expect(PatchData.profileInfo(xml)?.version.hasPrefix("1.5") == true)
    // A second download is reused, not fetched again.
    let start = Date.now
    _ = try await PatchData.download(manifest, into: folder)
    #expect(Date.now.timeIntervalSince(start) < 1)
}
