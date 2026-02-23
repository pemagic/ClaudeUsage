# ClaudeUsage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app that fetches Claude Code usage via CLI PTY and displays 5-hour/weekly utilization.

**Architecture:** Swift Package Manager executable + manual .app bundle packaging. PTY interaction using Darwin's `openpty()`. SwiftUI `MenuBarExtra` for UI. No third-party dependencies.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation, Darwin (PTY), ServiceManagement (launch at login). macOS 13+.

---

## Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Resources/Info.plist`
- Create: `build.sh`
- Create: `Sources/ClaudeUsage/.gitkeep`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            path: "Sources/ClaudeUsage"
        )
    ]
)
```

**Step 2: Create Resources/Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsage</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.ClaudeUsage</string>
    <key>CFBundleName</key>
    <string>ClaudeUsage</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

**Step 3: Create build.sh**

```bash
#!/bin/bash
set -e

APP="ClaudeUsage.app"
swift build -c release 2>&1

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeUsage "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

echo "✅ Built $APP"
echo "   Install: cp -r $APP /Applications/"
```

```bash
chmod +x build.sh
```

**Step 4: Init git and commit**

```bash
cd /Users/mac/Desktop/c1/ClaudeUsage
git init
echo ".build/" >> .gitignore
echo "*.app" >> .gitignore
git add .
git commit -m "chore: project scaffold"
```

---

## Task 2: Data Models

**Files:**
- Create: `Sources/ClaudeUsage/UsageData.swift`
- Create: `Sources/ClaudeUsage/Settings.swift`

**Step 1: Create UsageData.swift**

```swift
import Foundation

struct UsageSnapshot {
    // Utilization as 0.0–1.0 (e.g. 0.73 = 73% used)
    let fiveHourAll: Double?
    let fiveHourOpus: Double?
    let weeklyAll: Double?
    let weeklyOpus: Double?
    let fiveHourResetsAt: String?
    let weeklyResetsAt: String?
    let fetchedAt: Date
    let rawText: String   // kept for debugging

    var isValid: Bool { fiveHourAll != nil || weeklyAll != nil }
}
```

**Step 2: Create Settings.swift**

```swift
import Foundation
import ServiceManagement

final class Settings: ObservableObject {
    @Published var showRemaining: Bool {
        didSet { UserDefaults.standard.set(showRemaining, forKey: "showRemaining") }
    }
    @Published var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }

    static let refreshOptions = [1, 3, 5, 10, 30]

    init() {
        showRemaining = UserDefaults.standard.object(forKey: "showRemaining") as? Bool ?? true
        refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 5
        launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
```

**Step 3: Verify it compiles**

```bash
swift build 2>&1 | head -20
```

Expected: compile errors about missing @main — that's fine, we haven't written the App yet.

**Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: data models and settings"
```

---

## Task 3: Usage Parser (TDD)

**Files:**
- Create: `Sources/ClaudeUsage/UsageParser.swift`
- Create: `Tests/ClaudeUsageTests/UsageParserTests.swift` (manual run, not SPM test target)

**Step 1: Write UsageParser.swift**

```swift
import Foundation

enum UsageParser {

    // Strip ANSI escape codes (colors, cursor movement, etc.)
    static func stripANSI(_ text: String) -> String {
        // Matches ESC[ sequences and standalone ESC sequences
        let pattern = "\u{1B}(?:[@-Z\\\\-_]|\\[[0-?]*[ -/]*[@-~])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // Extract first percentage from a string, returns 0.0–1.0
    static func parsePercent(_ text: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else { return nil }
        return value / 100.0
    }

    // Extract reset time description, e.g. "resets in 2h 15m"
    static func parseResetTime(_ text: String) -> String? {
        let pattern = "resets? in ([\\w ]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }

    static func parse(_ rawText: String) -> UsageSnapshot {
        let clean = stripANSI(rawText)
        let lines = clean.components(separatedBy: .newlines)

        var fiveHourAll: Double? = nil
        var fiveHourOpus: Double? = nil
        var weeklyAll: Double? = nil
        var weeklyOpus: Double? = nil
        var fiveHourResetsAt: String? = nil
        var weeklyResetsAt: String? = nil

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            // 5-hour / session bucket
            let isFiveHour = lower.contains("5h") || lower.contains("5-hour")
                          || lower.contains("current session") || lower.contains("session")
            // Weekly bucket
            let isWeekly = lower.contains("week")
            // Opus sub-bucket
            let isOpus = lower.contains("opus")

            if isFiveHour && !isWeekly {
                if isOpus {
                    if fiveHourOpus == nil { fiveHourOpus = parsePercent(line) }
                } else {
                    if fiveHourAll == nil {
                        fiveHourAll = parsePercent(line)
                        // Scan next few lines for reset time
                        for j in (i+1)..<min(i+5, lines.count) {
                            if let t = parseResetTime(lines[j]) {
                                fiveHourResetsAt = t; break
                            }
                        }
                    }
                }
            } else if isWeekly {
                if isOpus {
                    if weeklyOpus == nil { weeklyOpus = parsePercent(line) }
                } else {
                    if weeklyAll == nil {
                        weeklyAll = parsePercent(line)
                        for j in (i+1)..<min(i+5, lines.count) {
                            if let t = parseResetTime(lines[j]) {
                                weeklyResetsAt = t; break
                            }
                        }
                    }
                }
            }
        }

        return UsageSnapshot(
            fiveHourAll: fiveHourAll,
            fiveHourOpus: fiveHourOpus,
            weeklyAll: weeklyAll,
            weeklyOpus: weeklyOpus,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            fetchedAt: Date(),
            rawText: clean
        )
    }
}
```

**Step 2: Add a quick parse smoke-test to verify parser works**

Add a temporary `debugParser()` function call in a test file:

Create `Sources/ClaudeUsage/DebugParser.swift` temporarily:

```swift
// DELETE this file after verifying parser
import Foundation

func debugParser() {
    let sample = """
    \u{1B}[2J\u{1B}[H
    ╭─────────────────────────────────────────╮
    │              Usage                      │
    ├─────────────────────────────────────────┤
    │  Current session                        │
    │    5h (all models):    73% used         │
    │    Resets in 2h 15m                     │
    │    5h (Opus):          45% used         │
    ├─────────────────────────────────────────┤
    │  Current week (all models)              │
    │    Weekly limit:       55% used         │
    │    Resets in 3d 2h                      │
    │    Weekly (Opus):      80% used         │
    ╰─────────────────────────────────────────╯
    """
    let snap = UsageParser.parse(sample)
    print("5h all:   \(snap.fiveHourAll.map { "\(Int($0*100))%" } ?? "nil")")
    print("5h opus:  \(snap.fiveHourOpus.map { "\(Int($0*100))%" } ?? "nil")")
    print("weekly:   \(snap.weeklyAll.map { "\(Int($0*100))%" } ?? "nil")")
    print("w. opus:  \(snap.weeklyOpus.map { "\(Int($0*100))%" } ?? "nil")")
    print("5h reset: \(snap.fiveHourResetsAt ?? "nil")")
    print("wk reset: \(snap.weeklyResetsAt ?? "nil")")
}
```

**Step 3: Verify parser compiles (build check only)**

```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```

**Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: usage parser with ANSI stripping"
```

---

## Task 4: PTY Fetcher

**Files:**
- Create: `Sources/ClaudeUsage/UsageFetcher.swift`

**Step 1: Create UsageFetcher.swift**

```swift
import Darwin
import Foundation

actor UsageFetcher {

    enum FetchError: LocalizedError {
        case claudeNotFound
        case ptyFailed(String)
        case timeout
        case outputEmpty

        var errorDescription: String? {
            switch self {
            case .claudeNotFound:    return "claude binary not found on PATH"
            case .ptyFailed(let m): return "PTY error: \(m)"
            case .timeout:           return "Timed out waiting for /usage output"
            case .outputEmpty:       return "claude produced no output"
            }
        }
    }

    // Locate claude binary
    private static func findClaude() -> String? {
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Try PATH lookup via `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        return nil
    }

    func fetch() async throws -> String {
        guard let claude = Self.findClaude() else {
            throw FetchError.claudeNotFound
        }

        // Open a PTY pair
        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw FetchError.ptyFailed("openpty failed: \(String(cString: strerror(errno)))")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        // Build process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Unset CLAUDECODE to avoid "nested session" error
        process.arguments = ["-u", "CLAUDECODE", claude, "--allowed-tools", ""]
        process.standardInput  = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError  = secondaryHandle

        // Neutral working directory (not inside any project)
        let probeDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsage/probe")
        try? FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = probeDir

        // Clean environment: remove ANTHROPIC_* and CLAUDECODE
        var env = ProcessInfo.processInfo.environment
        env["CLAUDECODE"] = nil
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        for key in env.keys where key.hasPrefix("ANTHROPIC_") { env[key] = nil }
        process.environment = env

        try process.run()
        defer {
            try? secondaryHandle.close()
            close(primaryFD)
            if process.isRunning { process.terminate() }
        }

        // Wait for CLI to initialize before sending command
        try await Task.sleep(nanoseconds: 2_000_000_000)  // 2s
        _ = drainFD(primaryFD)  // discard welcome text

        // Send /usage command
        write(primaryFD, "/usage\r", 7)

        // Read until we see usage output or timeout
        let stopStrings = [
            "current week (all models)",
            "current week (opus)",
            "current week (sonnet)",
            "current session",
            "failed to load usage data",
        ]

        var buffer = Data()
        let deadline = Date().addingTimeInterval(20)
        var lastEnterSent = Date()
        var found = false

        while Date() < deadline {
            let chunk = drainFD(primaryFD)
            if !chunk.isEmpty {
                buffer.append(chunk)
                if let text = String(data: buffer, encoding: .utf8) {
                    let lower = text.lowercased()
                    if stopStrings.contains(where: { lower.contains($0) }) {
                        found = true
                        // Settle: wait 0.5s for rendering to finish
                        try await Task.sleep(nanoseconds: 500_000_000)
                        buffer.append(drainFD(primaryFD))
                        break
                    }
                }
            }
            // Periodic Enter helps TUI render the usage panel
            if Date().timeIntervalSince(lastEnterSent) >= 0.8 {
                write(primaryFD, "\r", 1)
                lastEnterSent = Date()
            }
            try await Task.sleep(nanoseconds: 60_000_000)  // poll every 60ms
        }

        guard found else { throw FetchError.timeout }
        guard !buffer.isEmpty else { throw FetchError.outputEmpty }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    private func drainFD(_ fd: Int32) -> Data {
        var result = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break }
            result.append(contentsOf: buf.prefix(n))
        }
        return result
    }
}
```

**Step 2: Build check**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

**Step 3: Manual integration test — create a temporary test runner**

Add `Sources/ClaudeUsage/TestFetcher.swift` temporarily:

```swift
// DELETE after manual test
import Foundation

func runFetcherTest() {
    print("Testing fetcher...")
    Task {
        do {
            let fetcher = UsageFetcher()
            let raw = try await fetcher.fetch()
            print("=== RAW OUTPUT ===")
            print(raw)
            print("=== PARSED ===")
            let snap = UsageParser.parse(raw)
            print("5h all: \(snap.fiveHourAll.map { "\(Int($0*100))%" } ?? "nil")")
            print("weekly: \(snap.weeklyAll.map { "\(Int($0*100))%" } ?? "nil")")
        } catch {
            print("ERROR: \(error)")
        }
        exit(0)
    }
    RunLoop.main.run()
}
```

**Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: PTY usage fetcher"
```

---

## Task 5: Usage Store (Observable State)

**Files:**
- Create: `Sources/ClaudeUsage/UsageStore.swift`

**Step 1: Create UsageStore.swift**

```swift
import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var isLoading = false
    @Published var lastError: String?

    let settings: Settings
    private let fetcher = UsageFetcher()
    private var timer: Timer?

    init(settings: Settings) {
        self.settings = settings
        scheduleTimer()
        Task { await refresh() }
    }

    var menuBarLabel: String {
        guard let snap = snapshot, let value = snap.fiveHourAll else {
            return isLoading ? "…" : "—"
        }
        let pct = settings.showRemaining ? (1.0 - value) * 100 : value * 100
        return "\(Int(pct.rounded()))%"
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        do {
            let raw = try await fetcher.fetch()
            snapshot = UsageParser.parse(raw)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = Double(settings.refreshInterval) * 60
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
}
```

**Step 2: Build check**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

**Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: observable usage store"
```

---

## Task 6: SwiftUI Menu Bar UI

**Files:**
- Create: `Sources/ClaudeUsage/MenuBarView.swift`
- Create: `Sources/ClaudeUsage/ClaudeUsageApp.swift`

**Step 1: Create MenuBarView.swift**

```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        Group {
            snapshotContent
            Divider()
            settingsMenu
            Divider()
            Button("↺ Refresh Now") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r", modifiers: [])
            Divider()
            Button("Quit ClaudeUsage") { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: - Snapshot

    @ViewBuilder
    var snapshotContent: some View {
        if let snap = store.snapshot {
            Text("Current Session")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            usageRow(label: "5h (all models)",
                     value: snap.fiveHourAll,
                     resetIn: snap.fiveHourResetsAt)
            usageRow(label: "5h (Opus)",
                     value: snap.fiveHourOpus,
                     resetIn: nil)
            Divider()
            Text("Current Week")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            usageRow(label: "Weekly (all models)",
                     value: snap.weeklyAll,
                     resetIn: snap.weeklyResetsAt)
            usageRow(label: "Weekly (Opus)",
                     value: snap.weeklyOpus,
                     resetIn: nil)
            Divider()
            Text("Updated \(snap.fetchedAt, style: .time)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } else if store.isLoading {
            Text("Fetching usage…").foregroundStyle(.secondary)
        } else {
            Text(store.lastError ?? "No data").foregroundStyle(.red)
        }
    }

    func usageRow(label: String, value: Double?, resetIn: String?) -> some View {
        let display: String = {
            guard let v = value else { return "—" }
            let pct = settings.showRemaining ? (1.0 - v) * 100 : v * 100
            let suffix = resetIn.map { " · \($0)" } ?? ""
            return "\(Int(pct.rounded()))%\(suffix)"
        }()
        let color: Color = {
            guard let v = value else { return .secondary }
            if v > 0.8 { return .red }
            if v > 0.6 { return .orange }
            return .primary
        }()
        return HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(display).foregroundStyle(color)
        }
    }

    // MARK: - Settings

    @ViewBuilder
    var settingsMenu: some View {
        Menu("⚙ Settings") {
            // Refresh interval
            Menu("Refresh Interval") {
                ForEach(Settings.refreshOptions, id: \.self) { minutes in
                    Button {
                        settings.refreshInterval = minutes
                        store.scheduleTimer()
                    } label: {
                        HStack {
                            if settings.refreshInterval == minutes {
                                Image(systemName: "checkmark")
                            }
                            Text(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                        }
                    }
                }
            }
            Divider()
            // Display mode
            Menu("Display") {
                Button {
                    settings.showRemaining = true
                } label: {
                    HStack {
                        if settings.showRemaining { Image(systemName: "checkmark") }
                        Text("Remaining %")
                    }
                }
                Button {
                    settings.showRemaining = false
                } label: {
                    HStack {
                        if !settings.showRemaining { Image(systemName: "checkmark") }
                        Text("Used %")
                    }
                }
            }
            Divider()
            // Launch at login
            Button {
                settings.launchAtLogin.toggle()
            } label: {
                HStack {
                    if settings.launchAtLogin { Image(systemName: "checkmark") }
                    Text("Launch at Login")
                }
            }
        }
    }
}
```

**Step 2: Create ClaudeUsageApp.swift**

```swift
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var settings = Settings()
    @StateObject private var store: UsageStore

    init() {
        let s = Settings()
        _settings = StateObject(wrappedValue: s)
        _store = StateObject(wrappedValue: UsageStore(settings: s))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(settings)
        } label: {
            Text(store.menuBarLabel)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 3: Remove temporary debug files**

```bash
rm -f Sources/ClaudeUsage/DebugParser.swift
rm -f Sources/ClaudeUsage/TestFetcher.swift
```

**Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

**Step 5: Quick smoke test — run from command line**

```bash
.build/debug/ClaudeUsage &
sleep 3
# Check menu bar — should show "…" while loading then a percentage
kill %1
```

**Step 6: Commit**

```bash
git add Sources/
git commit -m "feat: SwiftUI menu bar UI"
```

---

## Task 7: Parser Tuning (Real Output)

After Task 6, we need to verify the parser handles Claude's actual `/usage` output correctly. The exact format is only known at runtime.

**Step 1: Capture real output**

Add a debug log temporarily in `UsageFetcher.fetch()` after getting raw output:

```swift
// After: return String(data: buffer, encoding: .utf8) ?? ""
// Add temporarily:
let debugPath = FileManager.default.temporaryDirectory.appendingPathComponent("claude_usage_raw.txt")
try? String(data: buffer, encoding: .utf8)?.write(to: debugPath, atomically: true, encoding: .utf8)
print("Raw output saved to: \(debugPath.path)")
```

**Step 2: Run and inspect raw output**

```bash
.build/debug/ClaudeUsage &
sleep 25
cat /tmp/claude_usage_raw.txt | cat -v   # show ANSI codes literally
```

**Step 3: Update parser if needed**

Look at the raw output and adjust the keyword matching in `UsageParser.parse()` to match actual line formats. The parser uses `.lowercased().contains(...)` so it's case-insensitive and flexible.

**Step 4: Remove debug code, commit**

```bash
git add Sources/
git commit -m "fix: parser tuned to actual claude output format"
```

---

## Task 8: Build .app and Install

**Step 1: Build release .app**

```bash
cd /Users/mac/Desktop/c1/ClaudeUsage
./build.sh
```

Expected:
```
Build complete!
✅ Built ClaudeUsage.app
   Install: cp -r ClaudeUsage.app /Applications/
```

**Step 2: Install**

```bash
cp -r ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

**Step 3: Verify**

- Menu bar shows `…` briefly, then a percentage (e.g. `73%`)
- Click menu bar item → dropdown shows session + weekly usage
- Settings → Refresh Interval → change works
- Settings → Display → toggle between remaining/used
- Settings → Launch at Login → toggling works (check System Settings > General > Login Items)

**Step 4: Final commit**

```bash
git add .
git commit -m "chore: verified build and install"
```

---

## Summary

| Task | Output |
|------|--------|
| 1 | Package.swift, Info.plist, build.sh |
| 2 | UsageData.swift, Settings.swift |
| 3 | UsageParser.swift |
| 4 | UsageFetcher.swift (PTY) |
| 5 | UsageStore.swift |
| 6 | MenuBarView.swift, ClaudeUsageApp.swift |
| 7 | Parser tuning against real output |
| 8 | .app bundle, install, verify |
