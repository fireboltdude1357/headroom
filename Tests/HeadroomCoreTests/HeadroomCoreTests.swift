import Foundation
import Testing
@testable import HeadroomCore

/// A scratch folder that deletes itself.
final class Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "headroom-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ path: String, bytes: Int = 10, modified: Date? = nil) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func touch(_ path: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: root.appending(path: path).path)
    }
}

/// Moves "trashed" items into a folder inside the sandbox instead of the real Trash.
struct FolderTrash: Trasher {
    let folder: URL

    func trash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

@Suite struct ProjectFinderTests {
    @Test func findsBuildFoldersOnlyWhenTheProjectConfirmsThem() throws {
        let box = try Sandbox()
        try box.file("app/package.json")
        try box.file("app/node_modules/react/index.js")
        try box.file("app/node_modules/nested/node_modules/x/index.js") // inside a generated folder, not a project
        try box.file("notes/node_modules/stray.js") // no package.json
        try box.file("rusty/Cargo.toml")
        try box.file("rusty/target/CACHEDIR.TAG")
        try box.file("fake-rust/Cargo.toml")
        try box.file("fake-rust/target/release/my-notes.txt") // "target" without Cargo's own files
        try box.file("py/pyproject.toml")
        try box.file("py/.venv/pyvenv.cfg")

        let found = ProjectFinder(roots: [box.root]).candidates()
        let names = Set(found.map { "\($0.project.lastPathComponent)/\($0.folder.lastPathComponent)" })
        #expect(names == ["app/node_modules", "rusty/target", "py/.venv"])
    }

    @Test func namesNestedProjectsAfterTheirRepository() throws {
        let box = try Sandbox()
        try box.file("shop/.git/HEAD")
        try box.file("shop/apps/mobile/ios/Podfile")
        try box.file("shop/apps/mobile/ios/Pods/Manifest.lock")
        let finder = ProjectFinder(roots: [box.root])
        let candidate = try #require(finder.candidates().first)
        #expect(finder.finding(for: candidate, measurement: Measurement()).title == "shop/apps/mobile/ios/Pods")
    }

    @Test func flagsProjectsNobodyTouchedInMonths() throws {
        let box = try Sandbox()
        let old = Date.now.addingTimeInterval(-200 * 86400)
        try box.file("old/package.json", modified: old)
        try box.file("old/src/index.ts", modified: old)
        try box.file("old/node_modules/a.js")
        try box.touch("old/src", old)
        try box.file("fresh/package.json")
        try box.file("fresh/node_modules/a.js")

        let finder = ProjectFinder(roots: [box.root])
        let findings = finder.candidates().map { finder.finding(for: $0, measurement: DiskMeasure.measure($0.folder)) }
        let untouched = Set(findings.filter(\.isUntouched).map(\.title))
        #expect(untouched == ["old/node_modules"])
    }
}

@Suite struct CleanerTests {
    func finding(_ box: Sandbox, blocking: [String] = [], markers: [URL] = [], consequence: Consequence = .rebuilds) throws -> Finding {
        let folder = box.root.appending(path: "cache")
        try box.file("cache/blob", bytes: 4096)
        return Finding(id: "test", title: "Test cache", owner: "Test", category: .appCaches, consequence: consequence,
                       explanation: "", paths: [folder], bytes: 4096, blockingBundleIDs: blocking, verificationMarkers: markers)
    }

    @Test func skipsItemsWhoseAppIsOpen() throws {
        let box = try Sandbox()
        let item = try finding(box, blocking: ["com.google.Chrome"])
        let cleaner = Cleaner(trasher: FolderTrash(folder: box.root.appending(path: "Trash"))) { $0 == "com.google.Chrome" ? "Chrome" : nil }
        let result = cleaner.run(CleanupPlan([item]))
        #expect(result.moved.isEmpty)
        #expect(result.skipped.map(\.reason) == [.appRunning("Chrome")])
        #expect(DiskMeasure.exists(item.paths[0]))
    }

    @Test func skipsWhenTheIdentifyingFileIsGone() throws {
        let box = try Sandbox()
        let item = try finding(box, markers: [box.root.appending(path: "package.json")])
        let result = Cleaner(trasher: FolderTrash(folder: box.root.appending(path: "Trash"))) { _ in nil }.run(CleanupPlan([item]))
        #expect(result.skipped.map(\.reason) == [.markerMissing("package.json")])
    }

    @Test func neverPlansAppManagedData() throws {
        let box = try Sandbox()
        let item = try finding(box, consequence: .appManaged)
        #expect(CleanupPlan([item]).findings.isEmpty)
    }

    @Test func refusesAppManagedLocationsEvenInsideAnotherFinding() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let docker = home.appending(path: "Library/Containers/com.docker.docker")
        #expect(Catalog.isProtected(docker))
        #expect(Catalog.isProtected(home.appending(path: "Pictures/Photos Library.photoslibrary/originals")))
        #expect(!Catalog.isProtected(home.appending(path: ".npm/_cacache")))
    }

    @Test func movesToTrashAndRestores() throws {
        let box = try Sandbox()
        let item = try finding(box)
        let cleaner = Cleaner(trasher: FolderTrash(folder: box.root.appending(path: "Trash"))) { _ in nil }
        let result = cleaner.run(CleanupPlan([item]))
        #expect(result.skipped.isEmpty)
        #expect(result.moved.count == 1)
        #expect(result.bytesMoved >= 4096)
        #expect(!DiskMeasure.exists(item.paths[0]))

        var log = TrashLog(file: box.root.appending(path: "log.json"))
        try log.append(result.moved)
        #expect(TrashLog(file: log.file).records == result.moved)

        try log.restore(result.moved[0])
        #expect(DiskMeasure.exists(item.paths[0].appending(path: "blob")))
        #expect(log.records.isEmpty)
    }

    @Test func refusesToRestoreOverSomethingNew() throws {
        let box = try Sandbox()
        let item = try finding(box)
        let result = Cleaner(trasher: FolderTrash(folder: box.root.appending(path: "Trash"))) { _ in nil }.run(CleanupPlan([item]))
        var log = TrashLog(file: box.root.appending(path: "log.json"))
        try log.append(result.moved)
        try box.file("cache/new-file")
        #expect(throws: TrashLog.RestoreError.self) { try log.restore(result.moved[0]) }
        #expect(log.records.count == 1)
    }
}

@Suite struct MeasureTests {
    @Test func countsHardLinkedFilesOnce() throws {
        let box = try Sandbox()
        let original = try box.file("store/blob", bytes: 1_000_000)
        try FileManager.default.createDirectory(at: box.root.appending(path: "store/linked"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: box.root.appending(path: "store/linked/blob"))
        let bytes = DiskMeasure.measure(box.root.appending(path: "store")).bytes
        #expect(bytes >= 1_000_000 && bytes < 1_200_000)
    }
}

@Suite struct TrendTests {
    let gb: Int64 = 1_000_000_000

    func snapshot(daysAgo: Double, freeGB: Int64, sizes: [String: Int64] = [:]) -> Snapshot {
        Snapshot(date: Date(timeIntervalSince1970: 1_000_000_000 - daysAgo * 86400),
                 volume: VolumeInfo(totalBytes: 500 * gb, freeBytes: freeGB * gb), sizes: sizes)
    }

    @Test func projectsWhenTheDiskFills() throws {
        // Losing 10 GB a week with 30 GB left: full in three weeks.
        let history = [snapshot(daysAgo: 14, freeGB: 50), snapshot(daysAgo: 7, freeGB: 40), snapshot(daysAgo: 0, freeGB: 30)]
        let full = try #require(Trends.fillDate(history))
        let days = full.timeIntervalSince(history[2].date) / 86400
        #expect(abs(days - 21) < 0.01)
    }

    @Test func noEstimateWhenSpaceIsGrowingOrHistoryIsShort() {
        #expect(Trends.fillDate([snapshot(daysAgo: 7, freeGB: 30), snapshot(daysAgo: 0, freeGB: 40)]) == nil)
        #expect(Trends.fillDate([snapshot(daysAgo: 0.5, freeGB: 40), snapshot(daysAgo: 0, freeGB: 30)]) == nil)
    }

    @Test func insightsNameWhatGrew() {
        var scan = ExampleData.scan()
        scan.findings = scan.findings.filter { $0.id == "npm.cache" || $0.id == "chrome.cache" }
        let previous = snapshot(daysAgo: 7, freeGB: 40, sizes: ["npm.cache": 2 * gb, "chrome.cache": scan.findings.first { $0.id == "chrome.cache" }!.bytes])
        let insights = Trends.insights(current: scan, previous: previous)
        #expect(insights.map(\.id) == ["grew:npm.cache"])
    }
}

@Suite struct DiscoveryTests {
    @Test func helpersOfInstalledAppsAreNotLeftovers() {
        let discoveries = Discoveries(home: URL(filePath: "/tmp"), installedBundleIDs: ["com.google.Chrome"])
        #expect(discoveries.isInstalled("com.google.Chrome.helper"))
        #expect(discoveries.isInstalled("com.google.chrome"))
        #expect(!discoveries.isInstalled("com.google.Keystone"))
    }

    @Test func recognizesBundleIDFolderNames() {
        #expect(Discoveries.looksLikeBundleID("com.tinyspeck.slackmacgap"))
        #expect(!Discoveries.looksLikeBundleID("Google"))
        #expect(!Discoveries.looksLikeBundleID("CrashReporter"))
    }

    @Test func recentlyUsedFoldersAreNotCalledLeftovers() {
        let discoveries = Discoveries(home: URL(filePath: "/tmp"), installedBundleIDs: [])
        let folder = Discoveries.AppFolder(url: URL(filePath: "/tmp/x"), bundleID: "com.example.gone", kind: .supportData)
        let stale = Measurement(bytes: 200_000_000, newest: .now.addingTimeInterval(-90 * 86400))
        let recent = Measurement(bytes: 200_000_000, newest: .now.addingTimeInterval(-86400))
        #expect(discoveries.finding(for: folder, measurement: stale, appName: nil)?.consequence == .leftover)
        #expect(discoveries.finding(for: folder, measurement: recent, appName: nil) == nil)
    }

    @Test func readsDeviceBackupInfo() throws {
        let box = try Sandbox()
        let folder = box.root.appending(path: "Library/Application Support/MobileSync/Backup/abc123")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let info: NSDictionary = ["Device Name": "Sam's iPhone", "Product Name": "iPhone 11",
                                  "Last Backup Date": Date(timeIntervalSince1970: 1_700_000_000)]
        try info.write(to: folder.appending(path: "Info.plist"))
        let backups = Discoveries(home: box.root, installedBundleIDs: []).deviceBackups()
        #expect(backups.map(\.0.title) == ["Sam's iPhone backup"])
        #expect(backups[0].0.consequence == .irreplaceable)
        #expect(backups[0].0.warning != nil)
    }
}
