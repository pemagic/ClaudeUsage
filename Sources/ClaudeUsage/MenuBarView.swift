import AppKit
import SwiftUI

// MARK: - Pace helpers

struct PaceInfo {
    let ahead: Bool
    let percentDiff: Int
    let runsOutIn: TimeInterval?
}

private func calcWeeklyPace(usage: Double, resetDate: Date) -> PaceInfo? {
    let now = Date()
    let remaining = resetDate.timeIntervalSince(now)
    guard remaining > 0 else { return nil }

    let total: TimeInterval = 7 * 24 * 3600
    let elapsed = total - remaining
    guard elapsed > 300 else { return nil } // Need >5 min of data

    let expectedByNow = elapsed / total
    let ahead = usage > expectedByNow
    let pctDiff: Int = Int((abs(usage - expectedByNow) * 100).rounded())

    let rate = usage / elapsed // fraction per second
    let runsOut: TimeInterval? = rate > 0 ? {
        let t = max(0, 1.0 - usage) / rate
        return t < remaining ? t : nil
    }() : nil

    return PaceInfo(ahead: ahead, percentDiff: pctDiff, runsOutIn: runsOut)
}

private func formatDuration(_ s: TimeInterval) -> String {
    let d = Int(s / 86400)
    let h = Int(s.truncatingRemainder(dividingBy: 86400) / 3600)
    let m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// MARK: - Main view

struct MenuBarView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var settings: Settings
    @State private var showSettings = false

    private let accent = Color(red: 0.72, green: 0.45, blue: 0.20)
    private let panelWidth: CGFloat = 295

    var body: some View {
        // TimelineView forces re-render every 30s so countdowns tick down
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Group {
                if showSettings {
                    SettingsPanelView(showSettings: $showSettings)
                } else {
                    mainView
                }
            }
        }
        .frame(width: panelWidth)
    }

    // MARK: - Main layout

    var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            contentSection
            Divider()
            footerSection
        }
    }

    // MARK: - Header

    var headerSection: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.snapshot?.modelName ?? "Claude")
                    .font(.system(size: 17, weight: .bold))
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let badge = store.snapshot?.planName?.replacingOccurrences(of: "Claude ", with: "") {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.18))
                    .foregroundStyle(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var headerSubtitle: String {
        if store.isIdle, let snap = store.snapshot {
            return "💤 Sleeping · \(timeAgo(snap.fetchedAt))"
        }
        if let snap = store.snapshot { return "Updated \(timeAgo(snap.fetchedAt))" }
        if store.isLoading { return "Updating..." }
        return "Not updated"
    }

    private func timeAgo(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        return "\(Int(s / 3600))h ago"
    }

    // MARK: - Content

    @ViewBuilder
    var contentSection: some View {
        if store.isIdle, let snap = store.snapshot {
            idleBanner
            usageContent(snap: snap)
        } else if store.isIdle {
            idleView
        } else if let snap = store.snapshot {
            usageContent(snap: snap)
        } else if store.isLoading {
            loadingView
        } else {
            errorView
        }
    }

    @ViewBuilder
    func usageContent(snap: UsageSnapshot) -> some View {
        usageBlock(title: "Session",
                   value: snap.fiveHourAll,
                   resetDate: snap.fiveHourResetsDate,
                   pace: nil)

        Divider()
        let pace: PaceInfo? = {
            guard let u = snap.weeklyAll, let d = snap.weeklyResetsDate else { return nil }
            return calcWeeklyPace(usage: u, resetDate: d)
        }()
        usageBlock(title: "Weekly",
                   value: snap.weeklyAll ?? 0.0,
                   resetDate: snap.weeklyResetsDate,
                   pace: pace)

        Divider()
        usageBlock(title: "Sonnet",
                   value: (snap.weeklyOpus ?? snap.fiveHourOpus) ?? 0.0,
                   resetDate: snap.weeklyResetsDate ?? snap.fiveHourResetsDate,
                   pace: nil)

        Divider()
        costSection()
    }

    // MARK: - Usage block

    func usageBlock(title: String, value: Double?, resetDate: Date?, pace: PaceInfo?) -> some View {
        let remaining = value.map { max(0, min(1, 1.0 - $0)) } ?? 0
        let pct = value.map { v -> Int in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let countdownStr: String? = resetDate.flatMap { d -> String? in
            let secs = d.timeIntervalSinceNow
            if secs <= 0 { return "Resetting..." }
            if secs < 60 { return "<1m" }
            return formatDuration(secs)
        }

        return VStack(alignment: .leading, spacing: 0) {
            // Section title
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .padding(.bottom, 8)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(accent.opacity(0.15))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(accent)
                        .frame(width: geo.size.width * remaining, height: 10)
                }
            }
            .frame(height: 10)
            .padding(.bottom, 7)

            // % left  ·  reset countdown
            HStack(alignment: .firstTextBaseline) {
                if let p = pct {
                    Text(settings.showRemaining ? "\(p)% left" : "\(p)% used")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                if let c = countdownStr {
                    Text(c == "Resetting..." ? c : "Resets in \(c)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Pace line (weekly only)
            if let p = pace {
                Text(paceText(p))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func paceText(_ p: PaceInfo) -> String {
        let sign = p.ahead ? "+" : ""
        let base = "Pace: \(p.ahead ? "Ahead" : "Behind") (\(sign)\(p.percentDiff)%)"
        if let t = p.runsOutIn {
            return base + " · Runs out in \(formatDuration(t))"
        }
        return base
    }

    // MARK: - Cost section

    func costSection() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cost")
                .font(.system(size: 16, weight: .bold))

            if let cd = store.costData, cd.last30DaysTokens > 0 {
                HStack(spacing: 4) {
                    Text("Today:")
                        .foregroundStyle(.secondary)
                    Text(cd.formattedTodayCost)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(cd.formattedTodayTokens) tokens").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))

                HStack(spacing: 4) {
                    Text("Last 30 days:")
                        .foregroundStyle(.secondary)
                    Text(cd.formattedMonthlyCost)
                    Text("·").foregroundStyle(.secondary)
                    Text("\(cd.formattedMonthlyTokens) tokens").foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            } else {
                Text("Scanning logs...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - State views

    var idleBanner: some View {
        HStack(spacing: 5) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10))
            Text("Sleeping · Cached Data")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(accent.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(accent.opacity(0.06))
    }

    var idleView: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
            Text("Sleeping")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Fetching usage...")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    var errorView: some View {
        Text(store.lastError ?? "No data")
            .font(.system(size: 13)).foregroundStyle(.red)
            .padding(.horizontal, 16).padding(.vertical, 18)
    }

    // MARK: - Footer

    var footerSection: some View {
        VStack(spacing: 0) {
            footerRow("Refresh Now", icon: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            Divider()
            footerRow("Settings...", icon: "gear") { showSettings = true }
            Divider()
            aboutSection
            Divider()
            footerRow("Quit ClaudeUsage", icon: nil) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - About (silkscreen style)

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var aboutSection: some View {
        HoverButton(action: {
            NSWorkspace.shared.open(URL(string: "https://github.com/pemagic/ClaudeUsage")!)
        }) {
            VStack(spacing: 3) {
                Text("ClaudeUsage v\(appVersion)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.quaternary)
                Text("github.com/pemagic/ClaudeUsage")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }

    func footerRow(_ label: String, icon: String?, action: @escaping () -> Void) -> some View {
        HoverButton(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                }
                Text(label)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Hover Button (highlight + haptic)

struct HoverButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .onHover { hovering in
            if hovering && !isHovered {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment, performanceTime: .now)
                NSSound.tink?.play()
            }
            isHovered = hovering
        }
    }
}

private extension NSSound {
    /// Short, subtle system sound for hover feedback
    static let tink: NSSound? = {
        let s = NSSound(named: "Tink")
        s?.volume = 0.15
        return s
    }()
}

// MARK: - Settings Panel

struct SettingsPanelView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var store: UsageStore
    @Binding var showSettings: Bool

    private let accent = Color(red: 0.72, green: 0.45, blue: 0.20)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nav header
            HStack {
                Button { showSettings = false } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(accent)

                Spacer()
                Text("Settings").font(.system(size: 15, weight: .bold))
                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Back")
                }.opacity(0)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)

            Divider()

            settingRow("Refresh Interval") {
                HStack(spacing: 6) {
                    ForEach(Settings.refreshOptions, id: \.self) { min in
                        pillButton(min == 1 ? "1m" : "\(min)m",
                                   active: settings.refreshInterval == min) {
                            settings.refreshInterval = min
                            store.scheduleRefreshTimer()
                        }
                    }
                }
            }

            Divider()

            settingRow("Auto-sleep After") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Settings.idleOptions, id: \.minutes) { opt in
                        radioButton(opt.label,
                                    selected: settings.idleThresholdMinutes == opt.minutes) {
                            settings.idleThresholdMinutes = opt.minutes
                            store.scheduleRefreshTimer()
                        }
                    }
                }
            }

            Divider()

            settingRow("Display") {
                HStack(spacing: 6) {
                    pillButton("Remaining", active: settings.showRemaining) { settings.showRemaining = true }
                    pillButton("Used",      active: !settings.showRemaining) { settings.showRemaining = false }
                }
            }

            Divider()

            settingRow("Desktop Widget") {
                HStack(spacing: 6) {
                    pillButton("Off", active: settings.widgetMode == 0) { settings.widgetMode = 0 }
                    pillButton("Small", active: settings.widgetMode == 1) { settings.widgetMode = 1 }
                    pillButton("Medium", active: settings.widgetMode == 2) { settings.widgetMode = 2 }
                }
            }

            Divider()

            settingRow(nil) {
                radioButton("Launch at Login", selected: settings.launchAtLogin) {
                    settings.launchAtLogin.toggle()
                }
            }
        }
    }

    func pillButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(active ? accent.opacity(0.22) : Color.primary.opacity(0.07))
                .foregroundStyle(active ? accent : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    func radioButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : Color.secondary)
                Text(label).font(.system(size: 13))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func settingRow<C: View>(_ title: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}
