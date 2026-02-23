import Foundation
import IOKit
import SwiftUI

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
                let raw = try await self.fetcher.fetch()
                snap = UsageParser.parse(raw)
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
            }
            return
        }

        let thresholdSecs = Double(thresholdMinutes) * 60
        let idle = systemIdleSeconds()

        if idle >= thresholdSecs && !isIdle {
            // Transition: active → idle
            isIdle = true
        } else if idle < thresholdSecs && isIdle {
            // Transition: idle → active (user returned)
            isIdle = false
            // Immediate refresh on return
            Task { await refresh() }
        }
    }
}
