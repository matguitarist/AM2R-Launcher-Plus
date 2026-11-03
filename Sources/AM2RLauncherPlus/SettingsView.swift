import AM2RLauncherPlusKit
import AppKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var choosing = false
    @State private var size: Int64?

    var body: some View {
        Section {
            LabeledContent("Location") {
                Text(DataFolder.url.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(DataFolder.url.path(percentEncoded: false))
            }
            LabeledContent("Size", value: size.map { $0.formatted(.byteCount(style: .file).locale(.app)) } ?? "Calculating…")
            if let move = model.dataMove {
                ProgressView(value: Double(move.done), total: Double(max(move.total, 1))) {
                    Text("Moving the data folder…")
                }
            }
            if DataFolder.isMissing {
                Label("The disk with the data folder isn't connected. Connect it, then reopen the app.", systemImage: "externaldrive.badge.exclamationmark")
                    .symbolRenderingMode(.multicolor)
            }
            if let error = model.dataMoveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            HStack {
                Spacer()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([DataFolder.url]) }
                    .help("Show the data folder in Finder")
                Button("Move…") { choosing = true }
                    .help("Move profiles, saves and patch data to another folder, such as an external drive")
                    .disabled(model.isPlaying || model.install != nil || model.dataMove != nil)
            }
        } header: {
            Text("Data Folder")
        } footer: {
            Text(model.isPlaying ? "Quit AM2R to move the data folder." : "Profiles, saves, logs and patch data. Moving copies them, checks the copy, then deletes the old folder.")
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            guard case .success(let parent) = result else { return }
            Task {
                await model.moveDataFolder(into: parent)
                await measure()
            }
        }
        .task { await measure() }
        Section("Engine") {
            if let version = EngineInfo.version {
                LabeledContent("Native", value: "Butterscotch \(version.prefix(7))")
                    .textSelection(.enabled)
                LabeledContent("Source") {
                    Link("Source Code (AGPL-3.0)", destination: URL(string: "https://github.com/ButterscotchRunner/Butterscotch/tree/\(version)")!)
                        .help("Open the engine's source on GitHub. Our patch ships inside the app.")
                }
                LabeledContent("Patches") {
                    Button("Show in Finder") { EngineInfo.revealFiles() }
                        .help("Show the engine's license and the AM2R patch bundled with this app")
                }
            } else {
                Text("Native engine not found. Use Rosetta, or reinstall the app.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension GeneralSettings {
    func measure() async {
        let folder = DataFolder.url
        size = await Task.detached(priority: .utility) { FolderMove.size(of: folder) }.value
    }
}

/// The bundled engine (S-007): Contents/Resources/Engine holds its license, VERSION and our patch.
enum EngineInfo {
    static var folder: URL { Bundle.main.bundleURL.appending(path: "Contents/Resources/Engine", directoryHint: .isDirectory) }

    /// The upstream Butterscotch commit, from VERSION ("<commit> <patch hash>").
    static var version: String? {
        guard GameRunner.engine != nil, let text = try? String(contentsOf: folder.appending(path: "VERSION"), encoding: .utf8) else { return nil }
        return text.split(separator: " ").first.map(String.init)
    }

    static func revealFiles() {
        NSWorkspace.shared.activateFileViewerSelecting([folder.appending(path: "butterscotch-am2r.patch")])
    }
}
