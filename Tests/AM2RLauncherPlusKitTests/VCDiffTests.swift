import Foundation
import Testing
@testable import AM2RLauncherPlusKit

private let xdelta3 = ["/opt/homebrew/bin/xdelta3", "/usr/local/bin/xdelta3"].first { FileManager.default.isExecutableFile(atPath: $0) }

/// Encodes with the real xdelta3 tool (only on Macs that have it), so the decoder is checked against the reference.
private func encode(source: Data, target: Data, flags: [String]) throws -> Data {
    let dir = FileManager.default.temporaryDirectory.appending(path: "vcdiff-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let s = dir.appending(path: "source"), t = dir.appending(path: "target"), p = dir.appending(path: "patch")
    try source.write(to: s)
    try target.write(to: t)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: xdelta3!)
    process.arguments = ["-e", "-f"] + flags + ["-s", s.path, t.path, p.path]
    try process.run()
    process.waitUntilExit()
    return try Data(contentsOf: p)
}

/// A source and a target that share most bytes, with edits, runs and moved blocks.
private func samplePair(size: Int, seed: UInt64) -> (Data, Data) {
    var generator = SplitMix(seed: seed)
    var source = [UInt8](repeating: 0, count: size)
    for i in 0..<size { source[i] = UInt8(truncatingIfNeeded: generator.next() % 23) }
    var target = source
    for _ in 0..<(size / 997) { target[Int(generator.next() % UInt64(size))] = UInt8(truncatingIfNeeded: generator.next()) }
    target.replaceSubrange(size / 3 ..< size / 3 + 500, with: [UInt8](repeating: 7, count: 2000))
    target.append(contentsOf: source[0 ..< size / 4])
    return (Data(source), Data(target))
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Test(.enabled(if: xdelta3 != nil), arguments: [
    ["-S", "none"],
    ["-S", "lzma"],
    ["-S", "lzma", "-9"],
    ["-S", "none", "-B", "65536", "-W", "16384"], // many small windows
    ["-S", "lzma", "-B", "65536", "-W", "16384"], // LZMA streams that continue across windows
])
func decodesWhatXdelta3Encodes(flags: [String]) throws {
    let (source, target) = samplePair(size: 300_000, seed: 42)
    let patch = try encode(source: source, target: target, flags: flags)
    #expect(try VCDiff.apply(source: source, patch: patch) == target)
}

@Test(.enabled(if: xdelta3 != nil))
func decodesAnEmptyTarget() throws {
    let patch = try encode(source: Data("abc".utf8), target: Data(), flags: [])
    #expect(try VCDiff.apply(source: Data("abc".utf8), patch: patch) == Data())
}

@Test func rejectsANonPatch() {
    #expect(throws: VCDiff.Failure.notVCDiff) { try VCDiff.apply(source: Data(), patch: Data("hello".utf8)) }
}

@Test(.enabled(if: xdelta3 != nil))
func detectsADamagedPatch() throws {
    let (source, target) = samplePair(size: 50_000, seed: 7)
    var patch = try encode(source: source, target: target, flags: ["-S", "none"])
    patch[patch.count - 10] ^= 0xFF
    #expect(throws: (any Error).self) { try VCDiff.apply(source: source, patch: patch) }
}

@Test func adler32MatchesTheKnownValue() {
    #expect(VCDiff.adler32(Data("Wikipedia".utf8)) == 0x11E60398)
}

@Test func standardCodeTableHasTheRFCEntries() {
    let table = CodeTable.standard.entries
    #expect(table[0].first.kind == .run)
    #expect(table[18].first.kind == .add && table[18].firstSize == 17)
    #expect(table[19].first.kind == .copy && table[19].firstSize == 0 && table[19].first.mode == 0)
    #expect(table[162].first.kind == .copy && table[162].first.mode == 8 && table[162].firstSize == 18)
    #expect(table[163].first.kind == .add && table[163].second.kind == .copy && table[163].secondSize == 4)
    #expect(table[255].first.kind == .copy && table[255].first.mode == 8 && table[255].second.kind == .add)
}

/// The real patch: AM2R 1.1 data.win + Mac game.xdelta = Community Updates 1.5.5 game.ios.
/// Set AM2R11_DATAWIN and GAME_XDELTA to run it.
@Test(.enabled(if: ProcessInfo.processInfo.environment["GAME_XDELTA"] != nil))
func patchesAM2R11IntoCommunityUpdates() throws {
    let env = ProcessInfo.processInfo.environment
    let output = FileManager.default.temporaryDirectory.appending(path: "game-\(UUID().uuidString).ios")
    try VCDiff.apply(source: URL(fileURLWithPath: env["AM2R11_DATAWIN"]!), patch: URL(fileURLWithPath: env["GAME_XDELTA"]!), output: output)
    #expect(AM2R11.md5(of: output) == "0de029951c94b04545c9c257053ad712")
    try? FileManager.default.removeItem(at: output)
}
