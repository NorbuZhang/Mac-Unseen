import AppKit
import SwiftUI

@MainActor
private final class AppContext: ObservableObject {
    // Own the store without subscribing the whole Scene to every sensor sample.
    let store = SensorStore()
}

@main
struct MacUnseenApp: App {
    @StateObject private var context = AppContext()
    @StateObject private var languageSettings = LanguageSettings()
    private var store: SensorStore { context.store }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environmentObject(store)
                .environment(\.sensorActions, SensorActions(store: store))
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .id(languageSettings.language)
                .frame(minWidth: 980, minHeight: 560)
                .onAppear {
                    DispatchQueue.main.async { updateWindowVisibility() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
                    updateWindowVisibility()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                    updateWindowVisibility(excluding: notification.object as? NSWindow)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    store.stop()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    updateWindowVisibility()
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("关于 Mac Unseen")) {
                    store.selectedSection = .about
                }
            }
        }
    }

    private func updateWindowVisibility(excluding closingWindow: NSWindow? = nil) {
        store.setWindowVisible(NSApp.windows.contains {
            $0 !== closingWindow && $0.canBecomeMain && $0.isVisible && !$0.isMiniaturized
        })
    }
}
