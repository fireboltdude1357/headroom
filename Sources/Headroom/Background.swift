import AppKit
import HeadroomCore
import ServiceManagement
import UserNotifications

/// Preference keys shared by Settings, the menu bar panel and the background scheduler.
enum Prefs {
    static let weeklyCheck = "weeklyCheck"
    static let lowSpaceAlert = "lowSpaceAlert"
    static let lastLowSpaceAlert = "lastLowSpaceAlert"

    static func register() {
        UserDefaults.standard.register(defaults: [weeklyCheck: false, lowSpaceAlert: true])
    }
}

/// Weekly rescans, the login item and the low space notification.
/// Notification and login item calls only happen inside a real bundle; they crash under `swift run`.
@MainActor
final class BackgroundTasks {
    private var scheduler: NSBackgroundActivityScheduler?
    /// Set by the app so the scheduler can start a scan.
    var runScan: (@MainActor () async -> Void)?

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Starts or stops the weekly scan and login item to match the current preferences.
    func refresh() {
        let weekly = UserDefaults.standard.bool(forKey: Prefs.weeklyCheck)
        if weekly, scheduler == nil {
            let scheduler = NSBackgroundActivityScheduler(identifier: "headroom.weekly-check")
            scheduler.repeats = true
            scheduler.interval = 7 * 24 * 3600
            scheduler.tolerance = 24 * 3600
            scheduler.qualityOfService = .utility
            scheduler.schedule { completion in
                Task { @MainActor in
                    await self.runScan?()
                    completion(.finished)
                }
            }
            self.scheduler = scheduler
        } else if !weekly {
            scheduler?.invalidate()
            scheduler = nil
        }
        guard isBundled else { return }
        if weekly { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }

    /// Posts "Only 21 GB is free" when under 10%, at most once a day.
    func afterScan(_ volume: VolumeInfo) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.lowSpaceAlert), volume.freeFraction < 0.10, isBundled else { return }
        let last = defaults.double(forKey: Prefs.lastLowSpaceAlert)
        guard Date.now.timeIntervalSince1970 - last > 24 * 3600 else { return }
        defaults.set(Date.now.timeIntervalSince1970, forKey: Prefs.lastLowSpaceAlert)

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Only \(volume.freeBytes.formattedBytes) is free"
        content.body = "Open Headroom to see what's taking up space."
        let request = UNNotificationRequest(identifier: "headroom.low-space", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }
}
