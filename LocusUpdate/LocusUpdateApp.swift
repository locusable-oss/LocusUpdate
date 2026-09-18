import SwiftUI
import AppKit

@main
struct LocusUpdateApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("LocusUpdate", id: "main") {
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
                .frame(minWidth: 520, idealWidth: 540, minHeight: 480, idealHeight: 560)
        }

        // Menu bar summary: "LU ✓" when clean, "LU N" when N outdated apps.
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(appState)
                .onAppear { appState.ensureBackgroundLoopStarted() }
        } label: {
            Text("LU \(appState.menuBarLabel)")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarMenu: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        Text(appState.outdatedCount == 0
             ? "All checked apps up to date"
             : "\(appState.outdatedCount) outdated")
        if let check = appState.lastCheckDate {
            Text("Checked \(Self.relativeFormatter.localizedString(for: check, relativeTo: Date()))")
                .font(.caption)
        }
        Divider()
        ForEach(appState.outdatedStatuses.prefix(12)) { status in
            Button("\(status.app.name) \(status.app.shortVersion) → \(status.remote?.version ?? "?")") {
                appState.openUpdatePage(for: status)
            }
            .disabled(status.remote?.browserURL == nil)
        }
        if appState.outdatedCount > 12 {
            Text("…and \(appState.outdatedCount - 12) more")
        }
        Divider()
        Button("Scan & Check Now") {
            Task { await appState.runScanAndCheck(reason: "menu") }
        }
        .disabled(appState.isWorking)
        Button("Open LocusUpdate") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit LocusUpdate") {
            NSApp.terminate(nil)
        }
    }
}
