import AM2RLauncherPlusKit
import AppKit
import SwiftUI

extension DebugLog.Level {
    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .debug: "ladybug"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

/// What the Debug Log window shows.
enum DebugLogSource: String, CaseIterable, Identifiable {
    case launcher, game
    var id: String { rawValue }
    var title: String { self == .launcher ? "Launcher" : "Game" }
}

/// Game › Debug Log (⌥⌘L): the launcher's events or the current profile's game output, live,
/// with level filters that double as counts, search, Follow and Clear.
struct DebugLogWindow: View {
    @Environment(AppModel.self) private var model
    @State private var levels: Set<DebugLog.Level> = [.info, .warning, .error]
    @State private var search = ""
    @State private var follow = true
    /// Clear hides entries up to this id, per source, until Show All.
    @State private var cleared: [DebugLogSource: (id: Int, at: Date)] = [:]
    @State private var gameEntries: [DebugLog.Entry] = []
    @State private var gameLog: URL?
    @State private var gameLogDate: Date?

    private var all: [DebugLog.Entry] {
        let entries = source == .launcher ? LauncherLog.shared.entries : gameEntries
        guard let mark = cleared[source] else { return entries }
        return entries.filter { $0.id > mark.id }
    }

    private var source: DebugLogSource { model.debugLogSource }

    var body: some View {
        let all = all
        let shown = DebugLog.filter(all, levels: levels, query: search)
        VStack(spacing: 0) {
            filterBar(all)
            Divider()
            entryList(shown)
                .overlay { emptyState(all: all, shown: shown) }
        }
        .frame(minWidth: 640, minHeight: 320)
        .navigationTitle("Debug Log")
        .navigationSubtitle(subtitle)
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar { toolbar }
        .task(id: "\(source.rawValue)-\(model.currentProfile?.uuid.uuidString ?? "")") { await followGameLog() }
        .noInitialFocus()
    }

    private var subtitle: String {
        switch source {
        case .launcher: "launcher.log"
        case .game: [model.currentProfile?.name, gameLog?.lastPathComponent].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Source", selection: Bindable(model).debugLogSource) {
                ForEach(DebugLogSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Show what the launcher did, or what the game wrote")
        }
        ToolbarItemGroup {
            Toggle(isOn: $follow) { Label("Follow", systemImage: "arrow.down.to.line") }
                .help("Keep the newest lines in view")
            Button("Clear", systemImage: "clear") {
                if let last = (source == .launcher ? LauncherLog.shared.entries : gameEntries).last { cleared[source] = (last.id, .now) }
            }
            .help("Hide the lines so far; new lines still show (⌘K)")
            .keyboardShortcut("k")
            Button("Copy", systemImage: "doc.on.doc") {
                let text = DebugLog.filter(all, levels: levels, query: search).map(Self.text).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .help("Copy the lines shown (⇧⌘C)")
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Show in Finder", systemImage: "folder") {
                let file = source == .launcher ? LauncherLog.file : gameLog
                if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            .help("Show the log file in Finder")
            .disabled(source == .game && gameLog == nil)
        }
    }

    // MARK: Filters

    private func filterBar(_ all: [DebugLog.Entry]) -> some View {
        let counts = Dictionary(grouping: all, by: \.level).mapValues(\.count)
        return HStack(spacing: Space.sm) {
            ForEach(DebugLog.Level.allCases, id: \.self) { level in
                Toggle(isOn: Binding(get: { levels.contains(level) }, set: { on in
                    if on { levels.insert(level) } else { levels.remove(level) }
                })) {
                    Label("\(level.title) \(counts[level, default: 0])", systemImage: level.symbol)
                        .monospacedDigit()
                        .foregroundStyle(levels.contains(level) ? level.color : .secondary)
                }
                .toggleStyle(.button)
                .help(levels.contains(level) ? "Hide \(level.title.lowercased()) lines" : "Show \(level.title.lowercased()) lines")
            }
            Spacer(minLength: Space.lg)
            if let mark = cleared[source] {
                Text("Cleared at \(mark.at.formatted(date: .omitted, time: .standard))")
                    .foregroundStyle(.secondary)
                Button("Show All") { cleared[source] = nil }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
        .background(.bar)
    }

    // MARK: Entries

    private func entryList(_ shown: [DebugLog.Entry]) -> some View {
        ScrollViewReader { proxy in
            List(shown) { entry in
                DebugLogRow(entry: entry)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .textSelection(.enabled)
            .onChange(of: shown.last?.id) { if follow, let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onChange(of: follow) { if follow, let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            .onAppear { if let last = shown.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }

    @ViewBuilder private func emptyState(all: [DebugLog.Entry], shown: [DebugLog.Entry]) -> some View {
        if all.isEmpty {
            switch source {
            case .launcher:
                ContentUnavailableView("No Launcher Events", systemImage: "list.bullet.rectangle",
                                       description: Text("Installs, updates, games and errors show here as they happen."))
            case .game:
                ContentUnavailableView("No Game Log", systemImage: "gamecontroller",
                                       description: Text(model.currentProfile == nil ? "Install a profile first." : "Play \(model.currentProfile?.name ?? "the game"); what it writes shows here, live."))
            }
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: search)
        }
    }

    /// One line for Copy: "14:05:00 WARN [VM] message" or "#12 WARN [VM] message".
    static func text(_ entry: DebugLog.Entry) -> String {
        let when = entry.date.map { $0.formatted(date: .omitted, time: .standard) } ?? "#\(entry.id)"
        return "\(when) \(entry.level.title.uppercased()) [\(entry.source)] \(entry.message)"
    }

    /// Reads the current profile's newest game log while Game is shown, again whenever it changes.
    private func followGameLog() async {
        guard source == .game else { return }
        gameEntries = []
        gameLog = nil
        gameLogDate = nil
        while !Task.isCancelled {
            if let profile = model.currentProfile, let file = LogTail.newest(in: GameRunner.logFolder(for: profile)) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if file != gameLog || date != gameLogDate {
                    let text = await Task.detached(priority: .utility) { LogTail.read(file).text }.value
                    if file != gameLog { cleared[.game] = nil }
                    gameLog = file
                    gameLogDate = date
                    gameEntries = DebugLog.gameEntries(text)
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

struct DebugLogRow: View {
    let entry: DebugLog.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text(entry.date.map { $0.formatted(date: .omitted, time: .standard) } ?? "\(entry.id)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
            Image(systemName: entry.level.symbol)
                .foregroundStyle(entry.level.color)
                .help(entry.level.title)
                .frame(width: 16)
            Text(entry.source)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(entry.level == .info ? .primary : entry.level.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout.monospaced())
        .accessibilityElement(children: .combine)
    }
}

/// Game › Debug Log (⌥⌘L).
struct DebugLogMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Debug Log") { openWindow(id: "debug-log") }
            .keyboardShortcut("l", modifiers: [.command, .option])
    }
}
