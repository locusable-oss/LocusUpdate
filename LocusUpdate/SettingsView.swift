import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var pathsText: String = ""
    @State private var newIgnoreID: String = ""

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
                        let lines = pathsText
                            .split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        if !lines.isEmpty {
                            preferences.scanPaths = lines
                        }
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
                Text("0 disables timed background scans. Manual Rescan / Check still work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Network") {
                Toggle("Allow network version checks", isOn: $preferences.networkChecksEnabled)
                Text("When off, LocusUpdate uses the local detection cache only and does not contact Sparkle/GitHub/vendor URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify when outdated apps are found", isOn: $preferences.notificationsEnabled)
                Text("Uses the macOS notification center. You can also disable LocusUpdate alerts in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            pathsText = preferences.scanPaths.joined(separator: "\n")
        }
        .navigationTitle("LocusUpdate Settings")
    }
}
