import SaveMySpaceCore
import SwiftUI

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { model.selection.contains(finding.path) },
                set: { _ in model.toggle(finding) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!finding.actionable)
            .help(finding.actionable ? tr("Select to move to the Trash", "Seleziona per spostare nel Cestino")
                                       : tr("Handle manually", "Da gestire a mano"))

            Text(SizeFormatter.string(finding.size))
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    RiskBadge(risk: finding.risk)
                    Text(model.displayPath(finding.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Text(finding.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let hint = finding.hint {
                    Label(hint, systemImage: finding.actionable ? "lightbulb" : "hand.raised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            Button {
                model.revealInFinder(finding)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(tr("Show in Finder", "Mostra nel Finder"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(tr("Show in Finder", "Mostra nel Finder")) { model.revealInFinder(finding) }
            Button(tr("Copy path", "Copia percorso")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finding.path, forType: .string)
            }
        }
    }
}

struct RiskBadge: View {
    let risk: Risk

    private var color: Color {
        switch risk {
        case .safe: return .green
        case .review: return .orange
        case .caution: return .red
        }
    }

    var body: some View {
        Text(risk.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
