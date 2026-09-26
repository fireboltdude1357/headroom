import Foundation

/// A known location that apps and tools fill up. Paths are relative to the home folder.
public struct CatalogSource: Sendable {
    public var id: String
    public var title: String
    public var owner: String
    public var category: FindingCategory
    public var consequence: Consequence
    public var explanation: String
    public var paths: [String]
    public var blockingBundleIDs: [String] = []
    public var settingsHint: String?
    public var warning: String?

    public func resolvedPaths(home: URL) -> [URL] {
        paths.map { home.appending(path: $0, directoryHint: .isDirectory) }
    }
}

public enum Catalog {
    private static let xcode = ["com.apple.dt.Xcode"]
    private static let simulator = ["com.apple.iphonesimulator", "com.apple.dt.Xcode"]

    public static let sources: [CatalogSource] = [
        // Developer tools
        .init(id: "xcode.deriveddata", title: "Xcode build data", owner: "Xcode", category: .developer, consequence: .rebuilds,
              explanation: "Intermediate build products and indexes for every project Xcode has opened. The next build recreates what it needs, and the first build afterward is slower.",
              paths: ["Library/Developer/Xcode/DerivedData"], blockingBundleIDs: xcode),
        .init(id: "xcode.devicesupport", title: "Device support files", owner: "Xcode", category: .developer, consequence: .redownload,
              explanation: "Debug symbols copied from each iPhone or iPad you have connected, one folder per iOS version. Xcode copies them again the next time that device connects.",
              paths: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport"], blockingBundleIDs: xcode),
        .init(id: "xcode.archives", title: "App archives", owner: "Xcode", category: .developer, consequence: .irreplaceable,
              explanation: "Builds you archived for the App Store or TestFlight. They hold the debug symbols that make crash reports readable.",
              paths: ["Library/Developer/Xcode/Archives"], blockingBundleIDs: xcode,
              warning: "Crash reports from these builds can't be symbolicated after the archives are gone."),
        .init(id: "simulator.caches", title: "Simulator caches", owner: "Simulator", category: .developer, consequence: .rebuilds,
              explanation: "Shared caches for iOS simulators. Simulators rebuild them on next launch.",
              paths: ["Library/Developer/CoreSimulator/Caches"], blockingBundleIDs: simulator),
        .init(id: "simulator.devices", title: "Simulator devices", owner: "Simulator", category: .developer, consequence: .appManaged,
              explanation: "Each simulator's installed apps and data. Deleting folders by hand confuses Xcode, so use simctl instead.",
              paths: ["Library/Developer/CoreSimulator/Devices"],
              settingsHint: "Run `xcrun simctl delete unavailable` in Terminal, or delete simulators in Xcode > Window > Devices and Simulators."),
        .init(id: "npm.cache", title: "npm cache", owner: "npm", category: .developer, consequence: .rebuilds,
              explanation: "Every package npm has downloaded. The next install downloads what it needs again.",
              paths: [".npm/_cacache"]),
        .init(id: "pnpm.store", title: "pnpm store", owner: "pnpm", category: .developer, consequence: .rebuilds,
              explanation: "The shared package store pnpm links into projects. Projects re-fetch packages on the next install.",
              paths: ["Library/pnpm/store"]),
        .init(id: "yarn.cache", title: "Yarn cache", owner: "Yarn", category: .developer, consequence: .rebuilds,
              explanation: "Downloaded package archives. Yarn downloads them again when needed.",
              paths: ["Library/Caches/Yarn"]),
        .init(id: "bun.cache", title: "Bun cache", owner: "Bun", category: .developer, consequence: .rebuilds,
              explanation: "Packages Bun has installed before. The next install downloads them again.",
              paths: [".bun/install/cache"]),
        .init(id: "cargo.registry", title: "Cargo registry", owner: "Rust", category: .developer, consequence: .rebuilds,
              explanation: "Downloaded crate sources and the registry index. Cargo fetches them again on the next build.",
              paths: [".cargo/registry"]),
        .init(id: "go.buildcache", title: "Go build cache", owner: "Go", category: .developer, consequence: .rebuilds,
              explanation: "Compiled Go packages. The next build recompiles them.",
              paths: ["Library/Caches/go-build"]),
        .init(id: "gradle.caches", title: "Gradle caches", owner: "Gradle", category: .developer, consequence: .rebuilds,
              explanation: "Dependencies and build outputs shared by Gradle projects. The next build downloads and rebuilds them.",
              paths: [".gradle/caches"], blockingBundleIDs: ["com.google.android.studio"]),
        .init(id: "android.systemimages", title: "Android emulator images", owner: "Android Studio", category: .developer, consequence: .redownload,
              explanation: "System images for Android emulators. The SDK Manager downloads them again when an emulator needs one.",
              paths: ["Library/Android/sdk/system-images"], blockingBundleIDs: ["com.google.android.studio"]),
        .init(id: "cocoapods.cache", title: "CocoaPods cache", owner: "CocoaPods", category: .developer, consequence: .rebuilds,
              explanation: "Downloaded pod sources. `pod install` fetches them again.",
              paths: ["Library/Caches/CocoaPods"]),
        .init(id: "swiftpm.cache", title: "Swift package cache", owner: "Swift", category: .developer, consequence: .rebuilds,
              explanation: "Cloned Swift package repositories. Package resolution clones them again.",
              paths: ["Library/Caches/org.swift.swiftpm"], blockingBundleIDs: xcode),
        .init(id: "pip.cache", title: "pip cache", owner: "Python", category: .developer, consequence: .rebuilds,
              explanation: "Downloaded Python wheels. pip downloads them again when needed.",
              paths: ["Library/Caches/pip"]),
        .init(id: "homebrew.cache", title: "Homebrew downloads", owner: "Homebrew", category: .developer, consequence: .rebuilds,
              explanation: "Bottles and source archives Homebrew already installed. Only reinstalls need them.",
              paths: ["Library/Caches/Homebrew"]),
        .init(id: "playwright.browsers", title: "Playwright browsers", owner: "Playwright", category: .developer, consequence: .redownload,
              explanation: "Browser builds for automated tests. `npx playwright install` downloads them again.",
              paths: ["Library/Caches/ms-playwright"]),
        .init(id: "huggingface.cache", title: "Hugging Face models", owner: "Hugging Face", category: .developer, consequence: .redownload,
              explanation: "Model weights and datasets downloaded by Python libraries. They download again on next use.",
              paths: [".cache/huggingface"]),
        .init(id: "ollama.models", title: "Ollama models", owner: "Ollama", category: .developer, consequence: .redownload,
              explanation: "Local language models. `ollama pull` downloads them again.",
              paths: [".ollama/models"], blockingBundleIDs: ["com.electron.ollama"]),
        .init(id: "docker.data", title: "Docker disk image", owner: "Docker", category: .developer, consequence: .appManaged,
              explanation: "One large file holding every image, container and volume. Docker has to shrink it itself.",
              paths: ["Library/Containers/com.docker.docker/Data"],
              settingsHint: "Run `docker system prune` or lower the disk limit in Docker Desktop > Settings > Resources."),

        // App caches
        .init(id: "chrome.cache", title: "Chrome cache", owner: "Google Chrome", category: .appCaches, consequence: .rebuilds,
              explanation: "Saved copies of websites. Pages load a little slower until Chrome caches them again. You stay signed in.",
              paths: ["Library/Caches/Google/Chrome"], blockingBundleIDs: ["com.google.Chrome"]),
        .init(id: "safari.cache", title: "Safari cache", owner: "Safari", category: .appCaches, consequence: .rebuilds,
              explanation: "Saved copies of websites. Safari caches pages again as you browse.",
              paths: ["Library/Caches/com.apple.Safari"], blockingBundleIDs: ["com.apple.Safari"]),
        .init(id: "firefox.cache", title: "Firefox cache", owner: "Firefox", category: .appCaches, consequence: .rebuilds,
              explanation: "Saved copies of websites. Firefox caches pages again as you browse.",
              paths: ["Library/Caches/Firefox"], blockingBundleIDs: ["org.mozilla.firefox"]),
        .init(id: "slack.cache", title: "Slack cache", owner: "Slack", category: .appCaches, consequence: .rebuilds,
              explanation: "Images and files Slack has shown you. Slack downloads them again when you scroll back.",
              paths: ["Library/Application Support/Slack/Cache", "Library/Application Support/Slack/Service Worker/CacheStorage",
                      "Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack/Cache"],
              blockingBundleIDs: ["com.tinyspeck.slackmacgap"]),
        .init(id: "discord.cache", title: "Discord cache", owner: "Discord", category: .appCaches, consequence: .rebuilds,
              explanation: "Images and media Discord has loaded. It loads them again when needed.",
              paths: ["Library/Application Support/discord/Cache"], blockingBundleIDs: ["com.hnc.Discord"]),
        .init(id: "vscode.cache", title: "VS Code caches", owner: "Visual Studio Code", category: .appCaches, consequence: .rebuilds,
              explanation: "Compiled code and downloaded extension packages. VS Code recreates them on launch.",
              paths: ["Library/Application Support/Code/Cache", "Library/Application Support/Code/CachedData",
                      "Library/Application Support/Code/CachedExtensionVSIXs"],
              blockingBundleIDs: ["com.microsoft.VSCode"]),
        .init(id: "spotify.cache", title: "Spotify cache", owner: "Spotify", category: .appCaches, consequence: .rebuilds,
              explanation: "Streamed songs kept for quick replay. Downloaded playlists live elsewhere and stay.",
              paths: ["Library/Caches/com.spotify.client"], blockingBundleIDs: ["com.spotify.client"]),

        // App data
        .init(id: "photos.library", title: "Photos library", owner: "Photos", category: .appData, consequence: .appManaged,
              explanation: "Your photos and videos. Only Photos should change this library.",
              paths: ["Pictures/Photos Library.photoslibrary"],
              settingsHint: "In Photos > Settings > iCloud, choose Optimize Mac Storage."),
        .init(id: "messages.attachments", title: "Messages attachments", owner: "Messages", category: .appData, consequence: .appManaged,
              explanation: "Photos, videos and files from your conversations.",
              paths: ["Library/Messages/Attachments"],
              settingsHint: "Open System Settings > General > Storage and review Messages, or turn on Messages in iCloud."),
        .init(id: "mail.data", title: "Mail downloads", owner: "Mail", category: .appData, consequence: .appManaged,
              explanation: "Downloaded messages and attachments for your mail accounts.",
              paths: ["Library/Mail"],
              settingsHint: "In Mail > Settings > Accounts, turn off Download Attachments or remove old accounts."),
        .init(id: "icloud.drive", title: "iCloud Drive", owner: "iCloud", category: .appData, consequence: .appManaged,
              explanation: "Files synced from iCloud Drive that are kept on this Mac.",
              paths: ["Library/Mobile Documents"],
              settingsHint: "Open System Settings > Apple Account > iCloud > Drive and turn on Optimize Mac Storage."),

        // System
        .init(id: "system.logs", title: "Logs", owner: "macOS and apps", category: .system, consequence: .rebuilds,
              explanation: "Diagnostic logs written by apps. They are only useful when troubleshooting.",
              paths: ["Library/Logs"]),
        .init(id: "system.trash", title: "Trash", owner: "Finder", category: .system, consequence: .appManaged,
              explanation: "Items already in the Trash still use space until you empty it.",
              paths: [".Trash"], settingsHint: "Empty the Trash in Finder once you are sure."),

        // Devices
        .init(id: "devices.iphoneupdates", title: "iPhone update files", owner: "Finder", category: .devices, consequence: .redownload,
              explanation: "iOS installers saved when you updated an iPhone through this Mac. Finder downloads a fresh one next time.",
              paths: ["Library/iTunes/iPhone Software Updates"]),
        .init(id: "devices.ipadupdates", title: "iPad update files", owner: "Finder", category: .devices, consequence: .redownload,
              explanation: "iPadOS installers saved when you updated an iPad through this Mac. Finder downloads a fresh one next time.",
              paths: ["Library/iTunes/iPad Software Updates"]),
    ]

    /// Locations macOS hides from apps without Full Disk Access. Headroom skips them rather than trigger
    /// a permission prompt for every sandboxed app.
    public static let protectedPrefixes = [
        "Library/Containers", "Library/Group Containers", "Library/Mail", "Library/Messages",
        "Library/Safari", "Library/Application Support/MobileSync",
    ]

    /// True for app-managed locations such as the Photos library, or any folder that contains one.
    /// Cleanup refuses these even if a finding somehow points at them.
    public static func isProtected(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        sources.lazy.filter { $0.consequence == .appManaged }
            .flatMap { $0.resolvedPaths(home: home) }
            .contains { DiskMeasure.overlaps($0, url) }
    }

    public static func needsFullDiskAccess(_ relativePath: String) -> Bool {
        protectedPrefixes.contains { relativePath.hasPrefix($0) }
    }
}
