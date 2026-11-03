import AM2RLauncherPlusKit
import SwiftData
import SwiftUI

/// The installed mods, how to add one, and the community's mod list (S-033).
struct ModsPage: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Profile> { $0.isMod }, sort: \Profile.installedAt, order: .reverse) private var mods: [Profile]

    private var canInstall: Bool { model.source != nil && model.install == nil && !model.isPlaying }

    /// The community list's groups, in its own order.
    private var groups: [(name: String, entries: [ModCatalog.Entry])] {
        var order: [String] = []
        var byGroup: [String: [ModCatalog.Entry]] = [:]
        for entry in model.modCatalog ?? [] {
            if byGroup[entry.category] == nil { order.append(entry.category) }
            byGroup[entry.category, default: []].append(entry)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Installed") {
                if mods.isEmpty {
                    Text(model.source == nil
                         ? "Install AM2R first. Mods are built on top of AM2R 1.1."
                         : "No mods yet. Get one below, then choose Install Mod… or drop its zip here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mods) { mod in
                        ModRow(mod: mod)
                            .tag(mod.id)
                    }
                }
            }
            catalog
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            if let mod = mods.first(where: { ids.contains($0.id) }) {
                ProfileActions(profile: mod)
            }
        } primaryAction: { ids in
            if let id = ids.first { model.selection = id; model.sidebar = .play }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let zip = urls.first(where: { $0.pathExtension.lowercased() == "zip" }), canInstall else { return false }
            model.sidebar = .play
            model.startModInstall(zip: zip)
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Link(destination: ModCatalog.page) {
                    Label("Open Mod List", systemImage: "safari")
                }
                .help("Open the community's list of AM2R mods in your browser")
                Button("Install Mod…", systemImage: "plus") { model.showModChooser = true }
                    .disabled(!canInstall)
                    .help(model.source == nil ? "Install AM2R first" : "Install an AM2R mod zip as its own profile (⌥⌘O)")
            }
        }
        .task { await model.loadModCatalog() }
        .navigationTitle("Mods")
    }

    @ViewBuilder private var catalog: some View {
        if model.modCatalog == nil {
            Section("From the Community") {
                if let error = model.modCatalogError {
                    HStack(spacing: Space.md) {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try Again") { Task { await model.loadModCatalog(force: true) } }
                    }
                } else {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        Text("Loading the mod list…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.entries) { entry in
                        CatalogRow(entry: entry)
                    }
                }
            }
        }
    }
}

/// One installed mod: name, version and author, its description, and Play.
private struct ModRow: View {
    @Environment(AppModel.self) private var model
    let mod: Profile

    private var details: String {
        var parts = ["Version \(mod.version)"]
        if !mod.author.isEmpty { parts.append("by \(mod.author)") }
        parts.append(PlayStats.lastPlayed(mod.lastPlayedAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(mod.name)
                    .font(.headline)
                Text(details)
                    .foregroundStyle(.secondary)
                if !mod.notes.isEmpty {
                    Text(mod.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(mod.notes)
                }
            }
            Spacer(minLength: Space.lg)
            Button("Play", systemImage: "play.fill") {
                model.selection = mod.id
                model.sidebar = .play
                model.play()
            }
            .disabled(model.isPlaying || model.install != nil)
            .help("Play \(mod.name)")
        }
        .padding(.vertical, Space.xs)
        // Separators start under the name, not under the trailing button.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityElement(children: .combine)
    }
}

/// One mod from the community list: name, author, what it does, and a link to get it.
private struct CatalogRow: View {
    let entry: ModCatalog.Entry

    var body: some View {
        HStack(alignment: .center, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(entry.name)
                    .font(.headline)
                if !entry.author.isEmpty {
                    Text("by \(entry.author)")
                        .foregroundStyle(.secondary)
                }
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .help(entry.summary)
                }
            }
            Spacer(minLength: Space.lg)
            if let link = entry.link {
                Link(destination: link) {
                    Label("Get", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .help("Open the download page of \(entry.name) in your browser. Then install the zip with Install Mod….")
            }
        }
        .padding(.vertical, Space.xs)
        // Separators start under the name, not under the trailing button.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .selectionDisabled()
        .accessibilityElement(children: .combine)
    }
}
