# ClaudeUsage — Design Doc

**Date:** 2026-02-22
**Status:** Approved

## Overview

A minimal native macOS menu bar app that periodically fetches Claude Code usage via CLI PTY and displays it in the menu bar. No external dependencies, no third-party services.

## Architecture

```
ClaudeUsage/
├── Package.swift
├── Resources/
│   └── Info.plist          # LSUIElement=YES, bundle config
├── Sources/ClaudeUsage/
│   ├── ClaudeUsageApp.swift   # @main, MenuBarExtra entry
│   ├── MenuBarView.swift      # SwiftUI menu content
│   ├── UsageFetcher.swift     # PTY interaction with claude CLI
│   ├── UsageParser.swift      # ANSI strip + percentage parsing
│   ├── UsageData.swift        # Data models + cache
│   └── Settings.swift         # UserDefaults wrapper
└── build.sh                   # Compiles + packages into .app
```

## Data Flow

1. Timer fires (per refresh interval setting)
2. `UsageFetcher` runs `env -u CLAUDECODE claude --allowed-tools ""` via PTY
3. Sends `/usage\r`, reads TUI output until stop strings appear
4. `UsageParser` strips ANSI codes, extracts percentages + reset times
5. Result cached in `UsageData` (published ObservableObject)
6. `MenuBarView` re-renders with new data

## Data Model

```swift
struct UsageSnapshot {
    let fiveHourAll: Double?        // 0.0 - 1.0 utilization
    let fiveHourOpus: Double?
    let weeklyAll: Double?
    let weeklyOpus: Double?
    let fiveHourResetsAt: String?
    let weeklyResetsAt: String?
    let fetchedAt: Date
}
```

## Menu Bar Display

**Label:** `73%` (5h remaining) or `27%` (5h used) — toggleable

**Dropdown:**
```
Current Session
  5h (all models):  73% · resets in 2h 15m
  5h (Opus):        45% · resets in 2h 15m

Current Week
  Weekly (all):     55%
  Weekly (Opus):    80%

Last updated: 9:25 PM
───────────────────────
⚙ Settings
  Refresh: 1m / 3m / ✓5m / 10m / 30m
  Display: ✓Remaining / Used
  Launch at Login: [ ]
───────────────────────
↺ Refresh Now
```

## Settings (UserDefaults)

| Key | Type | Default |
|-----|------|---------|
| `showRemaining` | Bool | true |
| `refreshInterval` | Int (minutes) | 5 |
| `launchAtLogin` | Bool | false |

## PTY Interaction

- Unset `CLAUDECODE` env var via `env -u CLAUDECODE`
- Launch: `claude --allowed-tools ""`
- Wait 2s for CLI to initialize
- Send: `/usage\r`
- Send Enter every 0.8s while waiting (for TUI rendering)
- Stop reading when output contains any of:
  - "Current week (all models)"
  - "Current week (Opus)"
  - "Current session"
  - "Failed to load usage data"
- Timeout: 20s

## Build & Install

```bash
./build.sh          # produces ClaudeUsage.app
cp -r ClaudeUsage.app /Applications/
```

## Constraints

- macOS 13+ (Ventura) — for MenuBarExtra + SMAppService
- No Dock icon (LSUIElement = YES)
- Background-only app
