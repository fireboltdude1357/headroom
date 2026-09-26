import Foundation

/// Size and newest modification date of a file tree.
public struct Measurement: Sendable {
    public var bytes: Int64 = 0
    public var newest: Date?
    /// False when the top-level location exists but could not be listed.
    public var readable = true
    /// True when some folder inside could not be read, so `bytes` and `newest` are lower bounds.
    public var incomplete = false
}

public enum DiskMeasure {
    /// Sums allocated blocks, which is what the files cost on disk. Uses fts because it hands back
    /// `stat` results without a second system call. Symlinks are not followed, and a file with
    /// several hard links inside the tree counts once (pnpm's node_modules are mostly hard links).
    public static func measure(_ url: URL) -> Measurement {
        var result = Measurement()
        var seenLinks = Set<UInt64>()
        let path = strdup(url.path)
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return result }
        defer { fts_close(fts) }
        while let entry = fts_read(fts) {
            if Task.isCancelled { result.incomplete = true; break }
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_DNR, FTS_ERR:
                // fts reports an unreadable folder after visiting it, so check its level, not the order.
                if entry.pointee.fts_level == FTS_ROOTLEVEL { result.readable = false } else { result.incomplete = true }
            case FTS_DP:
                continue
            case FTS_NS, FTS_NSOK:
                result.incomplete = true
            default:
                guard let stat = entry.pointee.fts_statp?.pointee else { break }
                let modified = Date(timeIntervalSince1970: TimeInterval(stat.st_mtimespec.tv_sec))
                if modified > (result.newest ?? .distantPast) { result.newest = modified }
                if info == FTS_F, stat.st_nlink > 1, !seenLinks.insert(UInt64(stat.st_ino)).inserted { break }
                result.bytes += Int64(stat.st_blocks) * 512
            }
        }
        return result
    }

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The file's inode number, used to check that a Trash item is still the one Headroom moved.
    public static func fileNumber(_ url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.uint64Value
    }

    /// True if one path is the other or sits inside it.
    public static func overlaps(_ a: URL, _ b: URL) -> Bool {
        let a = a.standardizedFileURL.path, b = b.standardizedFileURL.path
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
}
