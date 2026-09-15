import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var onlyOutdated = true
    @State private var hideIgnored = true
    @State private var selection: AppVersionStatus.ID?
    @State private var showSettings = false

    private var visible: [AppVersionStatus] {
        var rows = appState.statuses
        if hideIgnored {
            rows = rows.filter { !appState.preferences.isIgnored(bundleID: $0.app.bundleIdentifier) }
        }
        if onlyOutdated {
            rows = rows.filter { appState.preferences.isEffectivelyOutdated($0) }
        }
        return rows
    }

    private var selectedStatus: AppVersionStatus? {
        guard let selection else { return nil }
        return appState.statuses.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LocusUpdate")
                    .font(.title2.weight(.semibold))
                Spacer()
                Toggle("Outdated only", isOn: $onlyOutdated)
                    .toggleStyle(.checkbox)
                Toggle("Hide ignored", isOn: $hideIgnored)
                    .toggleStyle(.checkbox)
                Button("Settings…") { showSettings = true }
                Button(appState.isScanning ? "Scanning…" : "Rescan") {
                    Task { await appState.rescan() }
                }
                .disabled(appState.isScanning || appState.isChecking)
                Button(appState.isChecking ? "Checking…" : "Check updates") {
                    Task { await appState.checkUpdates() }
                }
                .disabled(appState.isScanning || appState.isChecking || appState.apps.isEmpty)
            }

            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(visible, selection: $selection) {
                TableColumn("Name") { (row: AppVersionStatus) in
                    HStack(spacing: 6) {
                        Text(row.app.name)
                        if appState.preferences.pinnedVersion(for: row.app.bundleIdentifier) != nil {
                            Text("Pinned")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.yellow.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        if appState.preferences.isIgnored(bundleID: row.app.bundleIdentifier) {
                            Text("Ignored")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .width(min: 120, ideal: 160)
                TableColumn("Local") { (row: AppVersionStatus) in
                    Text(row.app.shortVersion)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Latest") { (row: AppVersionStatus) in
                    Text(row.remote?.version ?? "—")
                }
                .width(min: 60, ideal: 80)
                TableColumn("Source") { (row: AppVersionStatus) in
                    Text(sourceLabel(row))
                        .font(.caption)
                }
                .width(min: 80, ideal: 110)
                TableColumn("Update") { (row: AppVersionStatus) in
                    Button("Open") {
                        appState.openUpdatePage(for: row)
                    }
                    .disabled(row.remote?.infoURL == nil)
                    .help(row.remote?.infoURL?.absoluteString ?? "No download/update URL")
                }
                .width(70)
                TableColumn("Bundle ID") { (row: AppVersionStatus) in
                    Text(row.app.bundleIdentifier)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 140, ideal: 220)
            }
            .contextMenu(forSelectionType: AppVersionStatus.ID.self) { ids in
                contextMenu(for: ids)
            }

            HStack {
                if let sel = selectedStatus {
                    Button("Open Update Page") {
                        appState.openUpdatePage(for: sel)
                    }
                    .disabled(sel.remote?.infoURL == nil)

                    if appState.preferences.isIgnored(bundleID: sel.app.bundleIdentifier) {
                        Button("Unignore") {
                            appState.unignoreApp(bundleID: sel.app.bundleIdentifier)
                        }
                    } else {
                        Button("Ignore") {
                            appState.ignoreApp(sel)
                        }
                    }

                    if appState.preferences.pinnedVersion(for: sel.app.bundleIdentifier) != nil {
                        Button("Unpin") {
                            appState.unpinApp(bundleID: sel.app.bundleIdentifier)
                        }
                    } else {
                        Button("Pin version") {
                            appState.pinApp(sel)
                        }
                    }

                    if let pinned = appState.preferences.pinnedVersion(for: sel.app.bundleIdentifier) {
                        Text("Pinned at \(pinned)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select a row for Ignore / Pin / Open Update. Opening always uses the browser — never silent install.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                    Button("Done") { showSettings = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding()
                Divider()
                SettingsView(preferences: appState.preferences)
            }
            .frame(width: 520, height: 520)
        }
        .task {
            appState.ensureBackgroundLoopStarted()
        }
    }

    private var summaryLine: String {
        let outdated = appState.outdatedCount
        let ignored = appState.preferences.ignoredBundleIDs.count
        let pinned = appState.preferences.pinnedVersions.count
        return "\(appState.apps.count) installed · \(outdated) outdated · \(ignored) ignored · \(pinned) pinned · Sparkle → GitHub → vendor"
    }

    private func sourceLabel(_ row: AppVersionStatus) -> String {
        if let pinned = appState.preferences.pinnedVersion(for: row.app.bundleIdentifier) {
            return "pinned \(pinned)"
        }
        return row.remote?.source.rawValue ?? (row.note ?? "—")
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<AppVersionStatus.ID>) -> some View {
        let rows = appState.statuses.filter { ids.contains($0.id) }
        if let first = rows.first {
            Button("Open Update Page") {
                appState.openUpdatePage(for: first)
            }
            .disabled(first.remote?.infoURL == nil)
            Divider()
            if appState.preferences.isIgnored(bundleID: first.app.bundleIdentifier) {
                Button("Unignore") {
                    appState.unignoreApp(bundleID: first.app.bundleIdentifier)
                }
            } else {
                Button("Ignore") {
                    appState.ignoreApp(first)
                }
            }
            if appState.preferences.pinnedVersion(for: first.app.bundleIdentifier) != nil {
                Button("Unpin") {
                    appState.unpinApp(bundleID: first.app.bundleIdentifier)
                }
            } else {
                Button("Pin version") {
                    appState.pinApp(first)
                }
            }
        }
    }
}
