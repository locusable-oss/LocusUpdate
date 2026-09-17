# LocusUpdate

macOS GUI for scanning installed apps and checking for updates (Sparkle appcast first, then GitHub Releases / vendor pages). Does not silently force-install updates — opens the publisher’s download/update page instead.

**MVP features:** menu bar outdated summary, background timed scan, optional notifications, local detection cache (incremental skip), and Settings for scan paths / interval / notifications / network policy.

GPL-3.0 — Copyright (C) 2026 Locusable Studio.

Build: see `ACCEPTANCE.md` (`make generate && make build` on a Mac with Xcode). Requires macOS 15+. Linux CI: static verify only (no Xcode).
