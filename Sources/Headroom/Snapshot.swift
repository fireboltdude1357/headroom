import AppKit
import HeadroomCore
import SwiftUI

/// Renders each screen with example data into PNGs, light and dark, at 2x.
/// Uses `cacheDisplay` on a real offscreen window because ImageRenderer draws AppKit controls wrong.
@MainActor
enum SnapshotRenderer {
    static let windowSize = CGSize(width: 1100, height: 720)

    static func run(outputDir: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            fail("couldn't create \(outputDir.path): \(error.localizedDescription)")
        }

        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let onboarding = AppModel()
            onboarding.hasFullDiskAccess = false
            func onboardingShot(_ name: String, _ view: some View) {
                // Rendered at the view's own fitting size, the same size a window would pick for it.
                render(view.environment(onboarding), size: nil,
                       appearance: appearance, to: outputDir.appending(path: "\(name)-\(suffix).png"))
            }
            onboardingShot("onboarding-welcome", OnboardingView(step: .welcome, hasFullDiskAccess: false))
            onboardingShot("onboarding-access", OnboardingView(step: .access, hasFullDiskAccess: false))
            onboardingShot("empty", EmptyState())
            onboarding.hasFullDiskAccess = true
            onboardingShot("onboarding-granted", OnboardingView(step: .access, hasFullDiskAccess: true))

            let model = AppModel()
            model.loadExample()
            func shot(_ name: String) { renderMain(model, appearance: appearance, to: outputDir.appending(path: "\(name)-\(suffix).png")) }

            model.sidebar = .overview
            shot("overview")

            model.selectUntouchedProjects()
            shot("projects")

            model.sidebar = .category(.developer)
            model.expanded = ["xcode.deriveddata"]
            shot("category-expanded")

            model.selected.formUnion(["xcode.deriveddata", "npm.cache", "xcode.archives", "download:Docker.dmg"])
            render(ReviewSheet().environment(model), size: nil, appearance: appearance,
                   to: outputDir.appending(path: "review-\(suffix).png"))

            render(MenuBarView().environment(model), size: nil, appearance: appearance,
                   to: outputDir.appending(path: "menubar-\(suffix).png"))

            model.runExampleCleanup()
            if let summary = model.summary {
                render(ResultSheet(summary: summary).environment(model), size: nil, appearance: appearance,
                       to: outputDir.appending(path: "result-\(suffix).png"))
            }

            model.summary = nil
            model.sidebar = .trash
            shot("trash")

            render(SettingsView().environment(model), size: nil, appearance: appearance,
                   to: outputDir.appending(path: "settings-\(suffix).png"))
        }
    }

    /// The full window, including the title bar and toolbar.
    private static func renderMain(_ model: AppModel, appearance: NSAppearance.Name, to url: URL) {
        let controller = NSHostingController(rootView: ContentView().environment(model))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.title = "Headroom"
        window.appearance = NSAppearance(named: appearance)
        window.setContentSize(windowSize)
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFront(nil)
        settle()
        guard let frame = window.contentView?.superview else { fail("window has no frame view") }
        write(frame, to: url)
        window.orderOut(nil)
    }

    /// A bare view, sized to its own fitting size unless `size` is given.
    private static func render(_ view: some View, size: CGSize?, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let size = size ?? host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFront(nil)
        settle()
        write(host, to: url)
        window.orderOut(nil)
    }

    /// Lets SwiftUI finish layout and its first render passes.
    private static func settle() {
        for _ in 0..<6 { RunLoop.main.run(until: .now + 0.1) }
    }

    private static func write(_ view: NSView, to url: URL) {
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { fail("couldn't allocate a bitmap for \(url.lastPathComponent)") }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("couldn't encode \(url.lastPathComponent)") }
        do {
            try png.write(to: url)
        } catch {
            fail("couldn't write \(url.path): \(error.localizedDescription)")
        }
        print("wrote \(url.path)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("snapshot: " + message + "\n").utf8))
        exit(1)
    }
}
