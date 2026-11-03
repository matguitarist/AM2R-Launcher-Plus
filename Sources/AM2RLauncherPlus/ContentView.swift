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
            if let profile = CurrentProfile.pick(profiles, selection: model.selection) {
                VStack(spacing: Space.lg) {
                    Text(profile.name)
                        .font(.largeTitle.bold())
                    HStack(spacing: Space.sm) {
                        Text("Version \(profile.version)")
                        Text(profile.engine.title)
                            .help(profile.engine.help)
                    }
                    .foregroundStyle(.secondary)
                    // Play arrives with S-005.
                    Button("Play", systemImage: "play.fill") {}
                        .buttonStyle(.borderedProminent)
                        .controlSize(.extraLarge)
                        .disabled(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The welcome page arrives with S-001.
                ContentUnavailableView(
                    "Install AM2R on this Mac",
                    systemImage: "gamecontroller",
                    description: Text("You'll need your AM2R 1.1 copy (AM2R_11.zip).")
                )
            }
        }
        .navigationTitle("Play")
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
