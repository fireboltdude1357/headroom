import Foundation

/// Moves a file to the Trash and returns where it ended up. Tests swap in a fake.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws -> URL
}

public struct FinderTrash: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }
}

/// The cleanup the user is about to confirm, grouped by what happens afterwards.
public struct CleanupPlan: Sendable {
    public var groups: [(consequence: Consequence, findings: [Finding])]

    /// App-managed items are dropped here as a second guard; the UI shouldn't offer them anyway.
    public init(_ findings: [Finding]) {
        let selectable = findings.filter(\.consequence.isSelectable)
        groups = Dictionary(grouping: selectable, by: \.consequence)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.bytes > $1.bytes }) }
    }

    public var findings: [Finding] { groups.flatMap(\.findings) }
    public var totalBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }
    public var warnings: [String] { findings.compactMap(\.warning) }
}

public struct TrashRecord: Codable, Sendable, Identifiable, Hashable {
    public var id = UUID()
    public var findingID: String
    public var title: String
    public var original: URL
    public var trashed: URL
    public var bytes: Int64
    public var date: Date
    /// Inode of the item in the Trash, so restore never moves back something else with the same name.
    public var fileNumber: UInt64?

    public init(id: UUID = UUID(), findingID: String, title: String, original: URL, trashed: URL, bytes: Int64,
                date: Date = .now, fileNumber: UInt64? = nil) {
        self.id = id
        self.findingID = findingID
        self.title = title
        self.original = original
        self.trashed = trashed
        self.bytes = bytes
        self.date = date
        self.fileNumber = fileNumber
    }
}

public enum SkipReason: Sendable, Hashable {
    case appRunning(String)
    case missing
    case markerMissing(String)
    case failed(String)

    public var description: String {
        switch self {
        case let .appRunning(app): "\(app) was open"
        case .missing: "it no longer exists"
        case let .markerMissing(file): "\(file) is gone, so Headroom can't confirm what it is"
        case let .failed(message): message
        }
    }
}

public struct CleanupResult: Sendable {
    public var moved: [TrashRecord]
    public var skipped: [(finding: Finding, reason: SkipReason)]

    public init(moved: [TrashRecord] = [], skipped: [(finding: Finding, reason: SkipReason)] = []) {
        self.moved = moved
        self.skipped = skipped
    }

    public var bytesMoved: Int64 { moved.reduce(0) { $0 + $1.bytes } }
}

public struct Cleaner: Sendable {
    public var trasher: any Trasher
    /// Returns the name of a running app for a bundle ID, or nil if it isn't running.
    public var runningApp: @Sendable (String) -> String?

    public init(trasher: any Trasher = FinderTrash(), runningApp: @escaping @Sendable (String) -> String?) {
        self.trasher = trasher
        self.runningApp = runningApp
    }

    /// Checks each item again right before moving it: the app must be closed, the files must
    /// still exist, and the files that identified it must still be there.
    public func verify(_ finding: Finding) -> SkipReason? {
        guard finding.consequence.isSelectable else { return .failed("Headroom doesn't remove app-managed data") }
        if let path = finding.paths.first(where: { Catalog.isProtected($0) }) {
            return .failed("\(path.lastPathComponent) holds data its app manages")
        }
        if let app = finding.blockingBundleIDs.lazy.compactMap(runningApp).first { return .appRunning(app) }
        if let marker = finding.verificationMarkers.first(where: { !DiskMeasure.exists($0) }) {
            return .markerMissing(marker.lastPathComponent)
        }
        if !finding.paths.contains(where: DiskMeasure.exists) { return .missing }
        return nil
    }

    public func run(_ plan: CleanupPlan, now: Date = .now) -> CleanupResult {
        var result = CleanupResult()
        for finding in plan.findings {
            if let reason = verify(finding) {
                result.skipped.append((finding, reason))
                continue
            }
            for path in finding.paths where DiskMeasure.exists(path) {
                // Measure what's there now; the scan may be hours old.
                let bytes = DiskMeasure.measure(path).bytes
                do {
                    let trashed = try trasher.trash(path)
                    result.moved.append(TrashRecord(findingID: finding.id, title: finding.title, original: path,
                                                    trashed: trashed, bytes: bytes, date: now,
                                                    fileNumber: DiskMeasure.fileNumber(trashed)))
                } catch {
                    result.skipped.append((finding, .failed(error.localizedDescription)))
                }
            }
        }
        return result
    }
}

/// Everything Headroom has moved to the Trash, so it can be put back.
public struct TrashLog: Sendable {
    public var file: URL
    public private(set) var records: [TrashRecord]

    public init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        records = data.flatMap { try? JSONDecoder().decode([TrashRecord].self, from: $0) } ?? []
    }

    public mutating func append(_ new: [TrashRecord]) throws {
        records.insert(contentsOf: new, at: 0)
        try save()
    }

    /// Drops records whose item has left the Trash, because it was emptied or put back by hand.
    public mutating func prune() throws {
        let before = records.count
        records.removeAll { !Self.isStillInTrash($0) }
        if records.count != before { try save() }
    }

    static func isStillInTrash(_ record: TrashRecord) -> Bool {
        guard DiskMeasure.exists(record.trashed) else { return false }
        guard let expected = record.fileNumber else { return true }
        return DiskMeasure.fileNumber(record.trashed) == expected
    }

    public enum RestoreError: LocalizedError {
        case goneFromTrash, originalOccupied(String)

        public var errorDescription: String? {
            switch self {
            case .goneFromTrash: "It's no longer in the Trash."
            case let .originalOccupied(path): "Something already exists at \(path)."
            }
        }
    }

    /// Moves an item from the Trash back where it was.
    public mutating func restore(_ record: TrashRecord) throws {
        let fm = FileManager.default
        guard Self.isStillInTrash(record) else {
            records.removeAll { $0.id == record.id }
            try save()
            throw RestoreError.goneFromTrash
        }
        guard !fm.fileExists(atPath: record.original.path) else {
            throw RestoreError.originalOccupied(record.original.path)
        }
        try fm.createDirectory(at: record.original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: record.trashed, to: record.original)
        records.removeAll { $0.id == record.id }
        try save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: file, options: .atomic)
    }
}
