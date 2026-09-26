import HeadroomCore
import SwiftUI

/// Everything Headroom moved to the Trash, with a Restore button per item.
struct TrashView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let records = model.records
        Group {
            if records.isEmpty {
                ContentUnavailableView("Nothing moved yet", systemImage: "trash",
                                       description: Text("Items Headroom moves to the Trash show up here so you can put them back."))
            } else {
                List {
                    Section {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.title).fontWeight(.medium)
                                        Text(record.original.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .font(.callout.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(record.bytes.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 180, alignment: .trailing)
                                    Button("Restore") { model.restore(record) }.controlSize(.small)
                                }
                                if let error = model.restoreErrors[record.id] {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                        .font(.callout)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    } header: {
                        Text("\(records.count) items · \(records.reduce(0) { $0 + $1.bytes }.formattedBytes) still in the Trash")
                            .monospacedDigit()
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { model.pruneTrash() }
    }
}
