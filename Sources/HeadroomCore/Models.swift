import Foundation

/// What happens if a finding is moved to the Trash. The cleanup plan groups items by this.
public enum Consequence: String, Codable, Sendable, CaseIterable, Comparable {
    /// Caches and build output. The owning app or tool recreates them.
    case rebuilds
    /// Installers, models, SDK images. Gone until you download them again.
    case redownload
    /// Data from an app that is no longer installed.
    case leftover
    /// Backups, archives and other data nothing can recreate.
    case irreplaceable
    /// Photos, Mail, Messages, iCloud. Headroom never selects these and points to the app's own setting.
    case appManaged

    public var label: String {
        switch self {
        case .rebuilds: "Rebuildable"
        case .redownload: "Can be downloaded again"
        case .leftover: "Left behind by a deleted app"
        case .irreplaceable: "Personal data"
        case .appManaged: "Managed by its app"
        }
    }

    public var isSelectable: Bool { self != .appManaged }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Where a finding shows up in the app's sidebar.
public enum FindingCategory: String, Codable, Sendable, CaseIterable {
    case developer, appCaches, appData, system, projects, devices, downloads, leftovers

    public var label: String {
        switch self {
        case .developer: "Developer tools"
        case .appCaches: "App caches"
        case .appData: "App data"
        case .system: "System"
        case .projects: "Project build folders"
        case .devices: "iPhone and iPad"
        case .downloads: "Old downloads"
        case .leftovers: "Deleted-app leftovers"
        }
    }

    public var symbol: String {
        switch self {
        case .developer: "hammer"
        case .appCaches: "square.stack.3d.up"
        case .appData: "photo.on.rectangle"
        case .system: "gearshape"
        case .projects: "folder.badge.gearshape"
        case .devices: "iphone"
        case .downloads: "arrow.down.circle"
        case .leftovers: "shippingbox"
        }
    }
}

/// One named thing taking up space, such as "npm cache" or "my-app/node_modules".
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    /// Stable across scans so history can compare sizes. Catalog sources use their catalog id.
    public var id: String
    public var title: String
    /// The app or tool that created it ("Xcode", "Google Chrome").
    public var owner: String
    public var category: FindingCategory
    public var consequence: Consequence
    /// What it is and what clearing it does.
    public var explanation: String
    /// Extra context such as "Last backup Mar 3, 2025".
    public var detail: String?
    /// Shown in the cleanup plan before the user confirms.
    public var warning: String?
    /// For app-managed data, where to go instead.
    public var settingsHint: String?
    public var paths: [URL]
    public var bytes: Int64
    public var lastModified: Date?
    /// Headroom skips this item while any of these apps is running.
    public var blockingBundleIDs: [String]
    /// Files that must still exist right before trashing, like a project's package.json.
    public var verificationMarkers: [URL]
    /// Projects nobody has edited in months.
    public var isUntouched: Bool

    public init(
        id: String, title: String, owner: String, category: FindingCategory, consequence: Consequence,
        explanation: String, detail: String? = nil, warning: String? = nil, settingsHint: String? = nil,
        paths: [URL], bytes: Int64, lastModified: Date? = nil, blockingBundleIDs: [String] = [],
        verificationMarkers: [URL] = [], isUntouched: Bool = false
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.category = category
        self.consequence = consequence
        self.explanation = explanation
        self.detail = detail
        self.warning = warning
        self.settingsHint = settingsHint
        self.paths = paths
        self.bytes = bytes
        self.lastModified = lastModified
        self.blockingBundleIDs = blockingBundleIDs
        self.verificationMarkers = verificationMarkers
        self.isUntouched = isUntouched
    }
}

public struct VolumeInfo: Codable, Sendable, Hashable {
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var usedBytes: Int64 { totalBytes - freeBytes }
    public var freeFraction: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) : 0 }

    public init(totalBytes: Int64, freeBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
    }

    /// Reads the startup volume. "Important usage" matches the free figure Finder shows,
    /// which counts purgeable space as available.
    public static func current(for url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeInfo(totalBytes: Int64(total), freeBytes: free)
    }
}

public struct ScanResult: Codable, Sendable {
    public var date: Date
    public var volume: VolumeInfo
    public var findings: [Finding]
    /// Locations Headroom tried and could not read, usually for lack of Full Disk Access.
    public var unreadable: [URL]
    public var hasFullDiskAccess: Bool

    public init(date: Date, volume: VolumeInfo, findings: [Finding], unreadable: [URL], hasFullDiskAccess: Bool) {
        self.date = date
        self.volume = volume
        self.findings = findings
        self.unreadable = unreadable
        self.hasFullDiskAccess = hasFullDiskAccess
    }

    public var totalBytes: Int64 { findings.reduce(0) { $0 + $1.bytes } }

    public func findings(in category: FindingCategory) -> [Finding] {
        findings.filter { $0.category == category }.sorted { $0.bytes > $1.bytes }
    }
}

extension Int64 {
    /// "4.2 GB", using the same decimal units as Finder.
    public var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

/// "now", "yesterday", "3 months ago".
func relativePhrase(_ date: Date, now: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.dateTimeStyle = .named
    return formatter.localizedString(for: min(date, now), relativeTo: now)
}
