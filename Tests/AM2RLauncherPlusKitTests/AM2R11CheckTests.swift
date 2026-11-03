import Foundation
import Testing
@testable import AM2RLauncherPlusKit

/// Builds small fake game folders and zips in a temp directory.
private struct Fixture {
    let dir = FileManager.default.temporaryDirectory.appending(path: "am2r11-tests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

    func folder(_ name: String, files: [String: String]) -> URL {
        let root = dir.appending(path: name, directoryHint: .isDirectory)
        for (path, contents) in files {
            let file = root.appending(path: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(contents.utf8).write(to: file)
        }
        return root
    }

    func zip(_ name: String, files: [String: String]) -> URL {
        let source = folder(name + "-src", files: files)
        let zip = dir.appending(path: name + ".zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-qr", zip.path, "."]
        try? process.run()
        process.waitUntilExit()
        return zip
    }
}

@Test func rejectsAFileThatIsNotAZip() throws {
    let fixture = Fixture()
    let file = fixture.folder("x", files: ["notes.txt": "hi"]).appending(path: "notes.txt")
    #expect(throws: AM2R11.Problem.notZipOrFolder) { try AM2R11.check(file) }
}

@Test func rejectsAFolderWithoutDataWin() {
    let fixture = Fixture()
    let folder = fixture.folder("empty", files: ["readme.txt": "hi"])
    #expect(throws: AM2R11.Problem.missingDataWin) { try AM2R11.check(folder) }
}

@Test func rejectsAModifiedDataWinInAFolder() {
    let fixture = Fixture()
    let folder = fixture.folder("game", files: ["data.win": "not the real game"])
    #expect(throws: AM2R11.Problem.wrongDataWin) { try AM2R11.check(folder) }
}

@Test func rejectsAModifiedDataWinInAZip() {
    let fixture = Fixture()
    let zip = fixture.zip("game", files: ["data.win": "not the real game", "AM2R.exe": "x"])
    #expect(throws: AM2R11.Problem.wrongDataWin) { try AM2R11.check(zip) }
}

@Test func rejectsAZipWithoutDataWin() {
    let fixture = Fixture()
    let zip = fixture.zip("nogame", files: ["readme.txt": "hi"])
    #expect(throws: AM2R11.Problem.missingDataWin) { try AM2R11.check(zip) }
}

@Test func rejectsADamagedZip() {
    let fixture = Fixture()
    let zip = fixture.folder("d", files: ["broken.zip": "PK not really"]).appending(path: "broken.zip")
    #expect(throws: AM2R11.Problem.unreadableZip) { try AM2R11.check(zip) }
}

@Test("Finds data.win at the top or in one subfolder", arguments: [
    (["data.win", "AM2R.exe"], ""),
    (["AM2R_11/", "AM2R_11/data.win", "AM2R_11/AM2R.exe"], "AM2R_11/"),
    (["a/data.win", "b/data.win"], nil),
    (["a/b/data.win"], nil),
] as [([String], String?)])
func zipRoot(entries: [String], expected: String?) {
    #expect(AM2R11.zipRoot(entries) == expected)
}

@Test func md5MatchesTheKnownValue() throws {
    let fixture = Fixture()
    let file = fixture.folder("h", files: ["a.txt": "hello"]).appending(path: "a.txt")
    #expect(AM2R11.md5(of: file) == "5d41402abc4b2a76b9719d911017c592")
}

@Test func hashCacheSurvivesReloadAndIsKeyedBySizeAndDate() throws {
    let fixture = Fixture()
    let file = fixture.folder("c", files: ["a.txt": "hello"]).appending(path: "a.txt")
    let store = fixture.dir.appending(path: "hashes.json")
    let key = try #require(HashCache.Key(url: file, member: ""))
    HashCache(file: store).store("abc", for: key)
    #expect(HashCache(file: store).value(for: key) == "abc")

    try Data("hello world".utf8).write(to: file)
    let changed = try #require(HashCache.Key(url: file, member: ""))
    #expect(HashCache(file: store).value(for: changed) == nil)
}

/// Runs against the real game when AM2R11_PATH points at a 1.1 zip or folder (not in CI).
@Test(.enabled(if: ProcessInfo.processInfo.environment["AM2R11_PATH"] != nil))
func acceptsTheRealAM2R11() throws {
    let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AM2R11_PATH"]!)
    let copy = try AM2R11.check(url)
    #expect(copy.hasWindowsGame)
}
