import AM2RLauncherPlusKit
import SwiftUI

/// Play page > Save Slots: gives a save slot every upgrade (S-037). The game has no cheat for it,
/// so the launcher edits the slot, after backing up the profile's saves.
struct UpgradesSection: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var slots: [URL] = []
    @State private var message: String?
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        // The Rosetta runner keeps its saves in its own folder.
        if profile.engine != .rosetta {
            Section("Save Slots") {
                LabeledContent {
                    Menu("Give…") {
                        ForEach(Array(slots.enumerated()), id: \.element) { _, slot in
                            Menu(Self.title(of: slot)) {
                                ForEach(GameSave.Upgrades.allCases) { upgrades in
                                    Button(Self.title(of: upgrades)) { give(upgrades, to: slot) }
                                }
                            }
                        }
                    }
                    .fixedSize()
                    .disabled(slots.isEmpty || working)
                    .help(slots.isEmpty ? "Save the game once to make a slot" : "Choose a slot and what to give")
                } label: {
                    Text("Every Upgrade")
                    Text(slots.isEmpty ? "No saves yet. Play and save first." : "Edits a save slot. Your saves are backed up first.")
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.multicolor)
                }
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            .task(id: LoadKey(profile: profile.uuid, playing: model.isPlaying)) {
                slots = GameSave.slots(in: GameRunner.saveFolder(for: profile))
            }
            .onChange(of: profile.uuid) { message = nil; failure = nil }
        }
    }

    static func title(of slot: URL) -> String {
        "Save \(slot.lastPathComponent.dropFirst("save".count))"
    }

    static func title(of upgrades: GameSave.Upgrades) -> String {
        switch upgrades {
        case .abilities: "Abilities, Beams and Suits"
        case .everything: "Everything, Maxed"
        }
    }

    private func give(_ upgrades: GameSave.Upgrades, to slot: URL) {
        working = true
        message = nil
        failure = nil
        Task {
            defer { working = false }
            switch await model.giveUpgrades(upgrades, to: slot, profile: profile) {
            case .success:
                message = "\(Self.title(of: slot)) now has every upgrade. Load it in the game."
            case .failure(let error):
                failure = error.message
            }
        }
    }
}

extension AppModel {
    enum UpgradeFailure: Error {
        case backup(String)
        case save(GameSave.Failure)

        var message: String {
            switch self {
            case .backup(let message): "The saves couldn't be backed up, so the slot wasn't changed. \(message)"
            case .save(let failure): failure.message
            }
        }
    }

    /// Backs up the profile's saves ("before upgrades"), then edits the slot.
    func giveUpgrades(_ upgrades: GameSave.Upgrades, to slot: URL, profile: Profile) async -> Result<Void, UpgradeFailure> {
        guard game?.profileID != profile.uuid else { return .failure(.save(.unwritable)) }
        guard await backUpSaves(profile, label: "before upgrades") != nil else { return .failure(.backup(backupError ?? "")) }
        let game = profile.folder.appending(path: "game.ios")
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, GameSave.Failure> in
            Result { () throws(GameSave.Failure) in try GameSave.giveUpgrades(upgrades, slot: slot, game: game) }
        }.value
        switch result {
        case .success:
            log(.info, "Saves", "Gave \(slot.lastPathComponent) of \(profile.name) every upgrade (\(upgrades.rawValue))")
            return .success(())
        case .failure(let failure):
            log(.error, "Saves", "Give \(slot.lastPathComponent) of \(profile.name) every upgrade: \(failure.message)")
            return .failure(.save(failure))
        }
    }
}
