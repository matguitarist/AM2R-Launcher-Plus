import AM2RLauncherPlusKit
import AppKit
import SwiftUI

/// The save backups of one profile (S-023): back up now, restore one (asks first), restore from a zip.
struct BackupsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var backups: [SaveBackup.Backup] = []
    @State private var selection: URL?
    @State private var confirmRestore: URL?
    @State private var choosingFile = false

    private var playingThis: Bool { model.game?.profileID == profile.uuid }

    var body: some View {
        VStack(spacing: 0) {
            Text("Saves of \(profile.name)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.lg)
                .accessibilityAddTraits(.isHeader)
            Divider()
            List(backups, selection: $selection) { backup in
                HStack(spacing: Space.md) {
                    Label(backup.name, systemImage: "doc.zipper")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: Space.lg)
                    Text(backup.size.formatted(.byteCount(style: .file).locale(.app)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(backup.url)
                .contextMenu {
                    Button("Restore…") { confirmRestore = backup.url }
                        .disabled(playingThis)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                    Divider()
                    Button("Move to Trash") {
                        try? FileManager.default.trashItem(at: backup.url, resultingItemURL: nil)
                        reload()
                    }
                }
            }
            .overlay {
                if backups.isEmpty {
                    ContentUnavailableView("No Backups", systemImage: "archivebox",
                                           description: Text("Back up the saves and settings of this profile to keep a copy you can restore."))
                }
            }
            .frame(width: 560, height: 280)
            if let message = model.backupError ?? model.backupMessage {
                Divider()
                Label(message, systemImage: model.backupError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md)
            }
            Divider()
            HStack(spacing: Space.md) {
                Button("Back Up Now") { Task { await model.backUpSaves(profile); reload() } }
                    .help("Zip the saves and settings of this profile (⌘B)")
                Button("Restore from File…") { choosingFile = true }
                    .help("Restore saves from a zip, such as a backup from another Mac")
                    .disabled(playingThis)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([DataFolder.backups(for: profile.uuid)]) }
                    .disabled(backups.isEmpty)
                Spacer()
                if model.backingUp { ProgressView().controlSize(.small) }
                Button("Restore…") { confirmRestore = selection }
                    .disabled(selection == nil || playingThis)
                    .help(playingThis ? "Quit AM2R to restore saves" : "Replace the saves of this profile with the selected backup")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.backingUp)
            .padding(Space.lg)
        }
        .confirmationDialog("Restore these saves?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button("Restore") {
                if let zip = confirmRestore { Task { await model.restoreSaves(profile, from: zip); reload() } }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current saves and settings of \(profile.name) are replaced. They're backed up first, so you can go back.")
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { confirmRestore = url }
        }
        .onExitCommand { dismiss() }
        .task { reload() }
        .onChange(of: model.backingUp) { if !model.backingUp { reload() } }
        .noInitialFocus()
    }

    private func reload() {
        backups = SaveBackup.list(in: DataFolder.backups(for: profile.uuid))
        if let selection, !backups.contains(where: { $0.url == selection }) { self.selection = nil }
    }
}
