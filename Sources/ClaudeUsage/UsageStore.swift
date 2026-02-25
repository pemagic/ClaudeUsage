import Foundation
import IOKit
import SwiftUI

// MARK: - Check if user is actively using Claude Code

/// Returns true only when a claude process exists AND user project logs show
/// recent activity.  This avoids false positives from the short-lived claude
/// process that UsageFetcher spawns (which writes to /tmp, not ~/.claude).
private func isClaudeActive() -> Bool {
    // Condition 1: at least one claude process is alive
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    proc.arguments = ["-x", "claude"]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    try? proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return false }

    // Condition 2: user project logs have been touched recently
    return hasRecentClaudeLogs(withinSeconds: 300)  // 5 minutes
}

/// Scans ~/.claude/projects/ for any file modified within `withinSeconds`.
private func hasRecentClaudeLogs(withinSeconds threshold: TimeInterval) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let projectsDir = "\(home)/.claude/projects"
    let fm = FileManager.default

    guard let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: projectsDir),
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return false }

    let cutoff = Date().addingTimeInterval(-threshold)

    while let url = enumerator.nextObject() as? URL {
        // Only check JSONL files for efficiency
        guard url.pathExtension == "jsonl" else { continue }
        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let modified = values.contentModificationDate,
           modified > cutoff {
            return true
        }
    }
    return false
}

// MARK: - Idle time via IOKit (no permissions required)

private func systemIdleSeconds() -> TimeInterval {
    var iter: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault,
                                              IOServiceMatching("IOHIDSystem"),
                                              &iter)
    guard result == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iter) }

    let entry = IOIteratorNext(iter)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }

    var dict: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = dict?.takeRetainedValue() as? [String: Any],
          let nanos = props["HIDIdleTime"] as? Int64 else { return 0 }

    return TimeInterval(nanos) / 1_000_000_000
}

// MARK: - UsageStore

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var costData: CostData?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isIdle = false

    let settings: Settings
    private let fetcher = UsageFetcher()

    private var refreshTimer: Timer?
    /// Lightweight timer that polls idle state every 15s — independent of refresh timer
    private var idlePollTimer: Timer?
    /// One-shot timer that fires when a usage window resets, triggering an immediate refresh
    private var resetTimer: Timer?
    /// Timestamp when Claude process was first observed as not running (nil = currently running)
    private var claudeGoneSince: Date?

    init(settings: Settings) {
        self.settings = settings
        scheduleRefreshTimer()
        startIdlePollTimer()
        Task { await refresh() }
    }

    // MARK: - Menu bar label

    var menuBarLabel: String {
        if isIdle { return "⏸" }
        guard let snap = snapshot, let value = snap.fiveHourAll else {
            return isLoading ? "…" : "—"
        }
        let pct = settings.showRemaining ? (1.0 - value) * 100 : value * 100
        return "\(Int(pct.rounded()))%"
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil

        // Run heavy I/O off the main thread to keep UI responsive
        let result: (UsageSnapshot?, CostData?, String?) = await Task.detached {
            var snap: UsageSnapshot?
            var err: String?
            do {
                let fetchResult = try await self.fetcher.fetch()
                snap = UsageParser.parse(fetchResult)
            } catch {
                err = error.localizedDescription
            }
            let cost = CostScanner.scan()
            return (snap, cost, err)
        }.value

        snapshot = result.0 ?? snapshot
        costData = result.1
        lastError = result.2
        isLoading = false
        scheduleResetTimer()
    }

    // MARK: - Timer management

    func scheduleRefreshTimer() {
        refreshTimer?.invalidate()

        let interval = Double(settings.refreshInterval) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Only refresh if not idle
                guard !self.isIdle else { return }
                await self.refresh()
            }
        }
    }

    /// Schedule a one-shot timer at the earliest upcoming reset time.
    /// When it fires, we re-fetch so the UI shows fresh post-reset data
    /// instead of stale "11% + 0m" for minutes.
    private func scheduleResetTimer() {
        resetTimer?.invalidate()
        resetTimer = nil

        guard let snap = snapshot else { return }

        // Find the earliest future reset date
        let candidates = [snap.fiveHourResetsDate, snap.weeklyResetsDate].compactMap { $0 }
        guard let earliest = candidates.filter({ $0.timeIntervalSinceNow > 0 }).min() else { return }

        // Fire 5 seconds after reset to give the backend time to update
        let delay = earliest.timeIntervalSinceNow + 5
        resetTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isIdle else { return }
                await self.refresh()
            }
        }
    }

    /// Always-running timer that checks idle state every 15 seconds.
    /// This is independent of the refresh timer so idle is detected promptly.
    private func startIdlePollTimer() {
        idlePollTimer?.invalidate()
        idlePollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkIdleState()
            }
        }
    }

    private func checkIdleState() {
        let thresholdMinutes = settings.idleThresholdMinutes
        guard thresholdMinutes > 0 else {
            // Idle detection disabled
            if isIdle {
                isIdle = false
                claudeGoneSince = nil
            }
            return
        }

        let thresholdSecs = Double(thresholdMinutes) * 60
        let idle = systemIdleSeconds()
        let claudeRunning = isClaudeActive()

        // Track how long Claude has been gone
        if claudeRunning {
            claudeGoneSince = nil
        } else if claudeGoneSince == nil {
            claudeGoneSince = Date()
        }

        // Claude not running counts as idle only after threshold elapsed
        let claudeGoneTooLong: Bool
        if let since = claudeGoneSince {
            claudeGoneTooLong = Date().timeIntervalSince(since) >= thresholdSecs
        } else {
            claudeGoneTooLong = false
        }

        let shouldBeIdle = claudeGoneTooLong || idle >= thresholdSecs

        if shouldBeIdle && !isIdle {
            isIdle = true
        } else if !shouldBeIdle && isIdle {
            isIdle = false
            Task { await refresh() }
        }
    }
}
