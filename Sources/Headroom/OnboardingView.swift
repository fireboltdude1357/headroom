import AppKit
import SwiftUI

/// First launch: one screen that asks for Full Disk Access, so macOS never asks folder by folder.
/// macOS doesn't let an app grant itself access, so the user flips one switch in System Settings.
/// Headroom notices within a second and starts the first scan without another click.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    /// Set after the user opens System Settings, to offer a restart if the switch doesn't register.
    @State private var openedSettings = false
    private let watchesAccess: Bool

    /// Snapshot mode renders the "turned it on?" hint and turns off the access check, which would
    /// otherwise start a real scan.
    init(openedSettings: Bool = false, watchesAccess: Bool = true) {
        _openedSettings = State(initialValue: openedSettings)
        self.watchesAccess = watchesAccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("Welcome to Headroom").font(.largeTitle.weight(.semibold))
            }
            Text("Headroom measures caches, build folders, old backups and leftovers, then explains each one before you move anything to the Trash.")
                .fixedSize(horizontal: false, vertical: true)
            Text("To see everything, it needs Full Disk Access. That one switch replaces the separate prompts macOS shows for Desktop, Documents, Downloads, iCloud Drive, Photos and other apps' data. Headroom only measures sizes, and never moves anything without asking you first.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "switch.2").foregroundStyle(.secondary)
                Text("In the list that opens, turn on **Headroom**. Headroom continues on its own once it's on.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Open System Settings") {
                    FullDiskAccess.openSettings()
                    openedSettings = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Continue without it") { model.finishOnboarding(scan: false) }
                    .help("Headroom skips the protected folders. You can turn on access later.")
            }
            .controlSize(.large)

            if openedSettings {
                HStack(spacing: 6) {
                    Text("Already turned it on? macOS sometimes applies it only after a restart.")
                        .foregroundStyle(.secondary)
                    Button("Restart Headroom") { FullDiskAccess.relaunch() }
                        .buttonStyle(.link)
                }
                .font(.callout)
            }
        }
        // A fixed column width gives the wrapping text a real width when the window measures its
        // content. Without it the text is measured one word per line and the window grows taller
        // than the screen.
        .frame(width: 520)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 640, minHeight: 520)
        // Polls once a second while this screen is up; opening one file is cheap and nothing redraws
        // until the answer changes.
        .task {
            while watchesAccess && !Task.isCancelled {
                model.recheckFullDiskAccess()
                if model.hasFullDiskAccess {
                    model.finishOnboarding(scan: true)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
