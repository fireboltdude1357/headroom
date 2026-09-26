import HeadroomCore
import SwiftUI

extension FindingCategory {
    /// One system color per category, used by the grid, legend and size bars.
    var color: Color {
        switch self {
        case .developer: .blue
        case .appCaches: .teal
        case .appData: .purple
        case .system: .gray
        case .projects: .orange
        case .devices: .green
        case .downloads: .indigo
        case .leftovers: .brown
        }
    }
}

extension Consequence {
    var color: Color {
        switch self {
        case .rebuilds: .green
        case .redownload: .blue
        case .leftover: .orange
        case .irreplaceable: .red
        case .appManaged: .gray
        }
    }

    /// Short form for the row badge; the full `label` goes in the cleanup plan.
    var shortLabel: String {
        switch self {
        case .rebuilds: "Rebuildable"
        case .redownload: "Redownload"
        case .leftover: "Leftover"
        case .irreplaceable: "Personal data"
        case .appManaged: "App-managed"
        }
    }
}

/// Small tinted capsule, e.g. "Rebuildable" or "Untouched".
struct Tag: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// "in about 3 weeks", or nil when free space isn't shrinking.
func fillPhrase(_ date: Date?) -> String? {
    guard let date else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .numeric
    let relative = formatter.localizedString(for: date, relativeTo: .now)
    return relative.hasPrefix("in ") ? "in about " + relative.dropFirst(3) : relative
}

/// "6.2 GB less than a week ago" style sentence for a free space delta.
func freeChangePhrase(_ change: Int64, since: Date) -> String {
    let ago = RelativeDateTimeFormatter().localizedString(for: since, relativeTo: .now)
    if abs(change) < 100_000_000 { return "About the same free space as \(ago)" }
    return "\(abs(change).formattedBytes) \(change < 0 ? "less" : "more") free than \(ago)"
}

/// Used versus free space. Orange once free space is under 10%.
struct UsageBar: View {
    var volume: VolumeInfo

    static func color(for volume: VolumeInfo) -> Color { volume.freeFraction < 0.10 ? .orange : .accentColor }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Self.color(for: volume)).frame(width: proxy.size.width * (1 - volume.freeFraction))
            }
        }
    }
}
