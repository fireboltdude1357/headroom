import HeadroomCore
import SwiftUI

/// Disk bar, trend line, "Worth a look" and the category grid.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let scan = model.scan {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DiskSection(scan: scan)
                    if !scan.unreadable.isEmpty {
                        AccessNotice(unreadable: scan.unreadable, needsFullDiskAccess: !scan.hasFullDiskAccess)
                    }
                    if !model.insights.isEmpty { InsightsSection(insights: model.insights) }
                    GridSection(scan: scan)
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }
}

private struct DiskSection: View {
    @Environment(AppModel.self) private var model
    var scan: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(scan.volume.freeBytes.formattedBytes) free")
                    .font(.title2.weight(.semibold))
                Text("of \(scan.volume.totalBytes.formattedBytes)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Scanned " + scan.date.formatted(.relative(presentation: .named)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()

            UsageBar(volume: scan.volume).frame(height: 14)

            HStack(spacing: 16) {
                Label("\(scan.volume.usedBytes.formattedBytes) used", systemImage: "circle.fill")
                    .foregroundStyle(barColor)
                Label("\(model.scan?.totalBytes.formattedBytes ?? "") found by Headroom", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout)
            .monospacedDigit()

            VStack(alignment: .leading, spacing: 4) {
                if let change = model.freeChange, let previous = model.previousSnapshot {
                    Label(freeChangePhrase(change, since: previous.date),
                          systemImage: change < 0 ? "arrow.down.right" : "arrow.up.right")
                }
                switch model.trend {
                case let .full(date):
                    Label("At this rate, your disk is full \(fillPhrase(date)).", systemImage: "chart.line.downtrend.xyaxis")
                case .notShrinking:
                    Label("Free space isn't shrinking.", systemImage: "chart.line.flattrend.xyaxis")
                case .notEnoughHistory:
                    Label("Scan again in a day or two to see where free space is heading.", systemImage: "clock")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var barColor: Color { UsageBar.color(for: scan.volume) }
}

private struct AccessNotice: View {
    var unreadable: [URL]
    var needsFullDiskAccess: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Some folders couldn't be read", systemImage: "lock")
                .font(.headline)
            Text(needsFullDiskAccess
                 ? "macOS asks separately for each of these, so Headroom skips them. Turn on Full Disk Access once to include them all."
                 : "Some folders couldn't be read, so their sizes are lower bounds.")
                .foregroundStyle(.secondary)
            ForEach(unreadable.prefix(6), id: \.self) { url in
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            if unreadable.count > 6 {
                Text("and \(unreadable.count - 6) more").font(.callout).foregroundStyle(.secondary)
            }
            if needsFullDiskAccess {
                Button("Open Full Disk Access settings") { FullDiskAccess.openSettings() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InsightsSection: View {
    @Environment(AppModel.self) private var model
    var insights: [Insight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worth a look").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                    HStack {
                        Text(insight.message)
                        Spacer()
                        Button(insight.action.buttonTitle) { model.perform(insight.action) }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    if index < insights.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// Every square is 250 MB, colored by category. Drawn once; nothing animates.
private struct GridSection: View {
    var scan: ScanResult
    private let squareBytes: Int64 = 250_000_000
    private let cell: CGFloat = 9
    private let gap: CGFloat = 2

    private var slices: [(FindingCategory, Int64)] {
        FindingCategory.allCases.compactMap { category in
            let bytes = scan.findings(in: category).reduce(0) { $0 + $1.bytes }
            return bytes > 0 ? (category, bytes) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("What Headroom found").font(.headline)
                Text("Each square is 250 MB").font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(slices, id: \.0) { category, bytes in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(category.color).frame(width: 9, height: 9)
                        Text(category.label)
                        Text(bytes.formattedBytes).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .font(.callout)
            GeometryReader { proxy in
                let columns = max(1, Int((proxy.size.width + gap) / (cell + gap)))
                Canvas { context, _ in
                    var index = 0
                    for (category, bytes) in slices {
                        let count = Int((Double(bytes) / Double(squareBytes)).rounded(.up))
                        for _ in 0..<count {
                            let x = CGFloat(index % columns) * (cell + gap)
                            let y = CGFloat(index / columns) * (cell + gap)
                            context.fill(Path(roundedRect: CGRect(x: x, y: y, width: cell, height: cell), cornerRadius: 1.5),
                                         with: .color(category.color))
                            index += 1
                        }
                    }
                }
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { width = proxy.size.width }
            }
            .frame(height: gridHeight)
        }
    }

    /// Measured width of the grid, so the height matches the number of rows it really needs.
    @State private var width: CGFloat = 800

    private var gridHeight: CGFloat {
        let columns = max(1, Int((width + gap) / (cell + gap)))
        let squares = slices.reduce(0) { $0 + Int((Double($1.1) / Double(squareBytes)).rounded(.up)) }
        let rows = (squares + columns - 1) / columns
        return CGFloat(rows) * (cell + gap)
    }
}

/// Full Disk Access is the one permission Headroom asks for. It replaces macOS's separate prompts
/// for Desktop, Documents, Downloads, iCloud Drive, Photos and other apps' data.
enum FullDiskAccess {
    static var isGranted: Bool { Scanner.hasFullDiskAccess(home: FileManager.default.homeDirectoryForCurrentUser) }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
