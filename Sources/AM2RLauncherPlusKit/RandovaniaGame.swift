import Foundation

/// Randovania's AM2R randomizer on a Mac (S-036). It patches a folder holding
/// AM2R.app/Contents/Resources/game.ios (Community Updates 1.5.5, checked together with
/// Contents/MacOS/Mac_Runner) and exports the same layout with the seed in game.ios.
public enum RandovaniaGame {
    public enum Failure: Error, Equatable, Sendable {
        case notAnExport
        case noGameFiles

        public var message: String {
            switch self {
            case .notAnExport: "This folder has no Randovania game. Export the seed from Randovania first."
            case .noGameFiles: "This profile has no game files to prepare."
            }
        }
    }

    /// The game files in an exported folder: AM2R.app inside it, or the chosen AM2R.app itself.
    public static func resources(in folder: URL) throws(Failure) -> URL {
        let candidates = [
            folder.appending(path: "AM2R.app/Contents/Resources", directoryHint: .isDirectory),
            folder.appending(path: "Contents/Resources", directoryHint: .isDirectory),
        ]
        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appending(path: "game.ios").path) }) else {
            throw .notAnExport
        }
        return found
    }

    /// A name for the seed: Randovania's word hash when the export kept its data (spoiler seeds),
    /// else the exported folder's name.
    public static func seedName(resources: URL, folder: URL) -> String {
        let data = resources.appending(path: "yams-data.json")
        if let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: data)) as? [String: Any],
           let identifier = json["configuration_identifier"] as? [String: Any],
           let hash = identifier["word_hash"] as? String, !hash.isEmpty {
            return hash
        }
        let name = folder.pathExtension == "app" ? folder.deletingLastPathComponent().lastPathComponent : folder.lastPathComponent
        return name.isEmpty ? "Randovania Seed" : name
    }

    /// Writes the input folder Randovania asks for: AM2R.app with the profile's game files in
    /// Contents/Resources and a Mac_Runner that points back to the launcher. Returns the app.
    @discardableResult
    public static func prepare(profile: URL, into folder: URL) throws -> URL {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: profile, includingPropertiesForKeys: nil)
        guard items.contains(where: { $0.lastPathComponent == "game.ios" }) else { throw Failure.noGameFiles }
        let app = folder.appending(path: "AM2R.app", directoryHint: .isDirectory)
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }
        let resources = app.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        for item in items where !item.lastPathComponent.hasPrefix(".") {
            try fm.copyItem(at: item, to: resources.appending(path: item.lastPathComponent))
        }
        let runner = macOS.appending(path: "Mac_Runner")
        try "#!/bin/sh\necho 'Play this game in AM2R Launcher Plus: Profile > Import Randovania Game…'\nexit 1\n"
            .write(to: runner, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)
        let plist: [String: Any] = ["CFBundleExecutable": "Mac_Runner", "CFBundleName": "AM2R",
                                    "CFBundleIdentifier": "am2rlauncherplus.randovania-input", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        return app
    }

    /// Copies an export's game files into a new profile folder.
    public static func importGame(from resources: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) where !item.lastPathComponent.hasPrefix(".") {
            try fm.copyItem(at: item, to: destination.appending(path: item.lastPathComponent))
        }
    }
}
