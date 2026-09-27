import AppKit
import HeadroomCore
import Observation
import ServiceManagement
import UserNotifications

/// Preference keys shared by Settings, the menu bar panel and the background scheduler.
enum Prefs {
    static let weeklyCheck = "weeklyCheck"
    static let lowSpaceAlert = "lowSpaceAlert"
    static let lastLowSpaceAlert = "lastLowSpaceAlert"
    static let onboarded = "onboarded"

    static func register() {
        UserDefaults.standard.register(defaults: [weeklyCheck: false, lowSpaceAlert: true])
    }
}

/// Weekly rescans, the login item, the hourly free-space check and the low space notification.
/// Notification and login item calls only happen inside a real bundle; they crash under `swift run`.
@Observable @MainActor
final class BackgroundTasks {
    private var scheduler: NSBackgroundActivityScheduler?
    private var hourlyCheck: Task<Void, Never>?
    /// Set by the app so the scheduler can start a scan.
    @ObservationIgnored var runScan: (@MainActor () async -> Void)?
    /// One line for Settings and the menu panel when the login item needs the user's help.
    var loginItemNotice: String?

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// Starts or stops the weekly scan, login item and hourly check to match the current preferences.
    func refresh() {
        let defaults = UserDefaults.standard
        let weekly = defaults.bool(forKey: Prefs.weeklyCheck)
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
        refreshLoginItem(enabled: weekly)

        let alert = defaults.bool(forKey: Prefs.lowSpaceAlert)
        if alert, hourlyCheck == nil {
            hourlyCheck = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                    guard !Task.isCancelled, let volume = VolumeInfo.current() else { continue }
                    self?.afterScan(volume)
                }
            }
        } else if !alert {
            hourlyCheck?.cancel()
            hourlyCheck = nil
        }
    }

    private func refreshLoginItem(enabled: Bool) {
        guard isBundled else { return }
        let service = SMAppService.mainApp
        guard enabled else {
            try? service.unregister()
            loginItemNotice = nil
            return
        }
        do {
            try service.register()
        } catch {
            loginItemNotice = "Headroom couldn't register as a login item: \(error.localizedDescription)"
            return
        }
        loginItemNotice = service.status == .requiresApproval
            ? "Allow Headroom in System Settings > General > Login Items so the weekly check can run."
            : nil
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Posts "Only 21 GB is free" when under 10%, at most once a day.
    func afterScan(_ volume: VolumeInfo) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.lowSpaceAlert), volume.freeFraction < 0.10, isBundled else { return }
        let last = defaults.double(forKey: Prefs.lastLowSpaceAlert)
        guard Date.now.timeIntervalSince1970 - last > 24 * 3600 else { return }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Only \(volume.freeBytes.formattedBytes) is free"
        content.body = "Open Headroom to see what's taking up space."
        let request = UNNotificationRequest(identifier: "headroom.low-space", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            do {
                try await center.add(request)
                defaults.set(Date.now.timeIntervalSince1970, forKey: Prefs.lastLowSpaceAlert)
            } catch {}
        }
    }
}
