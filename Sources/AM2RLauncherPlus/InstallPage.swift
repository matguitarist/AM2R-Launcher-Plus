import SwiftUI

/// Install progress (S-002 to S-004): download, patch, copy, with Cancel and Try Again.
struct InstallPage: View {
    @Environment(AppModel.self) private var model
    let state: InstallState

    var body: some View {
        VStack(spacing: Space.xxl) {
            Text(state.finishedName.map { "\($0) is ready" } ?? "Installing Community Updates")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(InstallState.Step.allCases, id: \.self) { step in
                    row(step)
                }
            }
            .frame(width: 440)
            .padding(Space.xxl)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 16))
            footer
        }
        .padding(Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ step: InstallState.Step) -> some View {
        let status = status(of: step)
        return HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Group {
                switch status {
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                case .active: ProgressView().controlSize(.small)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(step.title)
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
                Button("Try Again") { model.install = nil; model.startInstall() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
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
        bytes.formatted(.byteCount(style: .file))
    }
}
