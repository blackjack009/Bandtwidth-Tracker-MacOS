import SwiftUI
import AppKit
import Combine

@main
struct BandwidthTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    lazy var history = HistoryStore()
    lazy var monitor = BandwidthMonitor(history: history)
    lazy var tester = SpeedTester()
    lazy var prefs = Preferences()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var effectView: NSVisualEffectView?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            monitor.start()
            setupStatusBar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            history.flush()
        }
    }

    @MainActor
    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Bandwidth")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 400, height: 620)
        // Manual dismissal (not .transient) so opening the file / color dialogs
        // does not close the popover out from under the user.
        pop.behavior = .applicationDefined

        let hosting = NSHostingController(rootView:
            ContentView()
                .environmentObject(monitor)
                .environmentObject(tester)
                .environmentObject(history)
                .environmentObject(prefs)
        )

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 620))
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        container.addSubview(effect)
        effectView = effect

        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        container.addSubview(hosting.view)

        let vc = NSViewController()
        vc.view = container
        pop.contentViewController = vc
        popover = pop

        // React to preference changes (theme + background) for the native chrome
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.applyPreferences() }
            }
            .store(in: &cancellables)
        applyPreferences()
    }

    @MainActor
    private func applyPreferences() {
        // Force appearance so vibrancy + controls follow the effective (auto-contrast) scheme
        let appearance = prefs.effectiveNSAppearance
        popover?.appearance = appearance
        popover?.contentViewController?.view.appearance = appearance

        // Hide vibrancy when a solid color / image background is chosen
        effectView?.isHidden = (prefs.background != .translucent)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let pop = popover else { return }
        if pop.isShown {
            closePopover()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installClickMonitor()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeClickMonitor()
    }

    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let pop = self.popover, pop.isShown else { return }
            // Keep open while a system panel (color / file dialog) is frontmost.
            if NSApp.modalWindow != nil { return }
            if let key = NSApp.keyWindow,
               String(describing: type(of: key)).contains("Panel") { return }
            self.closePopover()
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }
}
