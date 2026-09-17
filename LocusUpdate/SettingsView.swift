import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @EnvironmentObject private var appState: AppState
    @State private var pathsText: String = ""
    @State private var newIgnoreID: String = ""
    @State private var cacheClearedFlash = false

    private static let intervalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Form {
            Section("Scan") {
                Text("Scan paths (one per line)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pathsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 140)
                HStack {
                    Button("Reset to defaults") {
                        preferences.scanPaths = AppPreferences.defaultScanPaths()
                        pathsText = preferences.scanPaths.joined(separator: "\n")
                    }
                    Spacer()
                    Button("Apply paths") {
                        applyPaths()
                    }
                    .keyboardShortcut(.defaultAction)
                }

                Stepper(
                    value: $preferences.scanIntervalMinutes,
                    in: 0...24 * 60,
                    step: 15
                ) {
                    if preferences.scanIntervalMinutes <= 0 {
                        Text("Background scan: Off")
                    } else {
                        Text("Background scan every \(preferences.scanIntervalMinutes) min")
                    }
                }
                Text("0 disables timed background scans. Manual Rescan / Check still work. Changing the interval restarts the timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let scan = appState.lastScanDate {
                    Text("Last scan: \(Self.intervalFormatter.string(from: scan))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let check = appState.lastCheckDate {
                    Text("Last check: \(Self.intervalFormatter.string(from: check))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Network") {
                Toggle("Allow network version checks", isOn: $preferences.networkChecksEnabled)
                Text("When off, LocusUpdate reuses the local detection cache and does not contact Sparkle/GitHub/vendor URLs for new probes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify when outdated apps are found", isOn: $preferences.notificationsEnabled)
                Text("Uses the macOS notification center. Authorization is requested once when enabled. You can also silence LocusUpdate in System Settings → Notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Detection cache") {
                Text("Cached probe results live in Application Support and skip re-probes when bundle ID, version, and Info.plist mtime are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(cacheClearedFlash ? "Cache cleared" : "Clear detection cache") {
                        appState.clearDetectionCache()
                        cacheClearedFlash = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            cacheClearedFlash = false
                        }
                    }
                    Spacer()
                }
            }

            Section("Ignore list") {
                if preferences.ignoredBundleIDs.isEmpty {
                    Text("No ignored bundle IDs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.ignoredBundleIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(id)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Remove") {
                                preferences.unignore(bundleID: id)
                            }
                        }
                    }
                }
                HStack {
                    TextField("bundle.id.to.ignore", text: $newIgnoreID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let id = newIgnoreID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty else { return }
                        preferences.ignore(bundleID: id)
                        newIgnoreID = ""
                    }
                }
            }

            Section("Pinned versions") {
                if preferences.pinnedVersions.isEmpty {
                    Text("No pinned apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.pinnedVersions.keys.sorted(), id: \.self) { id in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(id)
                                    .font(.system(.body, design: .monospaced))
                                Text("Pinned: \(preferences.pinnedVersions[id] ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unpin") {
                                preferences.unpin(bundleID: id)
                            }
                        }
                    }
                }
                Text("Pinned apps are excluded from the outdated count and notifications until unpinned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("MVP scope") {
                Text("LocusUpdate detects outdated apps and opens the publisher’s update page in your browser. It never downloads or replaces binaries, and does not manage Homebrew/CLI packages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Locusable Studio · GPL-3.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 480)
        .onAppear {
            pathsText = preferences.scanPaths.joined(separator: "\n")
        }
        .navigationTitle("LocusUpdate Settings")
    }

    private func applyPaths() {
        let lines = pathsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty {
            preferences.scanPaths = lines
        }
    }
}
