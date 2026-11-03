import AM2RLauncherPlusKit
import SwiftUI
import UniformTypeIdentifiers

/// First run: pick AM2R 1.1 (S-001). Install starts from here (S-002).
struct WelcomePage: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: Space.xxl) {
            VStack(spacing: Space.sm) {
                Text("Install AM2R on This Mac")
                    .font(.largeTitle.bold())
                Text("AM2R Launcher Plus turns your AM2R 1.1 into the latest Community Updates and plays it natively on Apple silicon.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            dropZone
            footer
        }
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $model.showChooser, allowedContentTypes: [.zip, .folder]) { result in
            if case .success(let url) = result { Task { await model.choose(url) } }
        }
    }

    private var dropZone: some View {
        Button { model.showChooser = true } label: {
            VStack(spacing: Space.md) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(symbolStyle)
                    .symbolEffect(.pulse, isActive: isChecking)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(model.source?.path ?? "")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gridProbe("drop-content", area: "drop-zone")
            .padding(Space.xxl)
            .frame(width: 440, height: 200)
            .cardBackground(highlighted: dropTargeted)
            .gridArea("drop-zone", inset: Space.xxl)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(dropTargeted ? Palette.accent : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            }
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(isChecking)
        .accessibilityLabel("Choose AM2R 1.1")
        .accessibilityValue(title)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await model.choose(url) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder private var footer: some View {
        switch model.welcome {
        case .ready:
            VStack(spacing: Space.sm) {
                Button("Install Community Updates") { model.startInstall() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Choose Another…") { model.showChooser = true }
                    .buttonStyle(.link)
            }
        case .failed:
            Button("Choose Another…") { model.showChooser = true }
                .controlSize(.large)
        case .empty, .checking:
            Text("Your copy stays where it is. Nothing is uploaded.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var isChecking: Bool {
        if case .checking = model.welcome { return true }
        return false
    }

    private var symbol: String {
        switch model.welcome {
        case .empty: "arrow.down.doc"
        case .checking: "magnifyingglass"
        case .failed: "exclamationmark.triangle.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    private var symbolStyle: AnyShapeStyle {
        switch model.welcome {
        case .failed: AnyShapeStyle(.orange)
        case .ready: AnyShapeStyle(Palette.accent)
        default: AnyShapeStyle(.secondary)
        }
    }

    private var title: String {
        switch model.welcome {
        case .empty: "Drop AM2R_11.zip or its folder here"
        case .checking: "Checking AM2R 1.1…"
        case .failed(let problem, _): problem.message
        case .ready: "AM2R 1.1 found"
        }
    }

    private var detail: String? {
        switch model.welcome {
        case .empty: "or click to choose it"
        case .checking(let name), .failed(_, let name): name
        case .ready: model.source?.name
        }
    }
}
