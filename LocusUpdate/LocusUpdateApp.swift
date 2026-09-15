import SwiftUI
import AppKit

@main
struct LocusUpdateApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("LocusUpdate") {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.ensureBackgroundLoopStarted()
                }
        }
        .defaultSize(width: 900, height: 520)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LocusUpdate") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "LocusUpdate",
                    ])
                }
            }
        }

        Settings {
            SettingsView(preferences: appState.preferences)
                .environmentObject(appState)
        }

        MenuBarExtra {
            menuBarContent
                .onAppear { appState.ensureBackgroundLoopStarted() }
        } label: {
            Text("LU \(appState.menuBarLabel)")
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuBarContent: some View {
        Text(appState.outdatedCount == 0
             ? "All checked apps up to date"
             : "\(appState.outdatedCount) outdated")
        Divider()
        ForEach(appState.outdatedStatuses.prefix(12)) { status in
            Button("\(status.app.name) \(status.app.shortVersion) → \(status.remote?.version ?? "?")") {
                appState.openUpdatePage(for: status)
            }
            .disabled(status.remote?.infoURL == nil)
        }
        if appState.outdatedCount > 12 {
            Text("…and \(appState.outdatedCount - 12) more")
        }
        Divider()
        Button("Scan & Check Now") {
            Task { await appState.runScanAndCheck(reason: "menu") }
        }
        .disabled(appState.isScanning || appState.isChecking)
        Button("Open LocusUpdate") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        Divider()
        Button("Quit LocusUpdate") {
            NSApp.terminate(nil)
        }
    }
}
