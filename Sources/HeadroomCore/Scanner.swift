import AppKit
import Foundation

/// Installed apps by bundle ID, read from the standard Applications folders.
public struct InstalledApps: Sendable {
    public var names: [String: String]

    public static func discover(home: URL) -> InstalledApps {
        let dirs = [URL(filePath: "/Applications"), URL(filePath: "/Applications/Utilities"),
                    URL(filePath: "/System/Applications"), URL(filePath: "/System/Applications/Utilities"),
                    home.appending(path: "Applications")]
        var names: [String: String] = [:]
        for dir in dirs {
            let apps = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            // Setapp and similar keep apps one folder deeper.
            let nested = apps.filter { $0.pathExtension.isEmpty }.flatMap {
                (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
            }
            for app in apps + nested where app.pathExtension == "app" {
                guard let bundle = Bundle(url: app), let id = bundle.bundleIdentifier else { continue }
                names[id] = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? app.deletingPathExtension().lastPathComponent
            }
        }
        return InstalledApps(names: names)
    }
}

/// Walks every known source and discovered folder, measuring them in parallel.
public struct Scanner: Sendable {
    public var home: URL
    public var projectFinder: ProjectFinder
    public var maxConcurrent = 6

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        projectFinder = ProjectFinder(home: home)
    }

    /// macOS only lets apps with Full Disk Access open the privacy databases or list Safari's folder, so
    /// any one of those succeeding is the signal. None of them raise a prompt when access is off.
    /// Trying them is also what puts Headroom in the Full Disk Access list, so users only flip a switch.
    public static func hasFullDiskAccess(home: URL) -> Bool {
        let databases = [home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
                         URL(filePath: "/Library/Application Support/com.apple.TCC/TCC.db")]
        if databases.contains(where: { (try? FileHandle(forReadingFrom: $0)) != nil }) { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: home.appending(path: "Library/Safari").path)) != nil
    }

    /// Runs a full scan. `progress` receives a short label for each step.
    public func scan(progress: @Sendable (String) -> Void = { _ in }) async -> ScanResult {
        // Finding projects and measuring folders both list directories, so this covers them all.
        DiskMeasure.neverDownload()
        let fullDiskAccess = Self.hasFullDiskAccess(home: home)
        let apps = InstalledApps.discover(home: home)
        var discoveries = Discoveries(home: home, installedBundleIDs: Set(apps.names.keys))
        discoveries.isRegisteredApp = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }

        var unreadable: [URL] = []
        var jobs: [Job] = []

        // Catalog sources.
        var catalogPaths: [URL] = []
        for source in Catalog.sources {
            var paths: [URL] = []
            for relative in source.paths {
                let url = home.appending(path: relative, directoryHint: .isDirectory)
                catalogPaths.append(url)
                // Even checking that a protected path exists counts as touching it, so skip it outright.
                if !fullDiskAccess && (Catalog.needsFullDiskAccess(relative) || Catalog.needsFullDiskAccess(url, home: home)) {
                    continue
                }
                if DiskMeasure.exists(url) { paths.append(url) }
            }
            guard !paths.isEmpty else { continue }
            let finding = Finding(id: source.id, title: source.title, owner: source.owner, category: source.category,
                                  consequence: source.consequence, explanation: source.explanation,
                                  warning: source.warning, settingsHint: source.settingsHint, paths: paths, bytes: 0,
                                  blockingBundleIDs: source.blockingBundleIDs)
            jobs.append(.finding(finding))
        }

        progress("Looking for project build folders")
        var finder = projectFinder
        if !fullDiskAccess { finder.roots.removeAll { Catalog.needsFullDiskAccess($0, home: home) } }
        for candidate in finder.candidates() { jobs.append(.project(candidate, finder)) }

        if fullDiskAccess {
            for (finding, _) in discoveries.deviceBackups() { jobs.append(.finding(finding)) }
        }

        // Skip folders the catalog already covers, including ones that merely contain a catalog path,
        // like Docker's container around its app-managed disk image.
        // Installed apps' own data is never offered, so don't spend time measuring it.
        for folder in discoveries.appFolders(includeContainers: fullDiskAccess)
        where !catalogPaths.contains(where: { DiskMeasure.overlaps($0, folder.url) })
            && (folder.kind == .cache || !discoveries.isInstalled(folder.bundleID)) {
            jobs.append(.appFolder(folder))
        }

        var findings = (fullDiskAccess ? discoveries.oldInstallers() : []).map { finding in
            var finding = finding
            finding.fileNumbers = Self.fileNumbers(finding.paths)
            return finding
        }
        progress("Measuring \(jobs.count) locations")
        let measured = await withTaskGroup(of: JobResult.self) { group in
            var results: [JobResult] = []
            var iterator = jobs.makeIterator()
            func next() -> Job? { iterator.next() }
            for _ in 0..<maxConcurrent {
                guard let job = next() else { break }
                group.addTask { Self.run(job) }
            }
            for await result in group {
                results.append(result)
                progress("Measuring \(results.count) of \(jobs.count) locations")
                if !Task.isCancelled, let job = next() { group.addTask { Self.run(job) } }
            }
            return results
        }

        for result in measured {
            switch result {
            case let .finding(finding, measurements):
                if measurements.contains(where: { !$0.readable || $0.incomplete }) { unreadable.append(contentsOf: finding.paths) }
                var finding = finding
                finding.bytes = measurements.reduce(0) { $0 + $1.bytes }
                finding.isPartial = measurements.contains(where: \.incomplete)
                finding.fileNumbers = Self.fileNumbers(finding.paths)
                finding.lastModified = finding.lastModified ?? measurements.compactMap(\.newest).max()
                if finding.bytes >= 1_000_000 { findings.append(finding) }
            case let .project(finding):
                if let finding { findings.append(finding) }
            case let .appFolder(folder, measurement):
                if var finding = discoveries.finding(for: folder, measurement: measurement, appName: apps.names[folder.bundleID]) {
                    finding.isPartial = measurement.incomplete
                    finding.fileNumbers = Self.fileNumbers(finding.paths)
                    findings.append(finding)
                }
            }
        }

        findings.sort { $0.bytes > $1.bytes }
        return ScanResult(date: .now, volume: VolumeInfo.current() ?? VolumeInfo(totalBytes: 0, freeBytes: 0),
                          findings: findings, unreadable: unreadable, hasFullDiskAccess: fullDiskAccess)
    }

    static func fileNumbers(_ paths: [URL]) -> [String: UInt64] {
        Dictionary(paths.compactMap { path in DiskMeasure.fileNumber(path).map { (path.path, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    private enum Job: Sendable {
        case finding(Finding)
        case project(ProjectFinder.Candidate, ProjectFinder)
        case appFolder(Discoveries.AppFolder)
    }

    private enum JobResult: Sendable {
        case finding(Finding, [Measurement])
        case project(Finding?)
        case appFolder(Discoveries.AppFolder, Measurement)
    }

    private static func run(_ job: Job) -> JobResult {
        switch job {
        case let .finding(finding): return .finding(finding, finding.paths.map(DiskMeasure.measure))
        case let .project(candidate, finder):
            // Working out "last worked" walks the project's sources, so it runs here in parallel too.
            let measurement = DiskMeasure.measure(candidate.folder)
            return .project(measurement.bytes > 0 ? finder.finding(for: candidate, measurement: measurement) : nil)
        case let .appFolder(folder): return .appFolder(folder, DiskMeasure.measure(folder.url))
        }
    }
}
