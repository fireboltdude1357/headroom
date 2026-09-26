import AppKit
import HeadroomCore
import Observation
import SwiftUI

/// One sidebar entry.
enum SidebarItem: Hashable {
    case overview
    case category(FindingCategory)
    case trash
}

/// What the cleanup did, shown after "Move to Trash".
struct CleanupSummary: Identifiable {
    let id = UUID()
    var moved: [TrashRecord]
    var skipped: [(finding: Finding, reason: SkipReason)]
    var freeBefore: Int64
    var freeAfter: Int64
    var bytesMoved: Int64 { moved.reduce(0) { $0 + $1.bytes } }
}

/// The single source of state for the app, the menu bar panel and snapshot mode.
@Observable @MainActor
final class AppModel {
    var scan: ScanResult?
    var history: HistoryStore
    var trashLog: TrashLog
    /// Example mode never writes to disk; these stand in for the trash log.
    var exampleRecords: [TrashRecord] = []
    /// Findings removed by a simulated cleanup, keyed by record id, so Restore can put them back.
    private var exampleRemoved: [TrashRecord.ID: Finding] = [:]
    var isExample = false

    var sidebar: SidebarItem? = .overview
    var selected: Set<String> = []
    var expanded: Set<String> = []
    var scanProgress: String?
    var isScanning: Bool { scanProgress != nil }

    var showReview = false
    var summary: CleanupSummary?
    var restoreErrors: [TrashRecord.ID: String] = [:]

    let background = BackgroundTasks()

    init() {
        history = HistoryStore(file: AppFiles.history)
        trashLog = TrashLog(file: AppFiles.trashLog)
        if let data = try? Data(contentsOf: AppFiles.lastScan),
           let last = try? JSONDecoder().decode(ScanResult.self, from: data) {
            scan = last
        }
    }

    // MARK: Derived

    var categories: [FindingCategory] {
        guard let scan else { return [] }
        return FindingCategory.allCases.filter { category in scan.findings.contains { $0.category == category } }
    }

    func findings(in category: FindingCategory) -> [Finding] { scan?.findings(in: category) ?? [] }

    var selectedFindings: [Finding] { scan?.findings.filter { selected.contains($0.id) } ?? [] }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.bytes } }

    /// The snapshot taken before the current scan, for "since last time" comparisons.
    var previousSnapshot: Snapshot? {
        guard let scan else { return history.latest }
        return history.snapshots.last { $0.date < scan.date }
    }

    /// History plus the current scan when it hasn't been appended yet (example mode).
    var trendSnapshots: [Snapshot] {
        guard let scan else { return history.snapshots }
        if history.latest?.date == scan.date { return history.snapshots }
        return history.snapshots + [Snapshot(scan)]
    }

    var fillDate: Date? { Trends.fillDate(trendSnapshots) }

    var insights: [Insight] {
        guard let scan else { return [] }
        return Trends.insights(current: scan, previous: previousSnapshot)
    }

    /// Positive when free space grew since the previous snapshot.
    var freeChange: Int64? {
        guard let scan, let previous = previousSnapshot else { return nil }
        return scan.volume.freeBytes - previous.volume.freeBytes
    }

    var records: [TrashRecord] { isExample ? exampleRecords : trashLog.records }

    // MARK: Selection

    func toggle(_ finding: Finding) {
        guard finding.consequence.isSelectable else { return }
        if selected.contains(finding.id) { selected.remove(finding.id) } else { selected.insert(finding.id) }
    }

    func selectUntouchedProjects() {
        sidebar = .category(.projects)
        for finding in findings(in: .projects) where finding.isUntouched { selected.insert(finding.id) }
    }

    func perform(_ action: Insight.Action) {
        switch action {
        case let .review(findingID):
            guard let finding = scan?.findings.first(where: { $0.id == findingID }) else { return }
            sidebar = .category(finding.category)
            expanded.insert(finding.id)
        case .selectUntouchedProjects:
            selectUntouchedProjects()
        }
    }

    // MARK: Scanning

    func loadExample() {
        isExample = true
        scan = ExampleData.scan()
        history = HistoryStore(snapshots: ExampleData.history())
        exampleRecords = []
        exampleRemoved = [:]
        selected = []
        expanded = []
        summary = nil
        sidebar = .overview
    }

    func leaveExample() {
        isExample = false
        history = HistoryStore(file: AppFiles.history)
        trashLog = TrashLog(file: AppFiles.trashLog)
        exampleRecords = []
        exampleRemoved = [:]
        selected = []
        expanded = []
        if let data = try? Data(contentsOf: AppFiles.lastScan) {
            scan = try? JSONDecoder().decode(ScanResult.self, from: data)
        } else {
            scan = nil
        }
    }

    func runScan() async {
        guard !isScanning else { return }
        if isExample { leaveExample() }
        scanProgress = "Starting"
        selected = []
        let progress = ProgressRelay { [weak self] text in
            Task { @MainActor in self?.scanProgress = text }
        }
        let result = await Task.detached(priority: .userInitiated) {
            await Scanner().scan(progress: { progress.report($0) })
        }.value
        scan = result
        scanProgress = nil
        try? history.append(Snapshot(result))
        if let data = try? JSONEncoder().encode(result) {
            try? FileManager.default.createDirectory(at: AppFiles.directory, withIntermediateDirectories: true)
            try? data.write(to: AppFiles.lastScan, options: .atomic)
        }
        background.afterScan(result.volume)
    }

    // MARK: Cleanup

    var plan: CleanupPlan { CleanupPlan(selectedFindings) }

    /// Name of the running app for a bundle id, or nil when it isn't open.
    nonisolated static let runningApp: @Sendable (String) -> String? = { id in
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
    }

    func runCleanup() async {
        guard let scan else { return }
        if isExample { return runExampleCleanup() }
        let plan = plan
        let freeBefore = scan.volume.freeBytes
        let cleaner = Cleaner(runningApp: Self.runningApp)
        let result = await Task.detached(priority: .userInitiated) { cleaner.run(plan) }.value
        try? trashLog.append(result.moved)
        let movedIDs = Set(result.moved.map(\.findingID))
        self.scan?.findings.removeAll { movedIDs.contains($0.id) }
        finish(moved: result.moved, skipped: result.skipped, freeBefore: freeBefore,
               freeAfter: VolumeInfo.current()?.freeBytes ?? freeBefore)
    }

    /// Synchronous so snapshot mode can use it too.
    func runExampleCleanup() {
        guard let free = scan?.volume.freeBytes else { return }
        let (moved, skipped) = simulateCleanup(plan)
        finish(moved: moved, skipped: skipped, freeBefore: free, freeAfter: free)
    }

    private func finish(moved: [TrashRecord], skipped: [(finding: Finding, reason: SkipReason)], freeBefore: Int64, freeAfter: Int64) {
        selected.subtract(moved.map(\.findingID))
        showReview = false
        summary = CleanupSummary(moved: moved, skipped: skipped, freeBefore: freeBefore, freeAfter: freeAfter)
    }

    /// Example mode: pretend every path moved, and remember the findings so Restore can bring them back.
    /// The running-app check is real so the result screen can show a skip, but nothing on disk moves.
    private func simulateCleanup(_ plan: CleanupPlan) -> (moved: [TrashRecord], skipped: [(finding: Finding, reason: SkipReason)]) {
        var moved: [TrashRecord] = []
        var skipped: [(finding: Finding, reason: SkipReason)] = []
        for finding in plan.findings {
            if let app = finding.blockingBundleIDs.lazy.compactMap(Self.runningApp).first {
                skipped.append((finding, .appRunning(app)))
                continue
            }
            guard let path = finding.paths.first else { continue }
            let record = TrashRecord(findingID: finding.id, title: finding.title, original: path,
                                     trashed: URL(filePath: "/Example/Users/sam/.Trash/\(path.lastPathComponent)"),
                                     bytes: finding.bytes)
            moved.append(record)
            exampleRemoved[record.id] = finding
            scan?.findings.removeAll { $0.id == finding.id }
        }
        exampleRecords.insert(contentsOf: moved, at: 0)
        return (moved, skipped)
    }

    // MARK: Trash

    func pruneTrash() {
        guard !isExample else { return }
        try? trashLog.prune()
    }

    func restore(_ record: TrashRecord) {
        restoreErrors[record.id] = nil
        if isExample {
            exampleRecords.removeAll { $0.id == record.id }
            if let finding = exampleRemoved.removeValue(forKey: record.id) {
                scan?.findings.append(finding)
                scan?.findings.sort { $0.bytes > $1.bytes }
            }
            return
        }
        do { try trashLog.restore(record) } catch { restoreErrors[record.id] = error.localizedDescription }
    }

    // MARK: Export

    func exportCSV() {
        guard let scan else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Headroom scan.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func cell(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["title,owner,category,consequence,bytes,paths"]
        for finding in scan.findings {
            lines.append([cell(finding.title), cell(finding.owner), cell(finding.category.label),
                          cell(finding.consequence.label), String(finding.bytes),
                          cell(finding.paths.map(\.path).joined(separator: "; "))].joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Lets the scanner's `@Sendable` progress closure hand text back to the main actor.
private struct ProgressRelay: Sendable {
    let report: @Sendable (String) -> Void
    init(_ report: @escaping @Sendable (String) -> Void) { self.report = report }
}
