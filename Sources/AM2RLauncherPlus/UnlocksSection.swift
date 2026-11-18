import AM2RLauncherPlusKit
import SwiftUI

/// Extras page > Unlocks (S-044): what finishing the game unlocks, without finishing it. Writes the
/// game's own data.sav and extras.sav in the profile's save folder, after backing up its saves.
struct UnlocksSection: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var unlocked = false
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        // The Rosetta runner keeps its saves in its own folder.
        if profile.engine != .rosetta {
            Section("Unlocks") {
                LabeledContent {
                    if unlocked {
                        Label("Unlocked", systemImage: "checkmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Unlock Everything", action: unlock)
                            .disabled(working)
                            .help("Unlocks what finishing the game unlocks. Your saves are backed up first.")
                    }
                } label: {
                    Text("Game Unlocks")
                    Text("New Game+, Random Game+, Fusion difficulty and the Samus Returns Fusion Suit, the gallery, and collected items on the map")
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            .task(id: LoadKey(profile: profile.uuid, playing: model.isPlaying)) { load() }
            .onChange(of: profile.uuid) { failure = nil }
        }
    }

    private func load() {
        let saves = GameRunner.saveFolder(for: profile), game = profile.folder.appending(path: "game.ios")
        unlocked = GameUnlocks.isEverythingUnlocked(saves: saves, game: game)
    }

    private func unlock() {
        working = true
        failure = nil
        Task {
            defer { working = false }
            switch await model.unlockEverything(profile: profile) {
            case .success: unlocked = true
            case .failure(let error): failure = error.message
            }
        }
    }
}

extension AppModel {
    /// Backs up the profile's saves ("before unlocks") when it has any, then writes the unlocks.
    func unlockEverything(profile: Profile) async -> Result<Void, UpgradeFailure> {
        guard game?.profileID != profile.uuid else { return .failure(.save(.unwritable)) }
        let saves = GameRunner.saveFolder(for: profile)
        let hasSaves = !((try? FileManager.default.contentsOfDirectory(atPath: saves.path)) ?? []).filter { !$0.hasPrefix(".") }.isEmpty
        if hasSaves, await backUpSaves(profile, label: "before unlocks") == nil { return .failure(.backup(backupError ?? "")) }
        let game = profile.folder.appending(path: "game.ios")
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, GameSave.Failure> in
            Result { () throws(GameSave.Failure) in try GameUnlocks.unlockEverything(saves: saves, game: game) }
        }.value
        switch result {
        case .success:
            log(.info, "Saves", "Unlocked everything for \(profile.name)")
            return .success(())
        case .failure(let failure):
            log(.error, "Saves", "Unlock everything for \(profile.name): \(failure.message)")
            return .failure(.save(failure))
        }
    }
}
