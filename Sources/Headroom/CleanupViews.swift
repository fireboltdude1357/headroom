import HeadroomCore
import SwiftUI

/// Bottom bar: "4 selected · 12.3 GB · Review cleanup…".
struct SelectionBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text("\(model.selected.count) selected · \(model.selectedBytes.formattedBytes)")
                .monospacedDigit()
            Spacer()
            Button("Clear") { model.selected = [] }
            Button("Review cleanup…") { model.showReview = true }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The plan grouped by consequence, with a "Move to Trash" button.
struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false

    var body: some View {
        let plan = model.plan
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move \(plan.findings.count) items to the Trash?").font(.title3.weight(.semibold))
                Text("\(plan.totalBytes.formattedBytes) comes back when you empty the Trash. Nothing is deleted right away.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(plan.groups, id: \.consequence) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Circle().fill(group.consequence.color).frame(width: 8, height: 8)
                                Text(group.consequence.label).font(.headline)
                                Spacer()
                                Text(group.findings.reduce(0) { $0 + $1.bytes }.formattedBytes)
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            ForEach(group.findings) { finding in
                                HStack {
                                    Text(finding.title)
                                    Text(finding.owner).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(finding.bytes.formattedBytes).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(.leading, 16)
                            }
                        }
                    }
                    if !plan.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(plan.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                            }
                        }
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                if model.isExample {
                    Label("Example data: nothing on this Mac moves", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    isRunning = true
                    Task { await model.runCleanup(); isRunning = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || plan.findings.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }
}

/// What happened: bytes moved, skips with reasons and free space before and after.
struct ResultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var summary: CleanupSummary

    private var skipLines: [String] {
        let counts = Dictionary(grouping: summary.skipped, by: { $0.reason.description })
        return counts.map { reason, items in "\(items.count) skipped because \(reason)" }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: summary.moved.isEmpty ? "xmark.circle" : "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(summary.moved.isEmpty ? Color.secondary : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.bytesMoved.formattedBytes) moved to the Trash")
                        .font(.title3.weight(.semibold))
                    Text("\(summary.moved.count) items")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

            if !skipLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(skipLines, id: \.self) { line in
                        Label(line, systemImage: "minus.circle")
                    }
                }
                .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Free before").foregroundStyle(.secondary)
                    Text(summary.freeBefore.formattedBytes)
                }
                GridRow {
                    Text("Free now").foregroundStyle(.secondary)
                    Text(summary.freeAfter.formattedBytes)
                }
                GridRow {
                    Text("After emptying the Trash").foregroundStyle(.secondary)
                    Text((summary.freeAfter + summary.bytesMoved).formattedBytes)
                }
            }
            .monospacedDigit()

            Text("Items sit in the Trash until you empty it, so the space comes back then. Headroom can put anything back from the Trash tab.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Show Trash") { model.sidebar = .trash; dismiss() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
