import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private func manifest(_ commit: String, game: String = "g1", readme: String = "r1", xml: String = "x1") -> PatchData.Manifest {
    PatchData.Manifest(commit: commit, files: [
        PatchData.File(path: "profile.xml", blob: xml, size: 1),
        PatchData.File(path: "data/game.xdelta", blob: game, size: 1),
        PatchData.File(path: "README.md", blob: readme, size: 1),
        PatchData.File(path: "data/droid.xdelta", blob: readme, size: 1),
    ])
}

@Test func checksAtMostOnceADay() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
    #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
    #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
    #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
    #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
}

@Test func aNewCommitIsAnUpdateOnlyWhenTheGameFilesChange() {
    let installed = manifest("aaa")
    #expect(!UpdateCheck.isNewer(manifest("aaa"), than: installed, installedCommit: "aaa"))
    #expect(!UpdateCheck.isNewer(manifest("bbb", readme: "r2"), than: installed, installedCommit: "aaa"))
    #expect(UpdateCheck.isNewer(manifest("bbb", game: "g2"), than: installed, installedCommit: "aaa"))
    #expect(UpdateCheck.isNewer(manifest("bbb", xml: "x2"), than: installed, installedCommit: "aaa"))
    // Without the installed manifest, any other commit counts; a profile without a commit never does.
    #expect(UpdateCheck.isNewer(manifest("bbb", readme: "r2"), than: nil, installedCommit: "aaa"))
    #expect(!UpdateCheck.isNewer(manifest("bbb", game: "g2"), than: installed, installedCommit: ""))
}

@Test func bannerTitles() {
    #expect(UpdateCheck.title(latestVersion: "1.5.6", installedVersion: "1.5.5") == "Community Updates 1.5.6 is available")
    #expect(UpdateCheck.title(latestVersion: "1.5.5", installedVersion: "1.5.5") == "An update to Community Updates 1.5.5 is available")
}

@Test func theLastCheckIsKept() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "update-\(UUID().uuidString)/latest.json")
    let latest = UpdateCheck.Latest(manifest: manifest("bbb"), version: "1.5.6", checkedAt: Date(timeIntervalSince1970: 1_700_000_000))
    try UpdateCheck.write(latest, to: file)
    #expect(UpdateCheck.read(from: file) == latest)
    #expect(UpdateCheck.read(from: file.deletingLastPathComponent().appending(path: "none.json")) == nil)
}

@Test func theInstalledManifestIsReadFromThePatchFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "patch-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONEncoder().encode(manifest("aaa")).write(to: folder.appending(path: "manifest.json"))
    #expect(PatchData.installedManifest(in: folder) == manifest("aaa"))
}

/// Set NETWORK_TESTS=1 to ask GitHub for real.
@Test(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"))
func readsTheLatestVersionFromGitHub() async throws {
    let latest = try await UpdateCheck.fetch(rosetta: false, known: nil)
    #expect(latest.commit.count == 40)
    #expect(latest.version.hasPrefix("1.5"))
}
