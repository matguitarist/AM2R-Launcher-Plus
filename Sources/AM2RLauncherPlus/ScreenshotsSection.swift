import AM2RLauncherPlusKit
import AppKit
import SwiftUI

/// Extras page > Screenshots (S-041): the game saves one with F12 into the profile's save folder
/// (snap/snap NNNN.png); here are the newest, a click opens one, and the folder opens in Finder.
struct ScreenshotsSection: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var shots: [URL] = []

    static let shown = 4
    static let thumbnail = CGSize(width: 128, height: 96)

    var body: some View {
        Section {
            if shots.isEmpty {
                Text("Press F12 while playing to save a screenshot.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Space.md) {
                    ForEach(shots.prefix(Self.shown), id: \.self) { shot in
                        Button { NSWorkspace.shared.open(shot) } label: { thumbnail(shot) }
                            .buttonStyle(.plain)
                            .help("Open \(shot.lastPathComponent)")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
            }
            LabeledContent {
                Button("Show in Finder") { showInFinder() }
                    .help("Open the profile's screenshot folder")
            } label: {
                Text(shots.isEmpty ? "No screenshots yet" : shots.count == 1 ? "1 screenshot" : "\(shots.count) screenshots")
                Text("Saved at the game's size, 320 × 240")
            }
        } header: {
            Text("Screenshots")
        }
        .task(id: LoadKey(profile: profile.uuid, playing: model.isPlaying)) {
            shots = Screenshots.list(in: GameRunner.saveFolder(for: profile))
        }
    }

    /// Sharp pixels, like the game: no smoothing when the 320 × 240 shot is drawn smaller.
    private func thumbnail(_ shot: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: shot) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    private func showInFinder() {
        let folder = Screenshots.folder(in: GameRunner.saveFolder(for: profile))
        // The game makes the folder on its first F12; make it now so Finder has something to open.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
