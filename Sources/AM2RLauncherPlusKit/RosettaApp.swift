import Foundation

/// The Rosetta engine (S-014): the official GameMaker runner, rebuilt from AM2R 1.1's AM2R.exe like
/// AM2R-Autopatcher-Mac's patcher.command does, as `<profile>/AM2R.app`, and run by Rosetta 2.
public enum RosettaApp {
    public static let appName = "AM2R.app"
    /// CFBundleExecutable in the patch data's Info.plist.
    static let runnerName = "Mac_Runner"

    public enum Failure: Error, Equatable, Sendable {
        case noWindowsGame
        case noRunnerPatch
        case patchFailed(String)
        case copyFailed(String)

        public var message: String {
            switch self {
            case .noWindowsGame: "Rosetta needs AM2R.exe from AM2R 1.1. Choose a complete copy of AM2R 1.1."
            case .noRunnerPatch: "The patch data of this profile has no Rosetta runner. Install the profile again."
            case .patchFailed: "Unable to build the Rosetta app. AM2R.exe doesn't match the patch data."
            case .copyFailed: "Unable to build the Rosetta app. There may not be enough space in the data folder."
            }
        }
    }

    /// True when Rosetta 2 is installed on this Mac.
    public static var isRosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    /// One bundle id per profile: the runner keeps its saves in Application Support/<bundle id>,
    /// so profiles never share saves, and Stop finds the right game.
    public static func bundleIdentifier(for profile: UUID) -> String {
        "com.yoyogames.am2r.profile-\(profile.uuidString.lowercased())"
    }

    /// The app inside a profile folder, nil when it isn't built.
    public static func app(in profileFolder: URL) -> URL? {
        let app = profileFolder.appending(path: appName, directoryHint: .isDirectory)
        let runner = app.appending(path: "Contents/MacOS/\(runnerName)")
        return FileManager.default.isExecutableFile(atPath: runner.path) ? app : nil
    }

    /// Builds `<profileFolder>/AM2R.app`: runner = AM2R.exe + AM2R.xdelta, Frameworks, Info.plist and PkgInfo
    /// from the patch data, and the profile's game files (cloned, so free on APFS) in Resources.
    /// The app is signed ad hoc (`sign`): unsigned, launchd refuses to start it. An existing app is replaced
    /// only when the new one is complete.
    /// - Parameters:
    ///   - source: the AM2R 1.1 zip or folder, with `root` the folder inside it that holds AM2R.exe.
    @discardableResult
    public static func build(source: URL, kind: AM2R11.Kind, root: String, patchData: URL, profileFolder: URL,
                             bundleIdentifier: String, sign: Bool = true) throws(Failure) -> URL {
        let fm = FileManager.default
        let data = patchData.appending(path: "data", directoryHint: .isDirectory)
        let runnerPatch = data.appending(path: "AM2R.xdelta")
        guard fm.fileExists(atPath: runnerPatch.path), fm.fileExists(atPath: data.appending(path: "Info.plist").path) else {
            throw .noRunnerPatch
        }
        let destination = profileFolder.appending(path: appName, directoryHint: .isDirectory)
        let staging = profileFolder.appending(path: appName + ".partial", directoryHint: .isDirectory)
        let contents = staging.appending(path: "Contents", directoryHint: .isDirectory)
        let work = fm.temporaryDirectory.appending(path: "am2r-rosetta-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: work) }

        do {
            let exe = try windowsGame(source: source, kind: kind, root: root, work: work)
            try fm.createDirectory(at: contents.appending(path: "MacOS", directoryHint: .isDirectory), withIntermediateDirectories: true)
            let runner = contents.appending(path: "MacOS/\(runnerName)")
            do {
                try VCDiff.apply(source: exe, patch: runnerPatch, output: runner)
            } catch {
                throw Failure.patchFailed("\(error)")
            }
            do {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner.path)
                let frameworks = data.appending(path: "Frameworks", directoryHint: .isDirectory)
                if fm.fileExists(atPath: frameworks.path) {
                    try fm.copyItem(at: frameworks, to: contents.appending(path: "Frameworks", directoryHint: .isDirectory))
                }
                if fm.fileExists(atPath: data.appending(path: "PkgInfo").path) {
                    try fm.copyItem(at: data.appending(path: "PkgInfo"), to: contents.appending(path: "PkgInfo"))
                }
                try writeInfo(from: data.appending(path: "Info.plist"), to: contents.appending(path: "Info.plist"), bundleIdentifier: bundleIdentifier)
                let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
                try fm.createDirectory(at: resources, withIntermediateDirectories: true)
                for item in try fm.contentsOfDirectory(at: profileFolder, includingPropertiesForKeys: nil) {
                    let name = item.lastPathComponent
                    if name.hasPrefix(".") || name.hasPrefix(appName) || name == "profile.xml" { continue }
                    try fm.copyItem(at: item, to: resources.appending(path: name))
                }
            } catch {
                throw Failure.copyFailed("\(error)")
            }
            if sign { try codesign(staging) }
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: staging, to: destination)
            } catch {
                throw Failure.copyFailed("\(error)")
            }
        } catch let failure as Failure {
            try? fm.removeItem(at: staging)
            throw failure
        } catch {
            try? fm.removeItem(at: staging)
            throw .copyFailed("\(error)")
        }
        return destination
    }

    /// The `open` arguments that start the app and wait until it quits, with its output in `log`.
    public static func openArguments(app: URL, log: URL) -> [String] {
        ["-W", "-n", "--stdout", log.path, "--stderr", log.path, app.path]
    }

    private static func codesign(_ app: URL) throws(Failure) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw .copyFailed("codesign: \(error)") }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw .copyFailed("codesign exited with \(process.terminationStatus)") }
    }

    /// AM2R.exe from the 1.1 folder, or unzipped into `work`.
    private static func windowsGame(source: URL, kind: AM2R11.Kind, root: String, work: URL) throws(Failure) -> URL {
        let fm = FileManager.default
        switch kind {
        case .folder:
            let exe = (root.isEmpty ? source : source.appending(path: root, directoryHint: .isDirectory)).appending(path: "AM2R.exe")
            guard fm.fileExists(atPath: exe.path) else { throw .noWindowsGame }
            return exe
        case .zip:
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", "-q", "-j", source.path, root + "AM2R.exe", "-d", work.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw Failure.noWindowsGame }
            } catch {
                throw .noWindowsGame
            }
            return work.appending(path: "AM2R.exe")
        }
    }

    /// The patch data's Info.plist with this profile's bundle id.
    private static func writeInfo(from source: URL, to target: URL, bundleIdentifier: String) throws {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: source), options: [], format: &format) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        info["CFBundleIdentifier"] = bundleIdentifier
        info["CFBundleExecutable"] = runnerName
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: target)
    }
}
