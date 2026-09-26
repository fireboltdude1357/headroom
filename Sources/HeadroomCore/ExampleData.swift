import Foundation

/// A made-up Mac used by the "Try example data" mode and for screenshots.
/// Paths point into a folder that doesn't exist, so cleanup here only moves nothing.
public enum ExampleData {
    static let home = URL(filePath: "/Example/Users/sam")
    static let gb: Int64 = 1_000_000_000

    public static func scan(now: Date = .now) -> ScanResult {
        func catalog(_ id: String, _ gigabytes: Double, daysAgo: Double = 1) -> Finding? {
            guard let source = Catalog.sources.first(where: { $0.id == id }) else { return nil }
            return Finding(id: source.id, title: source.title, owner: source.owner, category: source.category,
                           consequence: source.consequence, explanation: source.explanation, warning: source.warning,
                           settingsHint: source.settingsHint, paths: source.resolvedPaths(home: home),
                           bytes: Int64(gigabytes * Double(gb)), lastModified: now.addingTimeInterval(-daysAgo * 86400),
                           blockingBundleIDs: source.blockingBundleIDs)
        }
        func project(_ name: String, _ folder: String, _ ecosystem: String, _ marker: String, _ gigabytes: Double, monthsAgo: Double) -> Finding {
            let root = home.appending(path: "code/\(name)")
            let worked = now.addingTimeInterval(-monthsAgo * 30 * 86400)
            return Finding(id: "project:\(root.path)/\(folder)", title: "\(name)/\(folder)", owner: ecosystem,
                           category: .projects, consequence: .rebuilds,
                           explanation: "Generated \(ecosystem) output confirmed by \(marker). Your source code stays.",
                           detail: "~/code/\(name) · last worked " + relativePhrase(worked, now: now),
                           paths: [root.appending(path: folder)], bytes: Int64(gigabytes * Double(gb)), lastModified: worked,
                           verificationMarkers: [root.appending(path: marker)], isUntouched: monthsAgo >= 3)
        }
        func backup(_ device: String, _ product: String, _ gigabytes: Double, daysAgo: Double) -> Finding {
            let date = now.addingTimeInterval(-daysAgo * 86400)
            return Finding(id: "backup:\(device)", title: "\(device) backup", owner: "Finder", category: .devices,
                           consequence: .irreplaceable,
                           explanation: "A full local backup of this device, made by Finder.",
                           detail: "\(product) · Last backup " + date.formatted(date: .abbreviated, time: .omitted),
                           warning: "If this is the device's only backup, you won't be able to restore it after the backup is deleted.",
                           paths: [home.appending(path: "Library/Application Support/MobileSync/Backup/\(device)")],
                           bytes: Int64(gigabytes * Double(gb)), lastModified: date)
        }

        let findings: [Finding] = [
            catalog("xcode.deriveddata", 38.4), catalog("xcode.devicesupport", 21.7, daysAgo: 40),
            catalog("xcode.archives", 6.2, daysAgo: 90), catalog("simulator.devices", 24.9),
            catalog("simulator.caches", 4.1), catalog("npm.cache", 9.8), catalog("pnpm.store", 7.3),
            catalog("cargo.registry", 3.2, daysAgo: 60), catalog("homebrew.cache", 2.6), catalog("docker.data", 32.0),
            catalog("ollama.models", 14.5, daysAgo: 20), catalog("chrome.cache", 3.9), catalog("slack.cache", 2.2),
            catalog("vscode.cache", 1.4), catalog("spotify.cache", 3.1), catalog("photos.library", 61.3),
            catalog("messages.attachments", 18.7), catalog("mail.data", 7.9), catalog("icloud.drive", 22.4),
            catalog("system.logs", 1.1), catalog("devices.iphoneupdates", 6.8, daysAgo: 200),
            project("storefront", "node_modules", "Node.js", "package.json", 1.9, monthsAgo: 0.2),
            project("storefront", ".next", "Next.js", "next.config.ts", 0.9, monthsAgo: 0.2),
            project("thesis-analysis", ".venv", "Python", "pyproject.toml", 2.8, monthsAgo: 7),
            project("raytracer", "target", "Rust", "Cargo.toml", 5.4, monthsAgo: 11),
            project("hackathon-2025", "node_modules", "Node.js", "package.json", 1.2, monthsAgo: 9),
            project("WeatherKitDemo", ".build", "Swift", "Package.swift", 1.6, monthsAgo: 5),
            backup("Sam's iPhone 11", "iPhone 11", 41.8, daysAgo: 610),
            backup("Sam's iPhone 16", "iPhone 16", 63.2, daysAgo: 3),
            Finding(id: "download:Docker.dmg", title: "Docker.dmg", owner: "Downloads", category: .downloads,
                    consequence: .redownload, explanation: "An installer you downloaded. Apps installed from it keep working after it's gone.",
                    detail: "Downloaded 4 months ago", paths: [home.appending(path: "Downloads/Docker.dmg")],
                    bytes: Int64(0.62 * Double(gb))),
            Finding(id: "leftover:supportData:com.adobe.Premiere", title: "com.adobe.Premiere", owner: "Deleted app",
                    category: .leftovers, consequence: .leftover,
                    explanation: "The app data of an app that is no longer installed. Moving an app to the Trash leaves this behind.",
                    detail: "Last changed 8 months ago",
                    warning: "If you reinstall this app, its settings and saved data will be gone.",
                    paths: [home.appending(path: "Library/Application Support/com.adobe.Premiere")], bytes: Int64(4.4 * Double(gb))),
        ].compactMap { $0 }

        return ScanResult(date: now, volume: VolumeInfo(totalBytes: 494 * gb, freeBytes: Int64(27.2 * Double(gb))),
                          findings: findings.sorted { $0.bytes > $1.bytes }, unreadable: [], hasFullDiskAccess: true)
    }

    /// Four weekly snapshots with free space falling, so the trend line has something to fit.
    public static func history(now: Date = .now) -> [Snapshot] {
        let current = scan(now: now)
        return (1...4).reversed().map { weeksAgo in
            var sizes = Snapshot(current).sizes
            sizes["xcode.deriveddata"] = Int64(Double(sizes["xcode.deriveddata"] ?? 0) * (1 - 0.12 * Double(weeksAgo)))
            sizes["npm.cache"] = Int64(Double(sizes["npm.cache"] ?? 0) * (1 - 0.2 * Double(weeksAgo)))
            let free = Int64((27.2 + 6.2 * Double(weeksAgo)) * Double(gb))
            return Snapshot(date: now.addingTimeInterval(-Double(weeksAgo) * 7 * 86400),
                            volume: VolumeInfo(totalBytes: 494 * gb, freeBytes: free), sizes: sizes)
        }
    }
}
