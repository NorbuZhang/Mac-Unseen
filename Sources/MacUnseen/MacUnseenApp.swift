// SPDX-License-Identifier: MPL-2.0

import AppKit
import SwiftUI

@main
struct MacUnseenApp: App {
    @StateObject private var store = SensorStore()
    @StateObject private var languageSettings = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .id(languageSettings.language)
                .frame(minWidth: 980, minHeight: 560)
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
}
