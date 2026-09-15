import Foundation
import SwiftUI
import UserNotifications
import AppKit
import Combine

/// Shared model for main window + menu bar + background timed scan.
@MainActor
final class AppState: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var statuses: [AppVersionStatus] = []
    @Published var isScanning = false
    @Published var isChecking = false
    @Published var lastScanDate: Date?
    @Published var lastCheckDate: Date?
    @Published var menuBarLabel: String = "LU"

    let preferences: AppPreferences

    private var backgroundTask: Task<Void, Never>?
    private var knownOutdatedIDs: Set<String> = []
    private var didRequestNotificationAuth = false
    private var didStartBackground = false
    private var cancellables = Set<AnyCancellable>()

    init(preferences: AppPreferences = .shared) {
        self.preferences = preferences
        refreshMenuBarLabel()
        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshMenuBarLabel()
            }
            .store(in: &cancellables)
    }

    var outdatedStatuses: [AppVersionStatus] {
        statuses.filter { preferences.isEffectivelyOutdated($0) }
    }

    var outdatedCount: Int { outdatedStatuses.count }

    func ensureBackgroundLoopStarted() {
        guard !didStartBackground else { return }
        didStartBackground = true
        requestNotificationPermissionIfNeeded()
        Task { await self.runScanAndCheck(reason: "launch") }
        startBackgroundLoop()
    }

    func startBackgroundLoop() {
        backgroundTask?.cancel()
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = max(0, self.preferences.scanIntervalMinutes)
                if minutes <= 0 {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    continue
                }
                let nanos = UInt64(minutes) * 60 * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                await self.runScanAndCheck(reason: "timer")
            }
        }
    }

    func stopBackgroundLoop() {
        backgroundTask?.cancel()
        backgroundTask = nil
        didStartBackground = false
    }

    func runScanAndCheck(reason: String) async {
        await rescan()
        await checkUpdates()
        refreshMenuBarLabel()
        if reason == "timer" || reason == "launch" {
            await maybeNotifyNewOutdated()
        }
    }

    func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let roots = preferences.scanRootURLs()
        let scanner = AppScanner(searchRoots: roots)
        apps = await Task.detached(priority: .userInitiated) {
            scanner.scanInstalledApps()
        }.value
        let byID = Dictionary(uniqueKeysWithValues: statuses.map { ($0.app.bundleIdentifier, $0) })
        statuses = apps.map { app in
            if let prev = byID[app.bundleIdentifier], prev.app.shortVersion == app.shortVersion {
                return AppVersionStatus(app: app, remote: prev.remote, isOutdated: prev.isOutdated, note: prev.note)
            }
            return AppVersionStatus(app: app, remote: nil, isOutdated: false)
        }
        lastScanDate = Date()
        refreshMenuBarLabel()
    }

    func checkUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let snapshot = apps.filter { !preferences.isIgnored(bundleID: $0.bundleIdentifier) }
        let network = preferences.networkChecksEnabled
        let checker = UpdateChecker(networkChecksEnabled: network, useCache: true)
        let evaluated = await checker.evaluate(apps: snapshot, limit: 80)
        let byID = Dictionary(uniqueKeysWithValues: evaluated.map { ($0.app.bundleIdentifier, $0) })
        statuses = apps.map { app in
            if let e = byID[app.bundleIdentifier] {
                return e
            }
            let note = preferences.isIgnored(bundleID: app.bundleIdentifier) ? "ignored" : nil
            return AppVersionStatus(app: app, remote: nil, isOutdated: false, note: note)
        }
        lastCheckDate = Date()
        refreshMenuBarLabel()
    }

    func refreshMenuBarLabel() {
        let n = outdatedCount
        menuBarLabel = n > 0 ? "\(n)" : "✓"
    }

    func openUpdatePage(for status: AppVersionStatus) {
        guard let url = status.remote?.infoURL else { return }
        NSWorkspace.shared.open(url)
    }

    func ignoreApp(_ status: AppVersionStatus) {
        preferences.ignore(bundleID: status.app.bundleIdentifier)
        refreshMenuBarLabel()
    }

    func unignoreApp(bundleID: String) {
        preferences.unignore(bundleID: bundleID)
        refreshMenuBarLabel()
    }

    func pinApp(_ status: AppVersionStatus) {
        let version = status.remote?.version ?? status.app.shortVersion
        preferences.pin(bundleID: status.app.bundleIdentifier, version: version)
        refreshMenuBarLabel()
    }

    func unpinApp(bundleID: String) {
        preferences.unpin(bundleID: bundleID)
        refreshMenuBarLabel()
    }

    func requestNotificationPermissionIfNeeded() {
        guard preferences.notificationsEnabled, !didRequestNotificationAuth else { return }
        didRequestNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func maybeNotifyNewOutdated() async {
        guard preferences.notificationsEnabled else { return }
        requestNotificationPermissionIfNeeded()
        let current = Set(outdatedStatuses.map(\.app.bundleIdentifier))
        let newly = current.subtracting(knownOutdatedIDs)
        knownOutdatedIDs = current
        guard !newly.isEmpty else { return }

        let names = outdatedStatuses
            .filter { newly.contains($0.app.bundleIdentifier) }
            .prefix(5)
            .map(\.app.name)
        let body: String
        if names.count == 1 {
            body = "\(names[0]) has an update available."
        } else {
            body = "\(newly.count) apps have updates: \(names.joined(separator: ", "))."
        }

        let content = UNMutableNotificationContent()
        content.title = "LocusUpdate"
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "locusupdate.outdated.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(req)
    }
}
