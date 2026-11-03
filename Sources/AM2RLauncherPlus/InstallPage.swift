import SwiftUI

/// Install progress (S-002 to S-004): download, patch, copy, with Cancel and Try Again.
struct InstallPage: View {
    @Environment(AppModel.self) private var model
    let state: InstallState

    var body: some View {
        VStack(spacing: Space.xxl) {
            Text(state.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(state.steps, id: \.self) { step in
                    row(step)
                }
            }
            .frame(width: 440, alignment: .leading)
            .padding(Space.xxl)
            .cardBackground()
            .gridArea("install-steps", inset: Space.xxl)
            footer
        }
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ step: InstallState.Step) -> some View {
        let status = status(of: step)
        return HStack(alignment: .top, spacing: Space.md) {
            Group {
                switch status {
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                case .active: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            // One body line tall, so a spinner doesn't make its row taller than a check mark.
            .frame(width: Space.xl, height: Space.lg)
            .gridProbe("icon-\(step)", area: "install-steps", edge: nil)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(step.title(mod: state.modZip != nil))
                    .foregroundStyle(status == .pending ? .secondary : .primary)
                if step == .download, status == .active, state.bytesTotal > 0 {
                    ProgressView(value: Double(state.bytesDone), total: Double(state.bytesTotal))
                    Text("\(megabytes(state.bytesDone)) of \(megabytes(state.bytesTotal))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if status == .failed, let failure = state.failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .gridProbe("step-\(step)", area: "install-steps")
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.spoken)
    }

    @ViewBuilder private var footer: some View {
        if state.finishedName != nil {
            EmptyView()
        } else if state.failure != nil {
            HStack(spacing: Space.md) {
                Button("Cancel") { model.cancelInstall() }
                    .keyboardShortcut(.cancelAction)
                if state.importFolder != nil {
                    Button("Choose Another Folder…") { model.install = nil; model.chooseRandovaniaGame() }
                } else if state.modZip != nil {
                    Button("Choose Another Mod…") { model.install = nil; model.showModChooser = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Try Again") { let updating = state.updating; model.install = nil; model.startInstall(updating: updating) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        } else {
            Button("Cancel") { model.cancelInstall() }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
        }
    }

    private enum Status: Equatable {
        case pending, active, done, failed
        var spoken: String {
            switch self {
            case .pending: "Waiting"
            case .active: "In progress"
            case .done: "Done"
            case .failed: "Failed"
            }
        }
    }

    private func status(of step: InstallState.Step) -> Status {
        if state.finishedName != nil || step < state.step { return .done }
        if step > state.step { return .pending }
        return state.failure == nil ? .active : .failed
    }

    private func megabytes(_ bytes: Int) -> String {
        bytes.formatted(.byteCount(style: .file).locale(.app))
    }
}
