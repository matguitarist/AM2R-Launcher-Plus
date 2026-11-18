import AM2RLauncherPlusKit
import AppKit
import SwiftUI

/// Extras page > Randomizer (S-040): the game's randomizer seed and Starting Paths, kept in the
/// profile's modifiers.ini, and the seed of each randomized save so it can be shared or replayed.
struct RandomizerSection: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var options: RandomizerOptions?
    @State private var seedText = ""
    @State private var games: [(slot: URL, game: RandomizedGame)] = []
    @State private var loadedFor: UUID?
    @State private var failure: String?
    @State private var copied: URL?

    var body: some View {
        // The section always shows, so its task runs and loads the options.
        Section {
            if let options {
                settings(options)
                ForEach(games, id: \.slot) { entry in
                    LabeledContent {
                        HStack(spacing: Space.sm) {
                            Button(copied == entry.slot ? "Copied" : "Copy Seed") { copy(entry) }
                                .help("Copy seed \(entry.game.seed) to share it")
                            Button("Use Seed") { use(entry) }
                                .disabled(self.options?.useCustomSeed == true && self.options?.seed == entry.game.seed)
                                .help("New randomized games use this seed, to play the same layout again")
                        }
                        .fixedSize()
                    } label: {
                        Text(UpgradesSection.title(of: entry.slot))
                        Text("\(entry.game.mode.title), seed \(entry.game.seed)")
                            .textSelection(.enabled)
                    }
                }
            } else if loadedFor == profile.uuid {
                Text("\(profile.name) has no randomizer settings.")
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
        } header: {
            Text("Randomizer")
        } footer: {
            if options != nil {
                Text("Starting Paths is a Classic Mode choice in the game's randomizer. The game reads these when it starts.")
            }
        }
        .task(id: LoadKey(profile: profile.uuid, playing: model.isPlaying)) { load() }
    }

    @ViewBuilder private func settings(_ current: RandomizerOptions) -> some View {
        Toggle(isOn: binding(\.useCustomSeed)) {
            Text("Use a Custom Seed")
            Text("New randomized games use this seed, so a layout can be played again or shared")
        }
        LabeledContent("Seed") {
            TextField("Seed", text: $seedText, prompt: Text("0"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 140)
                .onSubmit(commitSeed)
                .onChange(of: seedText) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(10))
                    if digits != new { seedText = digits } else { commitSeed() }
                }
        }
        .disabled(!current.useCustomSeed)
        startingPath("Bomb Run", "Bombs may be the first item, the easier start", \.bombRun)
        startingPath("Power Bomb Run", "Power Bombs may be the first item after Bombs", \.powerBombRun)
        startingPath("Screw Attack Run", "Screw Attack may be the first item after Bombs, the hardest start", \.screwAttackRun)
    }

    /// Starting Paths needs one item to start with, so the last one on can't be turned off.
    private func startingPath(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ key: WritableKeyPath<RandomizerOptions, Bool>) -> some View {
        let isLast = options.map { $0[keyPath: key] && [$0.bombRun, $0.powerBombRun, $0.screwAttackRun].filter { $0 }.count == 1 } ?? false
        return Toggle(isOn: binding(key)) {
            Text(title)
            Text(detail)
        }
        .disabled(isLast)
        .help(isLast ? "Starting Paths needs at least one item to start with" : "")
    }

    private func binding(_ key: WritableKeyPath<RandomizerOptions, Bool>) -> Binding<Bool> {
        Binding {
            options?[keyPath: key] ?? false
        } set: { value in
            guard var changed = options else { return }
            changed[keyPath: key] = value
            save(changed)
        }
    }

    private func commitSeed() {
        guard var changed = options else { return }
        let clean = RandomizerOptions.cleanSeed(seedText.isEmpty ? "0" : seedText)
        guard clean != changed.seed else { return }
        changed.seed = clean
        save(changed)
    }

    private func load() {
        loadedFor = nil
        options = RandomizerOptions.read(from: profile.folder)
        seedText = options?.seed ?? ""
        let game = profile.folder.appending(path: "game.ios")
        games = profile.engine == .rosetta ? [] : GameSave.slots(in: GameRunner.saveFolder(for: profile)).compactMap { slot in
            GameSave.randomizedGame(slot: slot, game: game).map { (slot, $0) }
        }
        failure = nil
        copied = nil
        loadedFor = profile.uuid
    }

    private func save(_ changed: RandomizerOptions) {
        guard loadedFor == profile.uuid, changed != options else { return }
        do {
            try changed.write(to: profile.folder)
            options = changed
            failure = nil
        } catch {
            failure = "Unable to save the randomizer settings: \(error.localizedDescription)"
            log(.error, "Randomizer", "Write modifiers.ini of \(profile.name): \(error)")
        }
    }

    private func copy(_ entry: (slot: URL, game: RandomizedGame)) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.game.seed, forType: .string)
        copied = entry.slot
    }

    private func use(_ entry: (slot: URL, game: RandomizedGame)) {
        guard var changed = options else { return }
        changed.useCustomSeed = true
        changed.seed = entry.game.seed
        seedText = entry.game.seed
        save(changed)
    }
}
