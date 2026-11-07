import AM2RLauncherPlusKit
import AppKit
import LogKit
import SwiftUI

/// The game log of one run, in monospace (S-006).
struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: LogSheetItem
    @State private var tail: (text: String, truncated: Bool) = ("", false)

    var body: some View {
        VStack(spacing: 0) {
            Text("Log — \(item.profileName)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.lg)
                .accessibilityAddTraits(.isHeader)
            Divider()
            Group {
                if tail.text.isEmpty {
                    ContentUnavailableView("No Log", systemImage: "doc.text",
                                           description: Text("The game didn't write anything."))
                } else {
                    ScrollView([.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            if tail.truncated {
                                Text("Showing the last lines. Reveal in Finder to see the whole log.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Text(tail.text)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .fixedSize()
                        }
                        .padding(Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottomLeading)
                }
            }
            .frame(width: 720, height: 420)
            Divider()
            HStack(spacing: Space.md) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullText, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy the whole log (⇧⌘C)")
                .disabled(tail.text.isEmpty)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.log])
                }
                .help("Show the log file in Finder")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.lg)
        }
        .onExitCommand { dismiss() }
        .task(id: item.log) { tail = Self.read(item.log) }
        .noInitialFocus()
    }

    /// The end of the log: its last 2 MB, and of those the last 5000 lines.
    nonisolated static func read(_ file: URL, maxLines: Int = 5000) -> (text: String, truncated: Bool) {
        guard var (text, truncated) = try? LogFiles.readTail(of: file, maxBytes: 2 << 20) else { return ("", false) }
        if text.hasSuffix("\n") { text.removeLast() }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxLines {
            text = lines.suffix(maxLines).joined(separator: "\n")
            truncated = true
        }
        return (text, truncated)
    }

    /// Copy takes the whole file, not only the lines on screen.
    private var fullText: String {
        (try? String(contentsOf: item.log, encoding: .utf8)) ?? tail.text
    }
}
