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
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var isIdle = false

    let settings: Settings
    private let fetcher = UsageFetcher()

    // Two timers: one for normal refresh, one for idle polling
    private var refreshTimer: Timer?
    private var idleWatchTimer: Timer?

    init(settings: Settings) {
        self.settings = settings
        scheduleRefreshTimer()
        Task { await refresh() }
    }

    // MARK: - Menu bar label

    var menuBarLabel: String {
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
        do {
            let raw = try await fetcher.fetch()
            snapshot = UsageParser.parse(raw)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Timer management

    func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        idleWatchTimer?.invalidate()

        let interval = Double(settings.refreshInterval) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleTimerFire()
            }
        }
    }

    private func handleTimerFire() async {
        let idleThreshold = Double(settings.idleThresholdMinutes) * 60
        let idle = systemIdleSeconds()

        if idleThreshold > 0 && idle >= idleThreshold {
            // User is idle — pause normal refresh, start idle watch
            isIdle = true
            refreshTimer?.invalidate()
            startIdleWatchTimer()
        } else {
            // User is active — fetch normally
            isIdle = false
            await refresh()
        }
    }

    /// Polls every 30s while idle to detect when user returns
    private func startIdleWatchTimer() {
        guard idleWatchTimer == nil || !(idleWatchTimer?.isValid ?? false) else { return }
        idleWatchTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.checkIdleReturn()
            }
        }
    }

    private func checkIdleReturn() async {
        let idleThreshold = Double(settings.idleThresholdMinutes) * 60
        let idle = systemIdleSeconds()

        guard idleThreshold <= 0 || idle < idleThreshold else { return }

        // User returned!
        isIdle = false
        idleWatchTimer?.invalidate()
        idleWatchTimer = nil

        // Immediate refresh, then resume normal schedule
        await refresh()
        scheduleRefreshTimer()
    }
}
