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
    /// Set when the Trash log couldn't be saved; cleanup stopped at that point.
    var logError: String?
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
    /// Read at launch, and every second while onboarding waits for the switch.
    var hasFullDiskAccess = FullDiskAccess.isGranted
    /// True until the first-launch onboarding ends with a scan or a skip.
    /// People who scanned before onboarding existed skip it.
    var showOnboarding = false

    var sidebar: SidebarItem? = .overview
    var selected: Set<String> = []
    var expanded: Set<String> = []
    var scanProgress: String?
    var isScanning: Bool { scanProgress != nil }
    var isCleaning = false
    /// True while a scan or cleanup runs; mode switches and new scans wait.
    var isBusy: Bool { isScanning || isCleaning }
    /// Bumped whenever the mode changes, so a scan that finishes late is discarded.
    private var generation = 0

    var showReview = false
    var summary: CleanupSummary?
    var restoreErrors: [TrashRecord.ID: String] = [:]

    let background = BackgroundTasks()

    init() {
        // Cleanup and restore touch the same files a scan does, so they follow the same rule.
        DiskMeasure.neverDownload()
        history = HistoryStore(file: AppFiles.history)
        trashLog = TrashLog(file: AppFiles.trashLog)
        scan = Self.loadLastScan()
        showOnboarding = scan == nil && !UserDefaults.standard.bool(forKey: Prefs.onboarded)
    }

    private static func loadLastScan() -> ScanResult? {
        guard let data = try? Data(contentsOf: AppFiles.lastScan) else { return nil }
        return try? JSONDecoder().decode(ScanResult.self, from: data)
    }

    private func saveLastScan() {
        guard let scan, let data = try? JSONEncoder().encode(scan) else { return }
        try? FileManager.default.createDirectory(at: AppFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: AppFiles.lastScan, options: .atomic)
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

    /// What the trend line can say. `fillDate` needs two snapshots at least a day apart.
    enum Trend {
        case notEnoughHistory
        case notShrinking
        case full(Date)
    }

    var trend: Trend {
        let snapshots = trendSnapshots
        guard let first = snapshots.first, let last = snapshots.last, snapshots.count >= 2,
              last.date.timeIntervalSince(first.date) >= 24 * 3600
        else { return .notEnoughHistory }
        if let date = Trends.fillDate(snapshots) { return .full(date) }
        return .notShrinking
    }

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

    func recheckFullDiskAccess() {
        let granted = FullDiskAccess.isGranted
        if granted != hasFullDiskAccess { hasFullDiskAccess = granted }
    }

    func finishOnboarding(scan: Bool) {
        UserDefaults.standard.set(true, forKey: Prefs.onboarded)
        showOnboarding = false
        if scan { Task { await runScan() } }
    }

    func loadExample() {
        guard !isBusy else { return }
        generation += 1
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
        guard !isBusy else { return }
        generation += 1
        isExample = false
        history = HistoryStore(file: AppFiles.history)
        trashLog = TrashLog(file: AppFiles.trashLog)
        exampleRecords = []
        exampleRemoved = [:]
        selected = []
        expanded = []
        summary = nil
        scan = Self.loadLastScan()
        showOnboarding = scan == nil && !UserDefaults.standard.bool(forKey: Prefs.onboarded)
    }

    func runScan() async {
        guard !isBusy else { return }
        if isExample { leaveExample() }
        let started = generation
        scanProgress = "Starting"
        selected = []
        let progress = ProgressRelay { [weak self] text in
            // Updates arrive as separate tasks, so ignore any that land after the scan ended.
            Task { @MainActor in if self?.scanProgress != nil { self?.scanProgress = text } }
        }
        let result = await Task.detached(priority: .userInitiated) {
            await Scanner().scan(progress: { progress.report($0) })
        }.value
        scanProgress = nil
        // The mode changed while scanning (example data loaded), so this result no longer applies.
        guard generation == started, !isExample else { return }
        scan = result
        try? history.append(Snapshot(result))
        saveLastScan()
        background.afterScan(result.volume)
    }

    // MARK: Cleanup

    var plan: CleanupPlan { CleanupPlan(selectedFindings) }

    /// Name of the running app for a bundle id, or nil when it isn't open.
    /// An app with no localized name still counts as running.
    nonisolated static let runningApp: @Sendable (String) -> String? = { id in
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return nil }
        return app.localizedName ?? id
    }

    nonisolated static let isAppInstalled: @Sendable (String) -> Bool = { id in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    func runCleanup() async {
        guard scan != nil, !isBusy else { return }
        if isExample { return runExampleCleanup() }
        isCleaning = true
        defer { isCleaning = false }
        let plan = plan
        let freeBefore = VolumeInfo.current()?.freeBytes ?? scan?.volume.freeBytes ?? 0
        let cleaner = Cleaner(runningApp: Self.runningApp, isAppInstalled: Self.isAppInstalled)
        let log = trashLog
        let (result, updatedLog) = await Task.detached(priority: .userInitiated) {
            var log = log
            let result = cleaner.run(plan) { try log.append([$0]) }
            return (result, log)
        }.value
        trashLog = updatedLog
        removeMovedPaths(result.moved)
        saveLastScan()
        finish(moved: result.moved, skipped: result.skipped, logError: result.logError, freeBefore: freeBefore,
               freeAfter: VolumeInfo.current()?.freeBytes ?? freeBefore)
    }

    /// Takes moved paths out of their findings. A finding with paths left keeps them at its reduced size;
    /// one with nothing left goes away. Skipped findings stay as they were.
    private func removeMovedPaths(_ moved: [TrashRecord]) {
        guard var scan else { return }
        let movedByFinding = Dictionary(grouping: moved, by: \.findingID)
        scan.findings = scan.findings.compactMap { finding in
            guard let records = movedByFinding[finding.id] else { return finding }
            var finding = finding
            let movedPaths = Set(records.map(\.original.path))
            finding.paths.removeAll { movedPaths.contains($0.path) }
            guard !finding.paths.isEmpty else { return nil }
            finding.bytes = max(0, finding.bytes - records.reduce(0) { $0 + $1.bytes })
            return finding
        }
        self.scan = scan
    }

    /// Synchronous so snapshot mode can use it too.
    func runExampleCleanup() {
        guard let free = scan?.volume.freeBytes else { return }
        let (moved, skipped) = simulateCleanup(plan)
        finish(moved: moved, skipped: skipped, logError: nil, freeBefore: free, freeAfter: free)
    }

    private func finish(moved: [TrashRecord], skipped: [(finding: Finding, reason: SkipReason)], logError: String?,
                        freeBefore: Int64, freeAfter: Int64) {
        selected.subtract(moved.map(\.findingID))
        showReview = false
        summary = CleanupSummary(moved: moved, skipped: skipped, logError: logError, freeBefore: freeBefore, freeAfter: freeAfter)
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
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "The CSV couldn't be saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

/// Lets the scanner's `@Sendable` progress closure hand text back to the main actor.
private struct ProgressRelay: Sendable {
    let report: @Sendable (String) -> Void
    init(_ report: @escaping @Sendable (String) -> Void) { self.report = report }
}
