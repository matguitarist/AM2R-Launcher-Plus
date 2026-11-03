import Foundation
import Sparkle

/// Updates of the launcher itself, with Sparkle (S-032). The feed is appcast.xml on the GitHub releases;
/// every update is signed with the EdDSA key whose public half is SUPublicEDKey in Info.plist.
/// Test, snapshot and self-test runs (APP_STORE set) never check.
@Observable
final class LauncherUpdater {
    static let shared = LauncherUpdater()

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private(set) var canCheck = false
    var checksAutomatically: Bool {
        didSet {
            if updater.automaticallyChecksForUpdates != checksAutomatically { updater.automaticallyChecksForUpdates = checksAutomatically }
        }
    }

    private var updater: SPUUpdater { controller.updater }

    /// The version people see in Settings: "0.2.0 (202611031905)".
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: !Store.isOverridden, updaterDelegate: nil, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.canCheck = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in if self?.checksAutomatically != value { self?.checksAutomatically = value } }
            },
        ]
    }

    /// AM2R Launcher Plus › Check for Updates… and Settings › General › Check Now.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
