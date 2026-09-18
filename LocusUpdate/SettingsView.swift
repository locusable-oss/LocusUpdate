import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @EnvironmentObject private var appState: AppState
    @State private var pathsText: String = ""
    @State private var newIgnoreID: String = ""
    @State private var pathsHint: String = ""
    @State private var cacheClearedFlash = false
    @State private var cacheFlashTask: Task<Void, Never>?

    private static let intervalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var scanIntervalTitle: String {
        if preferences.scanIntervalMinutes <= 0 {
            return "Background scan: Off"
        }
        return "Background scan every \(preferences.scanIntervalMinutes) min"
    }

    var body: some View {
        Form {
            Section("Scan") {
                VStack(alignment: .leading, spacing: 8) {
                    caption("Scan paths (one per line)")
                    TextEditor(text: $pathsText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(6)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor))
                        }
                    HStack(alignment: .center, spacing: 12) {
                        Button("Reset to defaults") {
                            preferences.scanPaths = AppPreferences.defaultScanPaths()
                            pathsText = preferences.scanPaths.joined(separator: "\n")
                            pathsHint = "Restored the default scan paths."
                        }
                        .fixedSize()
                        Spacer(minLength: 12)
                        Button("Apply paths") {
                            applyPaths()
                        }
                        .keyboardShortcut(.defaultAction)
                        .fixedSize()
                    }
                    if !pathsHint.isEmpty {
                        caption(pathsHint)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(scanIntervalTitle)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Stepper(
                            scanIntervalTitle,
                            value: $preferences.scanIntervalMinutes,
                            in: 0...(24 * 60),
                            step: 15
                        )
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityLabel(scanIntervalTitle)
                    }
                    caption("0 disables timed background scans. Manual Rescan / Check still work. Changing the interval restarts the timer.")
                }

                if let scan = appState.lastScanDate {
                    Text("Last scan: \(Self.intervalFormatter.string(from: scan))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let check = appState.lastCheckDate {
                    Text("Last check: \(Self.intervalFormatter.string(from: check))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Network") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Allow network version checks", isOn: $preferences.networkChecksEnabled)
                    caption("When off, LocusUpdate reuses the local detection cache and does not contact Sparkle/GitHub/vendor URLs for new probes.")
                }
            }

            Section("Notifications") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Notify when outdated apps are found", isOn: $preferences.notificationsEnabled)
                    caption("Uses the macOS notification center. Authorization is requested once when enabled. You can also silence LocusUpdate in System Settings → Notifications.")
                }
            }

            Section("Detection cache") {
                VStack(alignment: .leading, spacing: 8) {
                    caption("Cached probe results live in Application Support and skip re-probes when bundle ID, version, and Info.plist mtime are unchanged.")
                    HStack {
                        Button(cacheClearedFlash ? "Cache cleared" : "Clear detection cache") {
                            appState.clearDetectionCache()
                            cacheClearedFlash = true
                            cacheFlashTask?.cancel()
                            cacheFlashTask = Task {
                                try? await Task.sleep(nanoseconds: 1_800_000_000)
                                if Task.isCancelled { return }
                                cacheClearedFlash = false
                            }
                        }
                        .fixedSize()
                        Spacer(minLength: 0)
                    }
                    if cacheClearedFlash {
                        caption(preferences.networkChecksEnabled
                            ? "Saved probe results were removed. The next check contacts Sparkle, GitHub, or the vendor again."
                            : "Saved probe results were removed. Network checks are still off, so nothing new will be fetched.")
                    }
                }
            }

            Section("Ignore list") {
                if preferences.ignoredBundleIDs.isEmpty {
                    Text("No ignored bundle IDs")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(preferences.ignoredBundleIDs.sorted(), id: \.self) { id in
                        HStack(alignment: .center, spacing: 8) {
                            Text(id)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Remove") {
                                preferences.unignore(bundleID: id)
                            }
                            .fixedSize()
                        }
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    TextField("bundle.id.to.ignore", text: $newIgnoreID)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onSubmit { addIgnore() }
                    Button("Add") { addIgnore() }
                        .disabled(newIgnoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fixedSize()
                }
            }

            Section("Pinned versions") {
                if preferences.pinnedVersions.isEmpty {
                    Text("No pinned apps")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(preferences.pinnedVersions.keys.sorted(), id: \.self) { id in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(id)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("Pinned: \(preferences.pinnedVersions[id] ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Unpin") {
                                preferences.unpin(bundleID: id)
                            }
                            .fixedSize()
                        }
                    }
                }
                caption("Pinned apps are excluded from the outdated count and notifications until unpinned.")
            }

            Section("MVP scope") {
                VStack(alignment: .leading, spacing: 4) {
                    caption("LocusUpdate detects outdated apps and opens the publisher’s update page in your browser. It never downloads or replaces binaries, and does not manage Homebrew/CLI packages.")
                    Text("Locusable Studio · GPL-3.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // macOS Form defaults to columns: unlabeled captions land in the label column and collide with fields.
        .formStyle(.grouped)
        .frame(minWidth: 500, idealWidth: 540)
        .onAppear {
            pathsText = preferences.scanPaths.joined(separator: "\n")
        }
        .navigationTitle("LocusUpdate Settings")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addIgnore() {
        let id = newIgnoreID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        preferences.ignore(bundleID: id)
        newIgnoreID = ""
    }

    private func applyPaths() {
        let lines = pathsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            pathsHint = "Add at least one folder, or Reset to defaults."
            return
        }
        preferences.scanPaths = lines
        pathsText = lines.joined(separator: "\n")
        let missing = lines.filter { line in
            let path = (line as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            return !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue
        }
        if missing.isEmpty {
            pathsHint = "Scan paths saved. Rescan to use them."
        } else if missing.count == lines.count {
            pathsHint = "Saved, but none of these paths are folders yet. Rescan will skip them."
        } else {
            pathsHint = missing.count == 1
                ? "Saved. 1 path is not a folder and will be skipped."
                : "Saved. \(missing.count) paths are not folders and will be skipped."
        }
    }
}
