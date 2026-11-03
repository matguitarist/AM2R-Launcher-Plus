import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "rdv-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func preparesTheFolderRandovaniaAsksFor() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = dir.appending(path: "profile", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: profile.appending(path: "lang"), withIntermediateDirectories: true)
    try Data("FORM".utf8).write(to: profile.appending(path: "game.ios"))
    try Data("en".utf8).write(to: profile.appending(path: "lang/english.ini"))
    let input = dir.appending(path: "input", directoryHint: .isDirectory)
    try RandovaniaGame.prepare(profile: profile, into: input)
    let fm = FileManager.default
    // What Randovania's _is_valid_input_dir checks on macOS.
    #expect(fm.fileExists(atPath: input.appending(path: "AM2R.app/Contents/Resources/game.ios").path))
    #expect(fm.isExecutableFile(atPath: input.appending(path: "AM2R.app/Contents/MacOS/Mac_Runner").path))
    #expect(fm.fileExists(atPath: input.appending(path: "AM2R.app/Contents/Resources/lang/english.ini").path))
    // Preparing again replaces the app.
    try RandovaniaGame.prepare(profile: profile, into: input)
    #expect(throws: RandovaniaGame.Failure.noGameFiles) { try RandovaniaGame.prepare(profile: dir.appending(path: "input"), into: dir) }
}

@Test func findsTheGameInAnExport() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let export = dir.appending(path: "My Seed", directoryHint: .isDirectory)
    let resources = export.appending(path: "AM2R.app/Contents/Resources", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try Data("FORM".utf8).write(to: resources.appending(path: "game.ios"))
    #expect(try RandovaniaGame.resources(in: export) == resources)
    #expect(try RandovaniaGame.resources(in: export.appending(path: "AM2R.app")) == resources)
    #expect(throws: RandovaniaGame.Failure.notAnExport) { try RandovaniaGame.resources(in: dir) }
    #expect(RandovaniaGame.seedName(resources: resources, folder: export) == "My Seed")
    #expect(RandovaniaGame.seedName(resources: resources, folder: export.appending(path: "AM2R.app")) == "My Seed")
    try Data(#"{"configuration_identifier": {"word_hash": "Chozo Baby Spider"}}"#.utf8).write(to: resources.appending(path: "yams-data.json"))
    #expect(RandovaniaGame.seedName(resources: resources, folder: export) == "Chozo Baby Spider")

    let profile = dir.appending(path: "profile", directoryHint: .isDirectory)
    try RandovaniaGame.importGame(from: resources, to: profile)
    #expect(FileManager.default.fileExists(atPath: profile.appending(path: "game.ios").path))
}
