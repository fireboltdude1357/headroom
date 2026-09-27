import HeadroomCore
import SwiftUI

/// Entry point. `Headroom --snapshot <dir>` renders every screen to PNGs and exits instead of running the app.
@main
enum Entry {
    static func main() {
        Prefs.register()
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated {
                SnapshotRenderer.run(outputDir: URL(filePath: arguments[index + 1]))
            }
            exit(0)
        }
        HeadroomApp.main()
    }
}

struct HeadroomApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Headroom", id: "main") {
            Group {
                if model.showOnboarding {
                    OnboardingView(hasFullDiskAccess: model.hasFullDiskAccess)
                } else {
                    ContentView()
                }
            }
            .environment(model)
            .onAppear {
                model.background.runScan = { await model.runScan() }
                model.background.refresh()
            }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan") { Task { await model.runScan() } }
                    .keyboardShortcut("n")
                    .disabled(model.isBusy)
                Button("Rescan") { Task { await model.runScan() } }
                    .keyboardShortcut("r")
                    .disabled(model.isBusy || model.scan == nil)
                Button("Export…") { model.exportCSV() }
                    .keyboardShortcut("e")
                    .disabled(model.scan == nil)
                Divider()
                Button(model.isExample ? "Leave example data" : "Try example data") {
                    if model.isExample { model.leaveExample() } else { model.loadExample() }
                }
                .disabled(model.isBusy)
            }
        }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra("Headroom", systemImage: "internaldrive") {
            MenuBarView().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Sidebar plus the selected screen, with the selection bar and cleanup sheets.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.isExample { ExampleBanner() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !model.selected.isEmpty { SelectionBar() }
                }
        }
        .navigationTitle("Headroom")
        .toolbar { ScanToolbar() }
        .sheet(isPresented: $model.showReview) { ReviewSheet().environment(model) }
        .sheet(item: $model.summary) { summary in ResultSheet(summary: summary).environment(model) }
    }

    /// Trash comes first so it still works with no scan loaded.
    @ViewBuilder private var detail: some View {
        switch model.sidebar ?? .overview {
        case .trash: TrashView()
        case _ where model.scan == nil: EmptyState()
        case .overview: OverviewView()
        case let .category(category): CategoryView(category: category).id(category)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Label("Overview", systemImage: "internaldrive").tag(SidebarItem.overview)
            if !model.categories.isEmpty {
                Section("Found") {
                    ForEach(model.categories, id: \.self) { category in
                        let findings = model.findings(in: category)
                        HStack {
                            Label(category.label, systemImage: category.symbol).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(findings.reduce(0) { $0 + $1.bytes }.formattedBytes)
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .tag(SidebarItem.category(category))
                    }
                }
            }
            Section {
                Label("Trash", systemImage: "trash").tag(SidebarItem.trash)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
    }
}

struct ScanToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let progress = model.scanProgress {
                ProgressView().controlSize(.small)
                Text(progress).foregroundStyle(.secondary)
            }
            Button(model.scan == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise") {
                Task { await model.runScan() }
            }
            .disabled(model.isBusy)
            .help(model.scan == nil ? "Scan (⌘N)" : "Rescan (⌘R)")
            Button("Export", systemImage: "square.and.arrow.up") { model.exportCSV() }
                .disabled(model.scan == nil)
                .help("Export CSV (⌘E)")
        }
    }
}

struct ExampleBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Label("Example data. This is a made-up Mac; cleanup here moves nothing on yours.", systemImage: "sparkles")
            Spacer()
            Button("Scan this Mac instead") { Task { await model.runScan() } }.controlSize(.small).disabled(model.isBusy)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct EmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("See what's taking up space").font(.title2.weight(.semibold))
            Text("Headroom measures caches, build folders, old backups and leftovers, then explains what each one is before you move anything to the Trash.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let progress = model.scanProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).foregroundStyle(.secondary)
                }
            } else {
                if !model.hasFullDiskAccess { AccessStep() }
                HStack {
                    Button("Scan this Mac") { Task { await model.runScan() } }.buttonStyle(.borderedProminent)
                    Button("Try example data") { model.loadExample() }.disabled(model.isBusy)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Asks for Full Disk Access once, up front, instead of letting macOS prompt folder by folder.
private struct AccessStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Give Headroom Full Disk Access", systemImage: "lock.open").font(.headline)
            Text("One switch covers Desktop, Documents, Downloads, iCloud Drive and other apps' data, so macOS won't ask about each folder. Without it, Headroom skips those folders.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Turn on Headroom in the list, then choose Quit & Reopen. If it isn't listed, click + and pick Headroom from Applications.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Full Disk Access settings") { FullDiskAccess.openSettings() }
        }
        .padding(16)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
