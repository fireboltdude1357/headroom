import Foundation

/// A generated folder that a project's own files prove is safe to rebuild.
public struct BuildFolderRule: Sendable {
    public var ecosystem: String
    public var folder: String
    /// At least one must sit beside the folder, such as package.json next to node_modules.
    public var projectMarkers: [String]
    /// If set, one of these must exist inside the folder too.
    public var innerMarkers: [String] = []
    public var rebuildHint: String

    public static let all: [BuildFolderRule] = [
        .init(ecosystem: "Node.js", folder: "node_modules", projectMarkers: ["package.json"],
              rebuildHint: "Your package manager's install command recreates it."),
        // next.config is optional, so Next.js's own build files inside .next are what confirm it.
        .init(ecosystem: "Next.js", folder: ".next", projectMarkers: ["package.json"],
              innerMarkers: ["BUILD_ID", "build-manifest.json", "trace"],
              rebuildHint: "`next build` or `next dev` recreates it."),
        .init(ecosystem: "Rust", folder: "target", projectMarkers: ["Cargo.toml"],
              innerMarkers: ["CACHEDIR.TAG", ".rustc_info.json"],
              rebuildHint: "`cargo build` recreates it."),
        .init(ecosystem: "Swift", folder: ".build", projectMarkers: ["Package.swift"],
              rebuildHint: "`swift build` recreates it."),
        .init(ecosystem: "Python", folder: ".venv",
              projectMarkers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock"],
              innerMarkers: ["pyvenv.cfg"], rebuildHint: "Recreate the environment and reinstall dependencies."),
        .init(ecosystem: "Python", folder: "venv",
              projectMarkers: ["pyproject.toml", "requirements.txt", "setup.py", "Pipfile", "uv.lock"],
              innerMarkers: ["pyvenv.cfg"], rebuildHint: "Recreate the environment and reinstall dependencies."),
        .init(ecosystem: "Gradle", folder: "build",
              projectMarkers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
              rebuildHint: "The next Gradle build recreates it."),
        .init(ecosystem: "CocoaPods", folder: "Pods", projectMarkers: ["Podfile"],
              innerMarkers: ["Manifest.lock"], rebuildHint: "`pod install` recreates it."),
    ]
}

/// Finds build folders inside the usual places people keep code.
public struct ProjectFinder: Sendable {
    public var roots: [URL]
    public var maxDepth = 6
    public var untouchedAfter: TimeInterval = 90 * 24 * 3600
    public var now = Date()
    /// Shared by copies of this finder, so a monorepo's root is walked once per scan, not once per package.
    let lastWorkedCache = LastWorkedCache()

    public static let rootNames = ["Developer", "code", "Code", "Projects", "projects", "src", "dev", "repos",
                                   "GitHub", "Sites", "Documents", "Desktop"]

    public init(home: URL) {
        roots = Self.rootNames.map { home.appending(path: $0, directoryHint: .isDirectory) }
    }

    public init(roots: [URL]) {
        self.roots = roots
    }

    private static let generatedNames = Set(BuildFolderRule.all.map(\.folder))
    private static let skipNames: Set<String> = [".git", "Library", ".Trash", "DerivedData", "Pods"]

    /// Candidate build folders with their project, before measuring.
    public struct Candidate: Sendable, Hashable {
        public var folder: URL
        public var project: URL
        public var marker: URL
        /// The file inside the folder that proved it's generated, if the rule needs one.
        public var innerMarker: URL?
        public var ecosystem: String
        public var rebuildHint: String
    }

    public func candidates() -> [Candidate] {
        var found: [Candidate] = []
        var seenProjects = Set<String>()
        for root in roots where DiskMeasure.exists(root) {
            // A root like Documents may be a symlink or nested in another root; dedupe by resolved path.
            let resolved = root.resolvingSymlinksInPath().path
            guard seenProjects.insert(resolved).inserted else { continue }
            walk(root, depth: 0, into: &found)
        }
        // Roots can reach the same folder twice through a symlink, so compare resolved paths.
        var unique = Set<String>()
        return found.filter { unique.insert($0.folder.resolvingSymlinksInPath().path).inserted }
    }

    private func walk(_ dir: URL, depth: Int, into found: inout [Candidate]) {
        guard depth <= maxDepth,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
        let nameSet = Set(names)
        for rule in BuildFolderRule.all where nameSet.contains(rule.folder) {
            guard let marker = rule.projectMarkers.first(where: nameSet.contains) else { continue }
            let folder = dir.appending(path: rule.folder, directoryHint: .isDirectory)
            // A build folder that is a symlink may point into Documents; opening it could raise a prompt.
            let type = (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.type] as? FileAttributeType
            guard type != .typeSymbolicLink else { continue }
            var innerMarker: URL?
            if !rule.innerMarkers.isEmpty {
                let inner = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                guard let name = rule.innerMarkers.first(where: inner.contains) else { continue }
                innerMarker = folder.appending(path: name)
            }
            found.append(Candidate(folder: folder, project: dir, marker: dir.appending(path: marker), innerMarker: innerMarker,
                                   ecosystem: rule.ecosystem, rebuildHint: rule.rebuildHint))
        }
        for name in names.sorted() {
            // Never descend into generated folders or hidden folders; their contents are not projects.
            guard !name.hasPrefix("."), !Self.generatedNames.contains(name), !Self.skipNames.contains(name),
                  !name.hasSuffix(".app"), !name.hasSuffix(".photoslibrary")
            else { continue }
            let child = dir.appending(path: name, directoryHint: .isDirectory)
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true else { continue }
            walk(child, depth: depth + 1, into: &found)
        }
    }

    /// The last time someone worked on the project: the newest source file, skipping generated
    /// folders, plus git's index, which moves on every commit or checkout. The walk stops after
    /// `fileBudget` files so a giant repo can't stall the scan; that only makes a project look newer.
    public func lastWorked(on project: URL, fileBudget: Int = 5_000) -> Date? {
        if let cached = lastWorkedCache.lookup(project.path) { return cached }
        let result = walkForLastWorked(project, fileBudget: fileBudget)
        lastWorkedCache.store(result, for: project.path)
        return result
    }

    private func walkForLastWorked(_ project: URL, fileBudget: Int) -> Date? {
        var newest: Date?
        func consider(_ url: URL) {
            guard let date = DiskMeasure.modificationDate(url) else { return }
            if date > (newest ?? .distantPast) { newest = date }
        }
        consider(project.appending(path: ".git/index"))
        consider(project.appending(path: ".git/HEAD"))
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: project, includingPropertiesForKeys: keys,
                                                          options: [.skipsPackageDescendants], errorHandler: { _, _ in true })
        else { return newest }
        var budget = fileBudget
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == ".git" || Self.generatedNames.contains(name) || name == "DerivedData" {
                walker.skipDescendants()
                continue
            }
            budget -= 1
            if budget <= 0 { return now }
            guard name != ".DS_Store", let date = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate else { continue }
            if date > (newest ?? .distantPast) { newest = date }
        }
        return newest
    }

    /// The git repository a project lives in, so "ios/Pods" reads as "my-app/apps/mobile/ios/Pods".
    /// Worktrees have a `.git` file rather than a folder, which `fileExists` also matches.
    public func repositoryRoot(of project: URL) -> URL? {
        let stops = Set(roots.map(\.standardizedFileURL.path))
        var dir = project.standardizedFileURL
        while dir.pathComponents.count > 1 {
            if DiskMeasure.exists(dir.appending(path: ".git")) { return dir }
            if stops.contains(dir.path) { return nil }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    public func finding(for candidate: Candidate, measurement: Measurement) -> Finding {
        let repo = repositoryRoot(of: candidate.project)
        let lastWorked = [lastWorked(on: candidate.project), repo.flatMap { lastWorked(on: $0) }].compactMap { $0 }.max()
        let untouched = lastWorked.map { now.timeIntervalSince($0) > untouchedAfter } ?? false
        var name = candidate.project.lastPathComponent
        if let repo, repo.path != candidate.project.standardizedFileURL.path {
            let inner = candidate.project.standardizedFileURL.path.dropFirst(repo.path.count + 1)
            name = repo.lastPathComponent + "/" + inner
        }
        var detail = candidate.project.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let lastWorked {
            detail += " · last worked " + relativePhrase(lastWorked, now: now)
        }
        return Finding(
            id: "project:" + candidate.folder.standardizedFileURL.path,
            title: "\(name)/\(candidate.folder.lastPathComponent)",
            owner: candidate.ecosystem,
            category: .projects,
            consequence: .rebuilds,
            explanation: "Generated \(candidate.ecosystem) output confirmed by \(candidate.marker.lastPathComponent). Your source code stays. \(candidate.rebuildHint)",
            detail: detail,
            paths: [candidate.folder],
            bytes: measurement.bytes,
            lastModified: lastWorked,
            verificationMarkers: [candidate.marker] + [candidate.innerMarker].compactMap { $0 },
            isUntouched: untouched,
            fileNumbers: DiskMeasure.fileNumber(candidate.folder).map { [candidate.folder.path: $0] } ?? [:]
        )
    }
}

/// A thread-safe map from folder path to its "last worked" date. The value is optional because
/// "no date found" is also worth remembering.
final class LastWorkedCache: @unchecked Sendable {
    private var dates: [String: Date?] = [:]
    private let lock = NSLock()

    /// nil when the folder hasn't been walked yet; `.some(nil)` when it was and had no dates.
    func lookup(_ path: String) -> Date?? {
        lock.withLock { dates[path] }
    }

    func store(_ date: Date?, for path: String) {
        lock.withLock { _ = dates.updateValue(date, forKey: path) }
    }
}
