import AM2RLauncherPlusKit
import GameController
import SwiftUI

/// Display, controller and language of one profile, written to its config.ini (S-010 to S-012).
/// Shown on the Play page under the Play button: they belong to the profile, not the app.
struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var settings = GameSettings()
    @State private var languages: [GameLanguages.Language] = []
    @State private var loadedFor: UUID?
    @State private var saveError: String?
    @State private var controllers = ControllerMonitor()

    var body: some View {
        Form {
                Section {
                    Toggle("Fullscreen", isOn: $settings.fullscreen)
                    Picker(settings.fullscreen ? "Display Scale" : "Window Size", selection: $settings.scale) {
                        ForEach(Array(settings.fullscreen ? GameSettings.fullscreenScales : GameSettings.scales), id: \.self) { scale in
                            Text(scaleTitle(scale)).tag(scale)
                        }
                    }
                    Toggle("Widescreen", isOn: $settings.widescreen)
                    Picker("Filter", selection: Bindable(profile).displayFilter) {
                        ForEach(DisplayFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .help("Draw scanlines or an old CRT screen over the game")
                } header: {
                    Text("Display")
                } footer: {
                    if model.isPlaying {
                        Text("Quit AM2R to change these settings.")
                    }
                }
                Section("Controller") {
                    Picker("Layout", selection: $settings.controller) {
                        Text("Mac (Select = map, Start = pause)").tag(ControllerLayout.mac)
                        Text("Original (Start = map)").tag(ControllerLayout.original)
                        Text("Custom (set in the game)").tag(ControllerLayout.custom)
                    }
                    LabeledContent("Connected", value: controllers.names.isEmpty ? "No controller" : controllers.names.formatted(.list(type: .and)))
                }
                Section("Language") {
                    if languages.isEmpty {
                        Text("This profile has no languages list.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Game Language", selection: $settings.language) {
                            ForEach(languages) { Text($0.name).tag($0.index) }
                        }
                    }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
        }
        .formStyle(.grouped)
        .disabled(model.isPlaying)
        .task(id: profile.uuid) { load(profile) }
        .onChange(of: settings) { old, new in
            guard loadedFor == profile.uuid, old != new else { return }
            var new = new
            new.clampScale()
            if new != settings { settings = new; return }
            save(profile)
        }
    }

    /// "2× (640 × 480)", "Stretch"
    private func scaleTitle(_ scale: Int) -> String {
        if scale == 0 { return "Stretch" }
        let width = settings.widescreen ? 426 : 320
        return settings.fullscreen ? "\(scale)×" : "\(scale)× (\(width * scale) × \(240 * scale))"
    }

    private func load(_ profile: Profile) {
        loadedFor = nil
        settings = GameSettings.read(from: GameRunner.saveFolder(for: profile))
        languages = GameLanguages.list(in: profile.folder)
        if !languages.isEmpty, !languages.contains(where: { $0.index == settings.language }) { settings.language = 0 }
        loadedFor = profile.uuid
    }

    private func save(_ profile: Profile) {
        do {
            try settings.write(to: GameRunner.saveFolder(for: profile))
            profile.controllerLayoutSet = true
            saveError = nil
        } catch {
            saveError = "Unable to save the game settings: \(error.localizedDescription)"
        }
    }
}

/// Names of the connected game controllers, kept current as they connect and disconnect.
@Observable
final class ControllerMonitor {
    private(set) var names: [String] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    private func refresh() {
        names = GCController.controllers().map { $0.vendorName ?? "Controller" }
    }
}
