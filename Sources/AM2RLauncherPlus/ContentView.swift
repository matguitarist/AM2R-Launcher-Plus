import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch model.sidebar ?? .play {
            case .play: PlayPage()
            case .profiles: ProfilesPage()
            }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            // S-020: at most daily; snapshot and self-test runs stay offline.
            if !SelfTest.requested && (ProcessInfo.processInfo.environment["APP_SNAPSHOT"] ?? "").isEmpty {
                await model.checkForUpdates()
            }
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

/// The selected profile, or the most recently installed one.
private struct CurrentProfile {
    static func pick(_ profiles: [Profile], selection: PersistentIdentifier?) -> Profile? {
        profiles.first { $0.id == selection } ?? profiles.first
    }
}

struct PlayPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Profile.installedAt, order: .reverse) private var profiles: [Profile]

    var body: some View {
        Group {
            if let install = model.install {
                InstallPage(state: install)
            } else if !model.forceWelcome, let profile = CurrentProfile.pick(profiles, selection: model.selection) {
                VStack(spacing: 0) {
                    hero(profile)
                        .padding(.top, Space.section)
                        .padding(.bottom, Space.lg)
                    GameSettingsView(profile: profile)
                        .frame(maxWidth: 600)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                WelcomePage()
            }
        }
        .navigationTitle("Play")
        .sheet(item: Bindable(model).logSheet) { item in
            LogSheet(item: item)
        }
    }
}

/// "Community Updates 1.5.6 is available" (S-020).
struct UpdateBanner: View {
    let title: String

    var body: some View {
        HStack(spacing: Space.lg) {
            Label(title, systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Palette.accentText)
                .gridProbe("update-message", area: "update-banner")
            Spacer(minLength: Space.lg)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(width: 480)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
        .gridArea("update-banner", inset: Space.md)
        .accessibilityElement(children: .contain)
    }
}

/// "AM2R stopped unexpectedly." with Show Log and Play Again (S-006).
struct FailureBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.lg) {
            Label("AM2R stopped unexpectedly.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .gridProbe("failure-message", area: "failure-banner")
            Spacer(minLength: Space.lg)
            Button("Show Log") { model.showLog() }
                .help("Read what the game wrote before it stopped (⌘L)")
            Button("Play Again") { model.play() }
                .help("Start AM2R again (⌘P)")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(width: 480)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
        .gridArea("failure-banner", inset: Space.md)
        .accessibilityElement(children: .contain)
    }
}

extension PlayPage {
    /// Name, version and engine, Play, then last played and any problem.
    func hero(_ profile: Profile) -> some View {
        VStack(spacing: Space.lg) {
            Text(profile.name)
                .font(.largeTitle.bold())
            HStack(spacing: Space.sm) {
                Text("Version \(profile.version)")
                Text("·")
                Label(profile.engine.title, systemImage: "cpu")
                    .help(profile.engine.help)
            }
            .foregroundStyle(.secondary)
            playControls
            if let summary = PlayStats.summary(lastPlayed: profile.lastPlayedAt, playTime: profile.playTime) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let update = model.availableUpdate(for: profile) {
                UpdateBanner(title: update)
            } else if let message = model.updateCheckMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failure = model.lastGameFailure, failure.profile == profile.uuid, !model.isPlaying {
                FailureBanner()
            }
            if let error = model.playError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder var playControls: some View {
        @Bindable var model = model
        if model.isPlaying {
            HStack(spacing: Space.md) {
                Button("Playing…", systemImage: "gamecontroller.fill") {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .disabled(true)
                Button("Stop") { model.confirmStop = true }
                    .controlSize(.extraLarge)
                    .help("Stop the game (⌘.)")
            }
            .confirmationDialog("Stop AM2R?", isPresented: $model.confirmStop) {
                Button("Stop", role: .destructive) { model.stopGame() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Unsaved progress will be lost.")
            }
        } else {
            Button("Play", systemImage: "play.fill") { model.play() }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .help("Start AM2R (⌘P)")
        }
    }
}

/// "Last played 1 hour ago · 2 h 14 min total"
enum PlayStats {
    static func summary(lastPlayed: Date?, playTime: Double) -> String? {
        guard let lastPlayed else { return nil }
        let ago = lastPlayed.formatted(.relative(presentation: .named).locale(.app))
        let total = Duration.seconds(playTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(.app))
        return "Last played \(ago) · \(total) total"
    }
}

struct ProfilesPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Profile.installedAt, order: .reverse) private var profiles: [Profile]

    var body: some View {
        @Bindable var model = model
        List(profiles, selection: $model.selection) { profile in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(profile.name)
                Text("\(profile.version) · \(profile.engine.title)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .tag(profile.id)
        }
        .overlay {
            if profiles.isEmpty {
                ContentUnavailableView("No Profiles", systemImage: SidebarItem.profiles.symbol,
                                       description: Text("Install Community Updates from the Play page."))
            }
        }
        .navigationTitle("Profiles")
    }
}

extension Locale {
    /// The language the app's text is in, so numbers and dates match the words around them.
    /// Becomes the person's language once the launcher is localized (S-030 and later).
    static var app: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
}
