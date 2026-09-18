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
    @Published private(set) var pendingWork = 0
    @Published var lastScanDate: Date?
    @Published var lastCheckDate: Date?
    @Published var menuBarLabel: String = "✓"

    let preferences: AppPreferences

    /// True while a scan or check is running, or waiting behind one. Drives button disable.
    var isWorking: Bool { pendingWork > 0 || isScanning || isChecking }

    private var backgroundTask: Task<Void, Never>?
    private var workTail: Task<Void, Never>?
    private var knownOutdatedIDs: Set<String> = []
    private var didRequestNotificationAuth = false
    private var didStartBackground = false
    private var cancellables = Set<AnyCancellable>()

    private static let knownOutdatedKey = "locusupdate.knownOutdatedBundleIDs"

    init(preferences: AppPreferences = .shared) {
        self.preferences = preferences
        knownOutdatedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.knownOutdatedKey) ?? [])
        refreshMenuBarLabel()

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshMenuBarLabel()
            }
            .store(in: &cancellables)

        // Restart timed scan when interval changes (0 = off, poll every 60s for re-enable).
        preferences.$scanIntervalMinutes
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.didStartBackground else { return }
                self.startBackgroundLoop()
            }
            .store(in: &cancellables)

        preferences.$notificationsEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.didRequestNotificationAuth = false
                    self?.requestNotificationPermissionIfNeeded()
                }
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
                    // Idle poll so turning the interval back on is picked up promptly.
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

    func runScanAndCheck(reason: String) async {
        await enqueue { state in
            await state.performRescan()
            await state.performCheck()
            state.refreshMenuBarLabel()
            if reason == "timer" || reason == "launch" {
                await state.maybeNotifyNewOutdated()
            }
        }
    }

    func rescan() async {
        await enqueue { state in
            await state.performRescan()
        }
    }

    func checkUpdates() async {
        await enqueue { state in
            await state.performCheck()
        }
    }

    /// One scan/check body at a time. A timer must not overwrite `apps` while a manual run is in flight.
    private func enqueue(_ body: @escaping @MainActor (AppState) async -> Void) async {
        pendingWork += 1
        defer { pendingWork = max(0, pendingWork - 1) }
        let previous = workTail
        let next = Task { @MainActor in
            await previous?.value
            await body(self)
        }
        workTail = next
        await next.value
    }

    private func performRescan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let roots = preferences.scanRootURLs()
        let scanner = AppScanner(searchRoots: roots)
        let previous = indexByIdentity(statuses)
        apps = await Task.detached(priority: .userInitiated) {
            scanner.scanInstalledApps()
        }.value
        statuses = apps.map { app in
            if let prev = previous[app.id], prev.app.shortVersion == app.shortVersion {
                return AppVersionStatus(app: app, remote: prev.remote, isOutdated: prev.isOutdated, note: prev.note)
            }
            return AppVersionStatus(app: app, remote: nil, isOutdated: false)
        }
        lastScanDate = Date()
        refreshMenuBarLabel()
    }

    private func performCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let previous = indexByIdentity(statuses)
        let snapshot = apps.filter { !preferences.isIgnored(bundleID: $0.bundleIdentifier) }
        let network = preferences.networkChecksEnabled
        let checker = UpdateChecker(networkChecksEnabled: network, useCache: true)
        let evaluated = await checker.evaluate(apps: snapshot, limit: 80)
        let byID = indexByIdentity(evaluated)
        statuses = apps.map { app in
            if let evaluatedStatus = byID[app.id] {
                return evaluatedStatus
            }
            if preferences.isIgnored(bundleID: app.bundleIdentifier) {
                return AppVersionStatus(app: app, remote: nil, isOutdated: false, note: "ignored")
            }
            // Past this round's network budget. Keep the last result instead of wiping it.
            if let prev = previous[app.id],
               prev.app.shortVersion == app.shortVersion,
               (prev.remote != nil || prev.note != nil) {
                return AppVersionStatus(app: app, remote: prev.remote, isOutdated: prev.isOutdated, note: prev.note)
            }
            return AppVersionStatus(app: app, remote: nil, isOutdated: false, note: "not checked yet")
        }
        lastCheckDate = Date()
        refreshMenuBarLabel()
    }

    /// Last-wins map. `Dictionary(uniqueKeysWithValues:)` traps when two bundles share an id.
    private func indexByIdentity(_ rows: [AppVersionStatus]) -> [String: AppVersionStatus] {
        var map: [String: AppVersionStatus] = [:]
        map.reserveCapacity(rows.count)
        for row in rows {
            map[row.app.id] = row
        }
        return map
    }

    func refreshMenuBarLabel() {
        let n = outdatedCount
        menuBarLabel = n > 0 ? "\(n)" : "✓"
    }

    func openUpdatePage(for status: AppVersionStatus) {
        guard let url = status.remote?.browserURL else { return }
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

    func clearDetectionCache() {
        DetectionCache().save([:])
    }

    func requestNotificationPermissionIfNeeded() {
        guard preferences.notificationsEnabled, !didRequestNotificationAuth else { return }
        didRequestNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func persistKnownOutdated() {
        UserDefaults.standard.set(Array(knownOutdatedIDs).sorted(), forKey: Self.knownOutdatedKey)
    }

    private func maybeNotifyNewOutdated() async {
        guard preferences.notificationsEnabled else { return }
        requestNotificationPermissionIfNeeded()
        let current = Set(outdatedStatuses.map(\.app.bundleIdentifier))
        let newly = current.subtracting(knownOutdatedIDs)
        knownOutdatedIDs = current
        persistKnownOutdated()
        guard !newly.isEmpty else { return }

        let names = outdatedStatuses
            .filter { newly.contains($0.app.bundleIdentifier) }
            .prefix(5)
            .map(\.app.name)
        let body: String
        if names.count == 1, newly.count == 1 {
            body = "\(names[0]) has an update available."
        } else {
            let list = names.joined(separator: ", ")
            let extra = newly.count - names.count
            if extra > 0 {
                body = "\(newly.count) apps have updates: \(list), and \(extra) more."
            } else {
                body = "\(newly.count) apps have updates: \(list)."
            }
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
