import Foundation
import Testing
@testable import AM2RLauncherPlusKit

/// The engine's report for Community Updates 1.5.5 with patch 0013, plus two a mod might add.
private let report = """
Loading game.ios...
Loaded "AM2R" (971912648) successfully! [WAD Version 16 / GameMaker version 1.0.0.1763]
Unknown Functions:
- show_debug_overlay
- device_mouse_dbclick_enable
- display_get_dpi_x
- display_get_dpi_y
- sprite_assign
- device_mouse_raw_x
- device_mouse_raw_y
- point_in_triangle
- physics_joint_rope_create
- d3d_model_load
10 unknown function(s) out of 703 referenced
"""

@Test func theReportListsOnlyWhatMatters() {
    #expect(EngineCoverage.missing(inReport: report) == ["d3d_model_load", "physics_joint_rope_create"])
    #expect(EngineCoverage.missing(inReport: "Unknown Functions:\nAll 701 referenced functions are implemented! :3\n").isEmpty)
}

@Test func anEngineWithoutTheReportIsAFailure() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "coverage-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let engine = folder.appending(path: "engine")
    try "#!/bin/sh\necho 'Loading game.ios...'\n".write(to: engine, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: engine.path)
    #expect(throws: EngineCoverage.Failure.noReport) { try EngineCoverage.missing(game: folder.appending(path: "game.ios"), engine: engine) }
    try "#!/bin/sh\nprintf 'Unknown Functions:\\n- sprite_assign\\n- d3d_model_load\\n'\n".write(to: engine, atomically: true, encoding: .utf8)
    #expect(try EngineCoverage.missing(game: folder.appending(path: "game.ios"), engine: engine) == ["d3d_model_load"])
}
