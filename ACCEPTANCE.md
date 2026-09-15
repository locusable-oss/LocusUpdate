# LocusUpdate — unsigned local build & acceptance checklist

**Product UI name:** LocusUpdate  
**Xcode / SPM target name:** LocusUpdate  
**License:** GPL-3.0 (Locusable Studio)  
**Host requirement:** macOS 15+ with Xcode 15+ (or current stable). This Linux box cannot run `xcodebuild`.

## Build (unsigned / ad-hoc)

```bash
cd /path/to/LocusUpdate
brew install xcodegen   # once
make generate           # writes LocusUpdate.xcodeproj
make build              # Debug, CODE_SIGN_IDENTITY="-"
# or: make open  → Run in Xcode (Debug)
```

Expected artifact: `LocusUpdate.app` with display name **LocusUpdate**.  
First launch may prompt for network and notification permission — accept if testing WI 12–13.

`make acceptance` / `make notes` only print pointers to this file (WI 16).

## Work item acceptance

### 10 — One-click open download/update page
- [ ] Run **Check updates** so at least one row has a Latest version and Source.
- [ ] Click **Open** in the Update column (or **Open Update Page** / context menu).
- [ ] Confirm the default browser opens `remote.infoURL` (Sparkle feed, GitHub release, or vendor page).
- [ ] Confirm the app **never** downloads or replaces binaries silently.

### 11 — Ignore list + pin/fixed version
- [ ] Select an app → **Ignore** → with “Hide ignored” on, it disappears from the table; outdated count drops.
- [ ] Settings → Ignore list shows the bundle ID; **Remove** restores it.
- [ ] Select an outdated app → **Pin version** → “Pinned” badge; excluded from outdated count / menu bar / notifications.
- [ ] Settings → Pinned versions lists bundle ID + version; **Unpin** restores outdated treatment.
- [ ] Quit and relaunch: ignore + pin persist (UserDefaults by bundle ID).

### 12 — Background timed scan + menu bar summary
- [ ] Menu bar shows `LU ✓` or `LU N` (outdated count).
- [ ] Menu lists outdated apps; choosing one opens the update URL when available.
- [ ] **Scan & Check Now** from the menu refreshes counts.
- [ ] Settings → set background interval (e.g. 15 min) or **0** to disable timed scans; manual actions still work.
- [ ] After interval elapses (or use a short interval for test), scan/check runs without opening the main window.

### 13 — Outdated notification (toggleable)
- [ ] Settings → **Notify when outdated apps are found** = On; grant notification permission if asked.
- [ ] On a run that discovers *new* outdated apps, a **LocusUpdate** notification appears.
- [ ] Turn the toggle **Off**; subsequent scans do not post notifications.
- [ ] System Settings → Notifications can also silence the app (expected).

### 14 — Local detection cache + incremental update
- [ ] First **Check updates** may hit the network (Sparkle → GitHub → vendor).
- [ ] Quit/relaunch or check again without changing apps: unchanged bundleID + version + Info.plist mtime reuse cache (faster; no redundant probes).
- [ ] Cache file: `~/Library/Application Support/LocusUpdate/detection-cache.json`.
- [ ] Replace/update an app on disk (new version or Info.plist mtime) → that bundle is re-probed.

### 15 — Settings window
- [ ] **Settings…** sheet and macOS **LocusUpdate → Settings…** (⌘,) open the form.
- [ ] Edit **scan paths** (one per line), Apply, Rescan → only those roots are scanned (default `/Applications` + `~/Applications`).
- [ ] **Scan frequency**, **notifications on/off**, **Allow network version checks** all persist across relaunch.
- [ ] Network off → statuses note “network checks off” (or cache hits only); no new remote fetches.

### 16 — Unsigned build notes (this document)
- [ ] `make notes` / `make acceptance` reference this checklist.
- [ ] `make build` documents unsigned Debug signing (`CODE_SIGN_IDENTITY=-`).
- [ ] Reviewer followed build steps on a Mac and walked WI 10–15 checks above.

## Explicitly out of scope (sort 17 — do not mark done)

- Homebrew / CLI package replacement  
- Silent binary download + install / in-place replace  
- Any estimate fields invented for billing  

Those remain documentation-only / future product decisions. LocusUpdate only **opens** the publisher’s update/download page.

## Smoke matrix (quick)

| Step | Action | Pass |
|------|--------|------|
| A | `make generate && make build` on Mac | ☐ |
| B | Launch → table fills after scan | ☐ |
| C | Check updates → outdated rows | ☐ |
| D | Open update URL in browser | ☐ |
| E | Ignore + Pin persist | ☐ |
| F | Menu bar count matches outdated | ☐ |
| G | Notification once, then toggle off | ☐ |
| H | Cache file present after check | ☐ |
| I | Settings paths / interval / network | ☐ |
