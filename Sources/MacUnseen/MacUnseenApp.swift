import AppKit
import SwiftUI

@MainActor
private final class AppContext: NSObject, ObservableObject {
    // Own the store without subscribing the whole Scene to every sensor sample.
    let store = SensorStore()
    let monitor = MenuBarMonitor()
    private let dashboards = NSHashTable<NSWindow>.weakObjects()
    private var openWindow: OpenWindowAction?
    private var hasPresentedDashboard = false

    override init() {
        super.init()
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(windowClosing(_:)),
                                  name: NSWindow.willCloseNotification, object: nil)
        notifications.addObserver(self, selector: #selector(stop),
                                  name: NSApplication.willTerminateNotification, object: nil)
        monitor.openDashboard = { [weak self] section in
            guard let self else { return }
            store.selectedSection = section
            showDashboard()
        }
        monitor.onEnabledChange = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                enterMenuBarIfNeeded()
            } else if NSApp.activationPolicy() == .accessory {
                showDashboard()
            }
        }
    }

    func updateScene(_ phase: ScenePhase, openWindow: OpenWindowAction) {
        self.openWindow = openWindow
        monitor.start()
        // A restored session can contain zero windows. Handle the initial launch
        // once, without reopening the dashboard on later menu bar interactions.
        if phase == .active, !hasPresentedDashboard {
            DispatchQueue.main.async {
                if !self.hasPresentedDashboard { openWindow(id: "dashboard") }
            }
        }
    }

    func registerDashboard(_ window: NSWindow?) {
        guard let window else { return }
        dashboards.add(window)
        hasPresentedDashboard = true
        restoreDock()
    }

    @objc private func windowClosing(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, dashboards.contains(window) else { return }
        dashboards.remove(window)
        updateWindowVisibility()
        // Let AppKit finish closing the window before changing the activation policy.
        DispatchQueue.main.async { self.enterMenuBarIfNeeded() }
    }

    private func enterMenuBarIfNeeded() {
        guard monitor.enabled, dashboards.allObjects.isEmpty, NSApp.activationPolicy() == .regular else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func restoreDock() {
        if NSApp.activationPolicy() == .accessory { NSApp.setActivationPolicy(.regular) }
    }

    private func showDashboard() {
        restoreDock()
        if let window = NSApp.orderedWindows.first(where: { dashboards.contains($0) }) ?? dashboards.allObjects.first {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "dashboard")
        }
        NSApp.activate()
    }

    func updateWindowVisibility() {
        store.setWindowVisible(dashboards.allObjects.contains { $0.isVisible && !$0.isMiniaturized })
    }

    @objc private func stop() { store.stop() }
}

@main
struct MacUnseenApp: App {
    @StateObject private var context = AppContext()
    @StateObject private var languageSettings = LanguageSettings()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    private var store: SensorStore { context.store }

    var body: some Scene {
        WindowGroup(id: "dashboard") {
            ContentView(store: store, monitor: context.monitor)
                .environmentObject(context.monitor.fanControl)
                .environmentObject(store)
                .environment(\.sensorActions, SensorActions(store: store))
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .id(languageSettings.language)
                .frame(minWidth: 980, minHeight: 560)
                .background(WindowReader(onWindow: context.registerDashboard))
                .onAppear {
                    DispatchQueue.main.async { context.updateWindowVisibility() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
                    context.updateWindowVisibility()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    context.updateWindowVisibility()
                    store.setAppActive(true)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didResignActiveNotification
                    )
                ) { _ in
                    store.setAppActive(false)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .onChange(of: scenePhase, initial: true) { _, phase in
            context.updateScene(phase, openWindow: openWindow)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                MenuMonitorToggle(monitor: context.monitor)
            }
            CommandGroup(replacing: .appInfo) {
                Button(tr("关于 Mac Unseen")) {
                    store.selectedSection = .about
                }
            }
        }
    }
}
