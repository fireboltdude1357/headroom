import Foundation

/// What one scan saw, kept so the next scan can say what changed.
public struct Snapshot: Codable, Sendable, Hashable {
    public var date: Date
    public var volume: VolumeInfo
    /// Bytes per finding id.
    public var sizes: [String: Int64]

    public init(date: Date, volume: VolumeInfo, sizes: [String: Int64]) {
        self.date = date
        self.volume = volume
        self.sizes = sizes
    }

    public init(_ scan: ScanResult) {
        self.init(date: scan.date, volume: scan.volume,
                  sizes: Dictionary(scan.findings.map { ($0.id, $0.bytes) }, uniquingKeysWith: +))
    }
}

/// A change since the previous scan that deserves a button in the menu bar panel.
public struct Insight: Identifiable, Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        case review(findingID: String)
        case selectUntouchedProjects
    }

    public var id: String
    public var message: String
    public var bytes: Int64
    public var action: Action
}

public enum Trends {
    /// Fits a line through free space over time and returns when it hits zero,
    /// or nil if free space isn't shrinking. Needs at least a day of history.
    public static func fillDate(_ snapshots: [Snapshot]) -> Date? {
        let points = snapshots.suffix(12).sorted { $0.date < $1.date }
        guard let first = points.first, let last = points.last, points.count >= 2,
              last.date.timeIntervalSince(first.date) >= 24 * 3600
        else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first.date) }
        let ys = points.map { Double($0.volume.freeBytes) }
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard variance > 0 else { return nil }
        let slope = covariance / variance
        guard slope < 0 else { return nil }
        return last.date.addingTimeInterval(Double(last.volume.freeBytes) / -slope)
    }

    /// Sources that grew noticeably since the previous snapshot, plus untouched projects.
    public static func insights(current: ScanResult, previous: Snapshot?, limit: Int = 3) -> [Insight] {
        var insights: [Insight] = []
        if let previous {
            for finding in current.findings where finding.consequence.isSelectable {
                // Something missing last time may just have become readable, so it isn't growth.
                guard let before = previous.sizes[finding.id] else { continue }
                let growth = finding.bytes - before
                guard growth >= 1_000_000_000 || (before > 0 && growth >= 500_000_000 && Double(growth) / Double(before) >= 0.5)
                else { continue }
                insights.append(Insight(id: "grew:" + finding.id,
                                        message: "\(finding.title) grew \(growth.formattedBytes) since the last scan",
                                        bytes: growth, action: .review(findingID: finding.id)))
            }
        }
        let untouched = current.findings.filter(\.isUntouched)
        let untouchedBytes = untouched.reduce(0) { $0 + $1.bytes }
        if untouchedBytes >= 500_000_000 {
            let projects = Set(untouched.compactMap { $0.paths.first?.deletingLastPathComponent() }).count
            insights.append(Insight(id: "untouched",
                                    message: "\(projects) untouched \(projects == 1 ? "project has" : "projects have") \(untouchedBytes.formattedBytes) of build folders",
                                    bytes: untouchedBytes, action: .selectUntouchedProjects))
        }
        return Array(insights.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }
}

/// Where Headroom keeps its own small files.
public enum AppFiles {
    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Headroom", directoryHint: .isDirectory)
    }
    public static var history: URL { directory.appending(path: "history.json") }
    public static var trashLog: URL { directory.appending(path: "trash-log.json") }
    public static var lastScan: URL { directory.appending(path: "last-scan.json") }
}

/// The last 52 snapshots, oldest first. Without a file it lives only in memory, as in example mode.
public struct HistoryStore: Sendable {
    public var file: URL?
    public private(set) var snapshots: [Snapshot]
    public static let limit = 52

    public init(snapshots: [Snapshot]) {
        file = nil
        self.snapshots = snapshots
    }

    public init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        snapshots = data.flatMap { try? JSONDecoder().decode([Snapshot].self, from: $0) } ?? []
    }

    public var latest: Snapshot? { snapshots.last }

    public mutating func append(_ snapshot: Snapshot) throws {
        snapshots.append(snapshot)
        snapshots = Array(snapshots.suffix(Self.limit))
        guard let file else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshots).write(to: file, options: .atomic)
    }
}
