import HeadroomCore
import SwiftUI

/// The menu bar panel: free space, trend, up to three insights and the background toggles.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.weeklyCheck) private var weeklyCheck = false
    @AppStorage(Prefs.lowSpaceAlert) private var lowSpaceAlert = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let scan = model.scan {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(scan.volume.freeBytes.formattedBytes) free")
                            .font(.title3.weight(.semibold))
                        Text("of \(scan.volume.totalBytes.formattedBytes)").foregroundStyle(.secondary)
                    }
                    UsageBar(volume: scan.volume).frame(height: 8).padding(.vertical, 2)
                    if let change = model.freeChange, let previous = model.previousSnapshot {
                        Text(freeChangePhrase(change, since: previous.date))
                    }
                    switch model.trend {
                    case let .full(date): Text("At this rate, your disk is full \(fillPhrase(date)).")
                    case .notShrinking: Text("Free space isn't shrinking.")
                    case .notEnoughHistory: Text("Not enough history yet to see a trend.")
                    }
                }
                .font(.callout)
                .monospacedDigit()

                if !model.insights.isEmpty {
                    Divider()
                    Text("Worth a look").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(model.insights) { insight in
                        HStack(alignment: .firstTextBaseline) {
                            Text(insight.message).font(.callout)
                            Spacer(minLength: 8)
                            Button(insight.action.buttonTitle) { open(insight.action) }.controlSize(.small)
                        }
                    }
                }
            } else {
                Text("No scan yet").foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button(model.isScanning ? (model.scanProgress ?? "Scanning") : "Scan now") {
                    Task { await model.runScan() }
                }
                .disabled(model.isBusy)
                Spacer()
            }

            Toggle("Weekly check", isOn: $weeklyCheck)
            Toggle("Low space alert (under 10%)", isOn: $lowSpaceAlert)
            if let notice = model.background.loginItemNotice {
                LoginItemNotice(notice: notice)
            }

            Divider()

            HStack {
                Button("Open Headroom") { open(nil) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: 320)
        .onChange(of: weeklyCheck) { model.background.refresh() }
        .onChange(of: lowSpaceAlert) { model.background.refresh() }
    }

    private func open(_ action: Insight.Action?) {
        if let action { model.perform(action) }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Settings scene: the same toggles as the menu bar plus a note about how sizes are measured.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.weeklyCheck) private var weeklyCheck = false
    @AppStorage(Prefs.lowSpaceAlert) private var lowSpaceAlert = true

    var body: some View {
        Form {
            Section {
                Toggle("Check for space to reclaim every week", isOn: $weeklyCheck)
                Text("Turning this on also opens Headroom at login so the check can run.")
                    .font(.callout).foregroundStyle(.secondary)
                if let notice = model.background.loginItemNotice {
                    LoginItemNotice(notice: notice)
                }
                Toggle("Notify me when free space is under 10%", isOn: $lowSpaceAlert)
            }
            Section("About") {
                Text("Headroom measures files itself, so totals won't match Apple's Storage settings. Everything it removes goes to the Trash first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onChange(of: weeklyCheck) { model.background.refresh() }
        .onChange(of: lowSpaceAlert) { model.background.refresh() }
    }
}

/// Shown when macOS wants the user to approve the login item, or registration failed.
struct LoginItemNotice: View {
    @Environment(AppModel.self) private var model
    var notice: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Button("Open Login Items") { model.background.openLoginItemsSettings() }
        }
        .font(.callout)
    }
}

extension Insight.Action {
    var buttonTitle: String {
        switch self {
        case .review: "Review"
        case .selectUntouchedProjects: "Select untouched"
        }
    }
}
