import AM2RLauncherPlusKit
import Foundation

extension AppModel {
    /// The bundled engine's build stamp; empty in a dev build without the engine.
    static var engineStamp: String {
        EngineCoverage.stamp(engineResources: Bundle.main.bundleURL.appending(path: "Contents/Resources/Engine", directoryHint: .isDirectory))
    }

    /// Asks the bundled engine which functions the profile's game calls that it lacks (S-042), once per
    /// engine build. Quick: the engine loads the game data and lists them without running anything.
    func checkEngineCoverage(_ profile: Profile) async {
        let stamp = Self.engineStamp
        guard !stamp.isEmpty, profile.builtinsCheckedWith != stamp, let engine = GameRunner.engine else { return }
        let game = profile.folder.appending(path: "game.ios")
        guard FileManager.default.fileExists(atPath: game.path) else { return }
        let result = await Task.detached(priority: .utility) { () -> Result<[String], EngineCoverage.Failure> in
            Result { () throws(EngineCoverage.Failure) in try EngineCoverage.missing(game: game, engine: engine) }
        }.value
        switch result {
        case .success(let names):
            profile.missingBuiltins = names
            profile.builtinsCheckedWith = stamp
            try? container.mainContext.save()
            log(names.isEmpty ? .info : .warning, "Engine",
                names.isEmpty ? "\(profile.name): the engine has every function the game calls"
                              : "\(profile.name) calls functions the engine lacks: \(names.joined(separator: ", "))")
        case .failure(let failure):
            log(.error, "Engine", "Checking the functions \(profile.name) calls: \(failure)")
        }
    }
}
