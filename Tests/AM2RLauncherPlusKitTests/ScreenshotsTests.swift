import Foundation
import Testing
@testable import AM2RLauncherPlusKit

@Test func screenshotsAreThePNGsInSnapNewestFirst() throws {
    let saves = FileManager.default.temporaryDirectory.appending(path: "snaps-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: saves) }
    #expect(Screenshots.list(in: saves).isEmpty)
    let snap = Screenshots.folder(in: saves)
    try FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
    let names = ["snap 0000.png", "snap 0001.png", "snap 0002.PNG", "notes.txt"]
    for (index, name) in names.enumerated() {
        let file = snap.appending(path: name)
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000 + Double(index))], ofItemAtPath: file.path)
    }
    #expect(Screenshots.list(in: saves).map(\.lastPathComponent) == ["snap 0002.PNG", "snap 0001.png", "snap 0000.png"])
}
