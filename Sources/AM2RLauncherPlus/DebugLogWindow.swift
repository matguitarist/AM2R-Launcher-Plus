import AM2RLauncherPlusKit
import AppKit
import LogKitUI
import SwiftUI

/// What the Log page shows.
enum DebugLogSource: String, CaseIterable, Identifiable {
    case launcher, game, rooms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: "Launcher"
        case .game: "Game"
        case .rooms: "Rooms"
        }
    }

    /// Debug lines start hidden, in both logs.
    static let startLevels: Set<LogLevel> = Set(LogLevel.allCases).subtracting([.trace, .debug])
}

/// The Log page (⌥⌘L): the launcher's events or the current profile's newest game log, live,
/// in LogKit's viewer (level filters that double as counts, sources, search, Follow, Clear, Share).
struct DebugLogPage: View {
    @Environment(AppModel.self) private var model
    /// The game log shown: the current profile's newest. A new run starts a new file, and the viewer moves to it.
    @State private var game: (key: String, viewer: LogViewerModel)?
    /// The current profile's am2r_log.txt (S-043), and whether its config.ini has WriteLog on.
    @State private var rooms: (profile: UUID, viewer: LogViewerModel)?
    @State private var roomLogOn = false
    @State private var roomLogError: String?

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
            case .rooms:
                if let viewer = rooms?.viewer, roomLogOn {
                    LogViewer(model: viewer, options: roomOptions)
                } else {
                    roomLogOff
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
                .help("Show what the launcher did, what the game wrote, or the rooms you went through")
            }
        }
        .task(id: model.currentProfile?.uuid) { await followNewestGameLog() }
        .task(id: "\(model.currentProfile?.uuid.uuidString ?? "")-\(source.rawValue)") { if source == .rooms { loadRoomLog() } }
        .noInitialFocus()
    }

    private var subtitle: String {
        switch source {
        case .launcher: "launcher.log"
        case .game: [model.currentProfile?.name, game?.viewer.fileURL?.lastPathComponent].compactMap { $0 }.joined(separator: " · ")
        case .rooms: [model.currentProfile?.name, "am2r_log.txt"].compactMap { $0 }.joined(separator: " · ")
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

    // MARK: Rooms

    private var roomOptions: LogViewerOptions {
        LogViewerOptions(
            emptyTitle: String(localized: "No Rooms Yet"),
            emptyMessage: model.currentProfile.map { String(localized: "Play \($0.name); each room you enter shows here.") } ?? "",
            shareActions: [
                .init(String(localized: "Show am2r_log.txt in Finder")) { _ in
                    guard let profile = model.currentProfile else { return }
                    let file = RoomLog.file(in: GameRunner.saveFolder(for: profile))
                    if FileManager.default.fileExists(atPath: file.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([file])
                    } else {
                        NSWorkspace.shared.open(GameRunner.saveFolder(for: profile))
                    }
                },
                .init(String(localized: "Turn Off Room Log")) { _ in setRoomLog(false) },
            ],
            sourceColor: { $0 == "Rooms" ? .accentColor : $0 == "Map" ? .teal : .secondary }
        )
    }

    /// Off: what the room log is, and the switch. The game reads WriteLog when it starts.
    private var roomLogOff: some View {
        ContentUnavailableView {
            Label("Room Log Is Off", systemImage: "map")
        } description: {
            Text(model.currentProfile == nil
                 ? "Install a profile first."
                 : "The game can list each room you enter, with the time. Turn it on, then play. Useful to tell where a problem happened.")
            if let roomLogError { Text(roomLogError).foregroundStyle(.red) }
        } actions: {
            if model.currentProfile != nil {
                Button("Turn On Room Log") { setRoomLog(true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPlaying)
                    .help(model.isPlaying ? "Quit the game first; it rewrites its settings when it closes" : "Sets WriteLog in the profile's config.ini")
            }
        }
    }

    private func loadRoomLog() {
        rooms = nil
        roomLogError = nil
        guard let profile = model.currentProfile else { roomLogOn = false; return }
        let saves = GameRunner.saveFolder(for: profile)
        roomLogOn = RoomLog.isOn(saves: saves)
        let names = GameData.roomNames(of: profile.folder.appending(path: "game.ios"))
        let viewer = LogViewerModel(file: LogFileSource(
            files: [.init(String(localized: "Room Log"), url: RoomLog.file(in: saves))],
            parser: RoomLog.parser(roomNames: names), maxBytes: 2 << 20))
        viewer.filter = LogFilter(levels: DebugLogSource.startLevels)
        viewer.defaultFilter = LogFilter(levels: DebugLogSource.startLevels)
        rooms = (profile.uuid, viewer)
    }

    private func setRoomLog(_ on: Bool) {
        guard let profile = model.currentProfile else { return }
        do {
            try RoomLog.set(on, saves: GameRunner.saveFolder(for: profile))
            roomLogOn = on
            roomLogError = nil
            log(.info, "Log", "\(profile.name): room log \(on ? "on" : "off")")
        } catch {
            roomLogError = String(localized: "Unable to change config.ini: \(error.localizedDescription)")
            log(.error, "Log", "Room log of \(profile.name): \(error)")
        }
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
