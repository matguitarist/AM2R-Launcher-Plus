import AM2RLauncherPlusKit
import AppKit
import LogKitUI
import SwiftUI

/// What the Log page shows.
enum DebugLogSource: String, CaseIterable, Identifiable {
    case launcher, game
    var id: String { rawValue }
    var title: String { self == .launcher ? "Launcher" : "Game" }

    /// Debug lines start hidden, in both logs.
    static let startLevels: Set<LogLevel> = Set(LogLevel.allCases).subtracting([.trace, .debug])
}

/// The Log page (⌥⌘L): the launcher's events or the current profile's newest game log, live,
/// in LogKit's viewer (level filters that double as counts, sources, search, Follow, Clear, Share).
struct DebugLogPage: View {
    @Environment(AppModel.self) private var model
    /// The game log shown: the current profile's newest. A new run starts a new file, and the viewer moves to it.
    @State private var game: (key: String, viewer: LogViewerModel)?

    private var source: DebugLogSource { model.debugLogSource }

    var body: some View {
        Group {
            switch source {
            case .launcher:
                LogViewer(model: LauncherLog.shared.viewer, options: launcherOptions)
            case .game:
                if let viewer = game?.viewer {
                    LogViewer(model: viewer, options: gameOptions)
                } else {
                    noGameLog
                }
            }
        }
        .navigationTitle("Log")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Source", selection: Bindable(model).debugLogSource) {
                    ForEach(DebugLogSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Show what the launcher did, or what the game wrote")
            }
        }
        .task(id: model.currentProfile?.uuid) { await followNewestGameLog() }
        .noInitialFocus()
    }

    private var subtitle: String {
        switch source {
        case .launcher: "launcher.log"
        case .game: [model.currentProfile?.name, game?.viewer.fileURL?.lastPathComponent].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Launcher

    private var launcherOptions: LogViewerOptions {
        LogViewerOptions(
            emptyTitle: String(localized: "No Launcher Events"),
            emptyMessage: String(localized: "Installs, updates, games and errors show here as they happen."),
            shareActions: [
                .init(String(localized: "Copy launcher.log")) { _ in
                    LauncherLog.shared.flush()
                    if let text = try? String(contentsOf: LauncherLog.file, encoding: .utf8) { Self.copy(text) }
                },
                .init(String(localized: "Show launcher.log in Finder")) { _ in
                    NSWorkspace.shared.activateFileViewerSelecting([LauncherLog.file])
                },
            ],
            sourceColor: { _ in .accentColor }
        )
    }

    // MARK: Game

    private var gameOptions: LogViewerOptions {
        LogViewerOptions(emptyTitle: String(localized: "No Game Log"), emptyMessage: noGameMessage,
                         sourceColor: { $0 == "Game" ? .secondary : .indigo })
    }

    private var noGameMessage: String {
        guard let profile = model.currentProfile else { return String(localized: "Install a profile first.") }
        return String(localized: "Play \(profile.name); what it writes shows here, live.")
    }

    private var noGameLog: some View {
        ContentUnavailableView("No Game Log", systemImage: "gamecontroller", description: Text(noGameMessage))
    }

    /// Looks for a newer game log every second while the page is open, for the current profile.
    private func followNewestGameLog() async {
        game = nil
        while !Task.isCancelled {
            if let profile = model.currentProfile {
                let folder = GameRunner.logFolder(for: profile)
                let newest = LogFiles.sessions(in: folder, extensions: ["log"]).first
                let key = "\(profile.uuid)-\(newest?.path ?? "")"
                if let newest, key != game?.key {
                    // Someone reading an earlier run (Log File menu) stays on it; otherwise follow the new run.
                    let previous = game?.viewer
                    if previous == nil || previous?.fileURL == previous?.fileSource?.files.first?.url {
                        let viewer = LogViewerModel(file: LogFileSource(
                            files: [.init(String(localized: "Newest Game Log"), url: newest)],
                            folder: folder, parser: DebugLog.gameParser, maxBytes: 2 << 20))
                        viewer.filter = previous?.filter ?? LogFilter(levels: DebugLogSource.startLevels)
                        viewer.defaultFilter = LogFilter(levels: DebugLogSource.startLevels)
                        game = (key, viewer)
                    }
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
