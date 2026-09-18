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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("LocusUpdate")
                    .font(.title2.weight(.semibold))
                    .fixedSize()
                Spacer(minLength: 12)
                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 10) {
                Toggle("Outdated only", isOn: $onlyOutdated)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Toggle("Hide ignored", isOn: $hideIgnored)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Spacer(minLength: 8)
                Button("Settings…") { showSettings = true }
                    .fixedSize()
                Button(appState.isScanning ? "Scanning…" : "Rescan") {
                    Task { await appState.rescan() }
                }
                .disabled(appState.isWorking)
                .fixedSize()
                Button(appState.isChecking ? "Checking…" : "Check updates") {
                    Task { await appState.checkUpdates() }
                }
                .disabled(appState.isWorking || appState.apps.isEmpty)
                .fixedSize()
            }

            Group {
                if visible.isEmpty {
                    emptyState
                } else {
                    appTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 420)
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Done") { showSettings = false }
                        .keyboardShortcut(.cancelAction)
                        .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
                SettingsView(preferences: appState.preferences)
                    .environmentObject(appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: 540, height: 620)
        }
    }

    private var appTable: some View {
        Table(visible, selection: $selection) {
            TableColumn("Name") { (row: AppVersionStatus) in
                HStack(spacing: 6) {
                    Text(row.app.name)
                        .lineLimit(1)
                    if appState.preferences.pinnedVersion(for: row.app.bundleIdentifier) != nil {
                        badge("Pinned", fill: Color.yellow.opacity(0.28))
                    }
                    if appState.preferences.isIgnored(bundleID: row.app.bundleIdentifier) {
                        badge("Ignored", fill: Color.secondary.opacity(0.18))
                    }
                }
            }
            .width(min: 120, ideal: 180)
            TableColumn("Local") { (row: AppVersionStatus) in
                Text(row.app.shortVersion)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Latest") { (row: AppVersionStatus) in
                Text(row.remote?.version ?? "—")
                    .lineLimit(1)
                    .foregroundStyle(appState.preferences.isEffectivelyOutdated(row) ? Color.orange : Color.primary)
            }
            .width(min: 60, ideal: 90)
            TableColumn("Source") { (row: AppVersionStatus) in
                Text(sourceLabel(row))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Update") { (row: AppVersionStatus) in
                Button("Open") {
                    appState.openUpdatePage(for: row)
                }
                .disabled(row.remote?.browserURL == nil)
                .help(row.remote?.browserURL?.absoluteString ?? "No download/update page")
            }
            .width(70)
            TableColumn("Bundle ID") { (row: AppVersionStatus) in
                Text(row.app.bundleIdentifier)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 220)
        }
        .contextMenu(forSelectionType: AppVersionStatus.ID.self) { ids in
            contextMenu(for: ids)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if appState.isScanning && appState.apps.isEmpty {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning installed apps…")
                    .font(.headline)
                Text("Looking one level under each scan path for .app bundles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appState.apps.isEmpty {
                Text("No apps found")
                    .font(.headline)
                Text("Add scan paths in Settings, then Rescan. Only .app bundles directly inside those folders are listed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else if onlyOutdated {
                Text("No outdated apps")
                    .font(.headline)
                Text("Uncheck “Outdated only” to see every scanned app, including ones that are current or not checked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            } else {
                Text("Nothing to show")
                    .font(.headline)
                Text("Ignored apps are hidden. Uncheck “Hide ignored”, or remove ids in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var actionBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if let sel = selectedStatus {
                Button("Open Update Page") {
                    appState.openUpdatePage(for: sel)
                }
                .disabled(sel.remote?.browserURL == nil)
                .fixedSize()

                if appState.preferences.isIgnored(bundleID: sel.app.bundleIdentifier) {
                    Button("Unignore") {
                        appState.unignoreApp(bundleID: sel.app.bundleIdentifier)
                    }
                    .fixedSize()
                } else {
                    Button("Ignore") {
                        appState.ignoreApp(sel)
                    }
                    .fixedSize()
                }

                if appState.preferences.pinnedVersion(for: sel.app.bundleIdentifier) != nil {
                    Button("Unpin") {
                        appState.unpinApp(bundleID: sel.app.bundleIdentifier)
                    }
                    .fixedSize()
                } else {
                    Button("Pin version") {
                        appState.pinApp(sel)
                    }
                    .fixedSize()
                }

                if let pinned = appState.preferences.pinnedVersion(for: sel.app.bundleIdentifier) {
                    Text("Pinned at \(pinned)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Select a row for Ignore, Pin, or Open Update. Opening always uses the browser — never a silent install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func badge(_ title: String, fill: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var summaryLine: String {
        if appState.isScanning { return "Scanning installed apps…" }
        if appState.isChecking { return "Checking for updates…" }
        let outdated = appState.outdatedCount
        let ignored = appState.preferences.ignoredBundleIDs.count
        let pinned = appState.preferences.pinnedVersions.count
        return "\(appState.apps.count) installed · \(outdated) outdated · \(ignored) ignored · \(pinned) pinned · Sparkle → GitHub → vendor"
    }

    private func sourceLabel(_ row: AppVersionStatus) -> String {
        switch row.remote?.source {
        case .sparkle:
            return "Sparkle"
        case .githubReleases:
            return "GitHub"
        case .vendorPage:
            return "Vendor"
        case .unknown:
            return row.note ?? "Unknown"
        case nil:
            return row.note ?? "—"
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<AppVersionStatus.ID>) -> some View {
        let rows = appState.statuses.filter { ids.contains($0.id) }
        if let first = rows.first {
            Button("Open Update Page") {
                appState.openUpdatePage(for: first)
            }
            .disabled(first.remote?.browserURL == nil)
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
