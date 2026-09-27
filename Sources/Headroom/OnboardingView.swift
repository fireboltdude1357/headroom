import AppKit
import SwiftUI

/// First launch: a welcome, then one Full Disk Access step so macOS never asks folder by folder.
/// Shown in place of the main window until the user scans or skips.
struct OnboardingView: View {
    enum Step { case welcome, access }

    @Environment(AppModel.self) private var model
    @State private var step: Step

    /// Starts on the access step when access is already on, which is where a Quit & Reopen lands.
    init(step: Step? = nil, hasFullDiskAccess: Bool) {
        _step = State(initialValue: step ?? (hasFullDiskAccess ? .access : .welcome))
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .access: access
                }
            }
            // A fixed column width gives the wrapping text a real width when the window measures
            // its content. Without it the text is measured one word per line and the window grows
            // taller than the screen.
            .frame(width: 520)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckFullDiskAccess()
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to Headroom").font(.largeTitle.weight(.semibold))
            Text("Headroom measures caches, build folders, old backups and leftovers, then explains what each one is before you move anything to the Trash.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue") { step = .access }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: model.hasFullDiskAccess ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(model.hasFullDiskAccess ? .green : .secondary)
            Text("Allow Full Disk Access").font(.largeTitle.weight(.semibold))
            Text("macOS asks separately before an app reads Desktop, Documents, Downloads, iCloud Drive, Photos or another app's data. Full Disk Access is one switch that covers all of them, so you won't see those prompts. Headroom only measures sizes and never moves anything without asking you first.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasFullDiskAccess {
                Label("Full Disk Access is on.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    StepRow(number: 1, text: "Click Open System Settings.")
                    StepRow(number: 2, text: "Turn on Headroom in the list. If it isn't there, click + and choose Headroom from Applications.")
                    StepRow(number: 3, text: "If macOS offers to quit and reopen Headroom, choose Quit & Reopen. You'll come back to this step.")
                }
            }

            HStack {
                if model.hasFullDiskAccess {
                    Button("Scan this Mac") { model.finishOnboarding(scan: true) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") { FullDiskAccess.openSettings() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                    Button("Continue without it") { model.finishOnboarding(scan: false) }
                        .help("Headroom skips the protected folders. You can turn on access later.")
                }
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
    }
}

private struct StepRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
