import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch model.sidebar ?? .play {
            case .play: PlayPage()
            case .profiles: ProfilesPage()
            case .mods: ModsPage()
            case .log: DebugLogPage()
            }
        }
        .modifier(ProfileDialogs())
        .fileImporter(isPresented: Bindable(model).showModChooser, allowedContentTypes: [.zip]) { result in
            if case .success(let zip) = result { model.sidebar = .play; model.startModInstall(zip: zip) }
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
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
                .listItemTint(Palette.accent)
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
                GameSettingsView(profile: profile) {
                    hero(profile)
                        .padding(.top, Space.lg)
                        .padding(.bottom, Space.sm)
                }
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
    @Environment(AppModel.self) private var model
    let title: String
    let profile: Profile

    var body: some View {
        HStack(spacing: Space.lg) {
            Label(title, systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Palette.accentText)
                .gridProbe("update-message", area: "update-banner")
            Spacer(minLength: Space.lg)
            Button("Update") { model.startInstall(updating: profile.uuid) }
                .disabled(model.isPlaying || model.source == nil)
                .help(model.source == nil
                      ? "Choose AM2R 1.1 first (⌘O): the update patches it again."
                      : "Download the update and patch this profile again. Saves and settings stay (⇧⌘U)")
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(width: 480)
        .cardBackground(Radius.banner)
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
        .cardBackground(Radius.banner)
        .gridArea("failure-banner", inset: Space.md)
        .accessibilityElement(children: .contain)
    }
}

extension PlayPage {
    /// Name, version and engine, Play, then last played and any problem.
    func hero(_ profile: Profile) -> some View {
        VStack(spacing: Space.lg) {
            Text(profile.name)
                .font(.largeTitle)
                .fontWeight(.bold)
            HStack(spacing: Space.sm) {
                Text("Version \(profile.version)")
                Text("·")
                if profile.isMod, !profile.author.isEmpty {
                    Text("by \(profile.author)")
                    Text("·")
                }
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
                UpdateBanner(title: update, profile: profile)
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
    /// "1 hour ago", "Never"
    static func lastPlayed(_ date: Date?) -> String {
        date.map { $0.formatted(.relative(presentation: .named).locale(.app)) } ?? "Never"
    }

    /// "2 hr, 14 min", "—" before the first game
    static func playTime(_ seconds: Double) -> String {
        seconds < 60 ? "—" : Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(.app))
    }

    static func summary(lastPlayed: Date?, playTime: Double) -> String? {
        guard let lastPlayed else { return nil }
        let ago = lastPlayed.formatted(.relative(presentation: .named).locale(.app))
        let total = Duration.seconds(playTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(.app))
        return "Last played \(ago) · \(total) total"
    }
}

/// Every profile with its version, engine and play stats; rename, duplicate, reveal and delete (S-022).
struct ProfilesPage: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Profile.installedAt, order: .reverse) private var profiles: [Profile]

    var body: some View {
        @Bindable var model = model
        Table(profiles, selection: $model.selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Version", value: \.version)
                .width(min: 56, ideal: 64)
            TableColumn("Engine") { Text($0.engine.title).help($0.engine.help) }
                .width(min: 56, ideal: 72)
            TableColumn("Last Played") { Text(PlayStats.lastPlayed($0.lastPlayedAt)) }
                .width(min: 88, ideal: 120)
            TableColumn("Play Time") { Text(PlayStats.playTime($0.playTime)) }
                .width(min: 72, ideal: 96)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if let profile = profiles.first(where: { ids.contains($0.id) }) {
                ProfileActions(profile: profile)
            }
        } primaryAction: { ids in
            if let id = ids.first { model.selection = id; model.sidebar = .play }
        }
        .overlay {
            if profiles.isEmpty {
                ContentUnavailableView("No Profiles", systemImage: SidebarItem.profiles.symbol,
                                       description: Text("Install Community Updates from the Play page."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { notices }
        .dropDestination(for: URL.self) { urls, _ in
            guard let zip = urls.first(where: { $0.pathExtension.lowercased() == "zip" }), model.source != nil,
                  model.install == nil, !model.isPlaying else { return false }
            model.sidebar = .play
            model.startModInstall(zip: zip)
            return true
        }
        .navigationTitle("Profiles")
    }

    /// Where kept saves went, and errors, under the table.
    @ViewBuilder private var notices: some View {
        if let kept = model.keptSaves {
            HStack(spacing: Space.md) {
                Label("The saves of \(kept.name) are in Kept Saves.", systemImage: "tray.full")
                Spacer(minLength: Space.lg)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([kept.folder]) }
                Button("Done") { model.keptSaves = nil }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(.bar)
        } else if let error = model.profileActionError {
            HStack(spacing: Space.md) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer(minLength: Space.lg)
                Button("Done") { model.profileActionError = nil }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(.bar)
        }
    }
}

/// The Profile menu and the Profiles page's context menu share these.
struct ProfileActions: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    var body: some View {
        let busy = model.isPlaying && model.game?.profileID == profile.uuid
        Button("Rename…") { model.renameTarget = profile }
        Button("Duplicate") { model.startDuplicate(profile) }
            .disabled(model.duplicating)
        Button("Show in Finder") { model.reveal(profile) }
        Divider()
        Button("Back Up Saves") { model.startBackup(profile) }
        Button("Saves Backups…") { model.backupsFor = profile }
        Divider()
        Button("Delete…", role: .destructive) { model.deleteTarget = profile }
            .disabled(busy)
    }
}

/// Rename and delete ask here, so the menu bar and the Profiles page share them (S-022).
struct ProfileDialogs: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var newName = ""

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert("Rename Profile", isPresented: Binding(get: { model.renameTarget != nil }, set: { if !$0 { model.renameTarget = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let profile = model.renameTarget { model.rename(profile, to: newName) } }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: model.renameTarget?.uuid) { newName = model.renameTarget?.name ?? "" }
            .sheet(item: $model.backupsFor, onDismiss: { model.backupMessage = nil; model.backupError = nil }) { profile in
                BackupsSheet(profile: profile)
            }
            .confirmationDialog(model.deleteTarget.map { "Delete \($0.name)?" } ?? "",
                                isPresented: Binding(get: { model.deleteTarget != nil }, set: { if !$0 { model.deleteTarget = nil } })) {
                Button("Delete, Keep Saves") { if let profile = model.deleteTarget { model.delete(profile, keepSaves: true) } }
                    .keyboardShortcut(.defaultAction)
                Button("Delete Profile and Saves", role: .destructive) { if let profile = model.deleteTarget { model.delete(profile, keepSaves: false) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The game files are removed. Kept saves go to Kept Saves in the data folder, so you can restore them later.")
            }
    }
}

extension Locale {
    /// The language the app's text is in, so numbers and dates match the words around them.
    /// Becomes the person's language once the launcher is localized (S-030 and later).
    static var app: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
}
