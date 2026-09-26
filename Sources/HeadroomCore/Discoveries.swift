import Foundation

/// Findings that come from inspecting folders rather than a fixed catalog path:
/// device backups, old installers in Downloads, per-app caches and deleted-app leftovers.
public struct Discoveries: Sendable {
    public var home: URL
    public var now = Date()
    /// Bundle IDs of installed apps. Anything matching one of these is not a leftover.
    public var installedBundleIDs: Set<String>
    /// Asks LaunchServices whether an app with this bundle ID exists anywhere on the Mac.
    /// Catches apps outside the Applications folders that `installedBundleIDs` doesn't list.
    public var isRegisteredApp: @Sendable (String) -> Bool = { _ in false }
    /// Minimum size before an uncatalogued cache or leftover is worth listing.
    public var minimumBytes: Int64 = 50_000_000

    public init(home: URL, installedBundleIDs: Set<String>) {
        self.home = home
        self.installedBundleIDs = installedBundleIDs
    }

    // MARK: Device backups

    /// One finding per iPhone or iPad backup, named from its Info.plist.
    public func deviceBackups() -> [(Finding, URL)] {
        let root = home.appending(path: "Library/Application Support/MobileSync/Backup", directoryHint: .isDirectory)
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            let info = NSDictionary(contentsOf: folder.appending(path: "Info.plist")) as? [String: Any]
            let device = info?["Device Name"] as? String ?? info?["Display Name"] as? String ?? "Unknown device"
            let product = info?["Product Name"] as? String
            let lastBackup = info?["Last Backup Date"] as? Date ?? DiskMeasure.modificationDate(folder)
            var detail = product.map { "\($0) · " } ?? ""
            if let lastBackup {
                detail += "Last backup " + lastBackup.formatted(date: .abbreviated, time: .omitted)
            }
            let finding = Finding(
                id: "backup:" + folder.lastPathComponent,
                title: "\(device) backup",
                owner: "Finder",
                category: .devices,
                consequence: .irreplaceable,
                explanation: "A full local backup of this device, made by Finder. Restoring or setting up a replacement device can use it.",
                detail: detail,
                warning: "If this is the device's only backup, you won't be able to restore it after the backup is deleted. Check that the device backs up to iCloud first.",
                paths: [folder],
                bytes: 0,
                lastModified: lastBackup,
                verificationMarkers: [folder.appending(path: "Info.plist")]
            )
            return (finding, folder)
        }
    }

    // MARK: Downloads

    static let installerExtensions: Set<String> = ["dmg", "pkg", "xip", "ipsw"]

    /// Installers in Downloads older than two weeks. Once an app is installed its disk image is dead weight.
    public func oldInstallers(olderThan age: TimeInterval = 14 * 24 * 3600) -> [Finding] {
        let downloads = home.appending(path: "Downloads", directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { file in
            guard Self.installerExtensions.contains(file.pathExtension.lowercased()),
                  let v = try? file.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let modified = v.contentModificationDate, now.timeIntervalSince(modified) > age
            else { return nil }
            return Finding(
                id: "download:" + file.lastPathComponent,
                title: file.lastPathComponent,
                owner: "Downloads",
                category: .downloads,
                consequence: .redownload,
                explanation: "An installer you downloaded. Apps installed from it keep working after it's gone.",
                detail: "Downloaded " + relativePhrase(modified, now: now),
                warning: file.pathExtension.lowercased() == "dmg" ? "If \(file.lastPathComponent) is a disk image you made, not an installer, keep it." : nil,
                paths: [file],
                bytes: Int64(v.totalFileAllocatedSize ?? 0),
                lastModified: modified
            )
        }
    }

    // MARK: Per-app caches and leftovers

    public static func looksLikeBundleID(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+){2,}/) != nil
    }

    /// True when some installed app owns this bundle ID, either exactly or as its helper or extension
    /// ("com.google.Chrome.helper" belongs to "com.google.Chrome").
    public func isInstalled(_ bundleID: String) -> Bool {
        !owners(of: bundleID).isEmpty || isRegisteredApp(bundleID)
    }

    /// Installed apps this bundle ID belongs to: itself, the app it's a helper of, or its helpers.
    public func owners(of bundleID: String) -> [String] {
        let id = bundleID.lowercased()
        return installedBundleIDs.filter { installed in
            let other = installed.lowercased()
            return id == other || id.hasPrefix(other + ".") || other.hasPrefix(id + ".")
        }.sorted()
    }

    /// Folders under ~/Library named by bundle ID, split into caches of installed apps and
    /// leftovers of apps that are gone. `excluding` holds paths the catalog already covers.
    public struct AppFolder: Sendable {
        public var url: URL
        public var bundleID: String
        public var kind: Kind
        public enum Kind: Sendable { case cache, supportData, container }
    }

    public func appFolders(includeContainers: Bool) -> [AppFolder] {
        var result: [AppFolder] = []
        func scan(_ relative: String, _ kind: AppFolder.Kind) {
            let dir = home.appending(path: relative, directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where Self.looksLikeBundleID(name) && !name.lowercased().hasPrefix("com.apple.") {
                result.append(AppFolder(url: dir.appending(path: name, directoryHint: .isDirectory), bundleID: name, kind: kind))
            }
        }
        scan("Library/Caches", .cache)
        scan("Library/Application Support", .supportData)
        if includeContainers { scan("Library/Containers", .container) }
        return result
    }

    /// Turns a measured app folder into a finding, or nil if it's too small or recently used.
    public func finding(for folder: AppFolder, measurement: Measurement, appName: String?) -> Finding? {
        guard measurement.bytes >= minimumBytes else { return nil }
        let installed = isInstalled(folder.bundleID)
        if installed {
            // Only caches of installed apps are safe to clear; their support data is not ours to judge.
            guard folder.kind == .cache else { return nil }
            let name = appName ?? folder.bundleID
            return Finding(
                id: "cache:" + folder.bundleID,
                title: "\(name) cache",
                owner: name,
                category: .appCaches,
                consequence: .rebuilds,
                explanation: "Temporary files \(name) keeps to work faster. It recreates them as needed.",
                paths: [folder.url],
                bytes: measurement.bytes,
                lastModified: measurement.newest,
                // A helper's cache is in use whenever its main app runs.
                blockingBundleIDs: Array(Set([folder.bundleID] + owners(of: folder.bundleID))).sorted()
            )
        }
        // A partial measurement could hide recent writes, so don't call it abandoned.
        if measurement.incomplete { return nil }
        // An app that still writes here is probably installed somewhere we didn't look.
        if let newest = measurement.newest, now.timeIntervalSince(newest) < 30 * 24 * 3600 { return nil }
        let where_ = switch folder.kind {
        case .cache: "cache"
        case .supportData: "app data"
        case .container: "sandbox container"
        }
        return Finding(
            id: "leftover:\(folder.kind):" + folder.bundleID,
            title: folder.bundleID,
            owner: "Deleted app",
            category: .leftovers,
            consequence: .leftover,
            explanation: "The \(where_) of an app that is no longer installed. Moving an app to the Trash leaves this behind.",
            detail: measurement.newest.map { "Last changed " + relativePhrase($0, now: now) },
            warning: folder.kind == .cache ? nil : "If you reinstall this app, its settings and saved data will be gone.",
            paths: [folder.url],
            bytes: measurement.bytes,
            lastModified: measurement.newest,
            // Covers an app reinstalled and opened between the scan and the cleanup.
            blockingBundleIDs: [folder.bundleID]
        )
    }
}
