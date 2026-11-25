import Foundation
import ProcessKit

/// Which GameMaker functions a game calls that the native engine doesn't have (S-042), told by the
/// engine itself: `butterscotch --headless --print-unknown-functions game.ios` lists them as "- name".
/// A mod can call functions Community Updates never does; those parts of it won't work natively.
public enum EngineCoverage {
    /// Missing on purpose (tools/engine-check/known-missing.txt): Android touch controls and a debug key.
    public static let harmless: Set<String> = [
        "show_debug_overlay", "device_mouse_dbclick_enable", "display_get_dpi_x", "display_get_dpi_y",
        "sprite_assign", "device_mouse_raw_x", "device_mouse_raw_y", "point_in_triangle",
    ]

    /// The names in the engine's report, minus the harmless ones, sorted.
    public static func missing(inReport report: String) -> [String] {
        let names = report.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("- ") else { return nil }
            let name = text.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return name.isEmpty || harmless.contains(name) ? nil : name
        }
        return Array(Set(names)).sorted()
    }

    public enum Failure: Error, Equatable, Sendable {
        case couldNotRun(String)
        /// The engine didn't print its report (an older engine, or the game didn't load).
        case noReport
    }

    /// Asks the engine. Takes a fraction of a second: the game data is loaded, nothing runs.
    public static func missing(game: URL, engine: URL) throws(Failure) -> [String] {
        let output: Shell.Output
        do {
            output = try Shell.runSync(engine.path, ["--headless", "--disable-log-colours", "--print-unknown-functions", game.lastPathComponent],
                                       options: Shell.Options(directory: game.deletingLastPathComponent(), stderr: .merged))
        } catch {
            throw .couldNotRun(error.localizedDescription)
        }
        let report = output.text
        guard report.contains("Unknown Functions:") else { throw .noReport }
        return missing(inReport: report)
    }

    /// The engine build's stamp (Engine/VERSION in the app), so a profile is checked again after an engine update.
    public static func stamp(engineResources: URL) -> String {
        ((try? String(contentsOf: engineResources.appending(path: "VERSION"), encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
