import HeadroomCore
import SwiftUI

/// The list of findings for one sidebar category.
struct CategoryView: View {
    @Environment(AppModel.self) private var model
    var category: FindingCategory

    var body: some View {
        let findings = model.findings(in: category)
        let largest = findings.first?.bytes ?? 1
        List {
            Section {
                ForEach(findings) { finding in
                    FindingRow(finding: finding, fraction: Double(finding.bytes) / Double(largest))
                }
            } header: {
                HStack {
                    Text("\(findings.count) items · \(findings.reduce(0) { $0 + $1.bytes }.formattedBytes)")
                        .monospacedDigit()
                    Spacer()
                    if category == .projects, findings.contains(where: \.isUntouched) {
                        Button("Select untouched") { model.selectUntouchedProjects() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

/// One finding: checkbox, title, size bar and an expandable explanation.
struct FindingRow: View {
    @Environment(AppModel.self) private var model
    var finding: Finding
    var fraction: Double

    private var isExpanded: Bool { model.expanded.contains(finding.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                checkbox.frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.title).fontWeight(.medium)
                        Tag(text: finding.consequence.shortLabel, color: finding.consequence.color)
                        if finding.isUntouched { Tag(text: "Untouched", color: .orange) }
                    }
                    HStack(spacing: 0) {
                        Text(finding.owner)
                        if let detail = finding.detail { Text(" · \(detail)") }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(finding.bytes.formattedBytes).monospacedDigit()
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(finding.category.color.opacity(0.8)).frame(width: max(2, 90 * fraction))
                    }
                    .frame(width: 90, height: 4)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(finding.explanation)
                    if let warning = finding.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let hint = finding.settingsHint {
                        Label(hint, systemImage: "gearshape")
                    }
                    Text(finding.paths.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                        .joined(separator: "\n"))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .textSelection(.enabled)
                .padding(.leading, 28)
                .padding(.trailing, 32)
                .padding(.bottom, 8)
            }
        }
    }

    /// App-managed items can't be selected, so the checkbox slot points at the app's own setting.
    @ViewBuilder private var checkbox: some View {
        if finding.consequence.isSelectable {
            Toggle("", isOn: Binding(get: { model.selected.contains(finding.id) }, set: { _ in model.toggle(finding) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
        } else {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .help(finding.settingsHint ?? "Managed by \(finding.owner)")
        }
    }

    private func toggleExpanded() {
        if isExpanded { model.expanded.remove(finding.id) } else { model.expanded.insert(finding.id) }
    }
}
