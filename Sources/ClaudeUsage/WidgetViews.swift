import SwiftUI

// MARK: - Widget accent (follows system, single neutral tone)

private let widgetAccent = Color.primary

// MARK: - Shared Helpers

private func widgetFormatDuration(_ s: TimeInterval) -> String {
    let d = Int(s / 86400)
    let h = Int(s.truncatingRemainder(dividingBy: 86400) / 3600)
    let m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func widgetCountdown(_ resetDate: Date?) -> String? {
    guard let d = resetDate else { return nil }
    let secs = d.timeIntervalSinceNow
    if secs <= 0 { return "Resetting..." }
    if secs < 60 { return "<1m" }
    return widgetFormatDuration(secs)
}

// MARK: - Small Widget View (180×190)

struct SmallWidgetView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Text("🐱")
                    .font(.system(size: 14))
                Text("ClaudeUsage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            if store.isIdle {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("⏸").font(.system(size: 24))
                        Text("Paused")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if let snap = store.snapshot {
                smallUsageBlock(
                    label: "Session",
                    value: snap.fiveHourAll,
                    resetDate: snap.fiveHourResetsDate
                )

                Spacer().frame(height: 12)

                smallUsageBlock(
                    label: "Weekly",
                    value: snap.weeklyAll,
                    resetDate: snap.weeklyResetsDate
                )

                Spacer()

                // Cost line
                if let cd = store.costData, cd.todayTokens > 0 {
                    HStack(spacing: 3) {
                        Text("\(cd.formattedTodayCost)")
                            .font(.system(size: 11, weight: .medium))
                        Text("today")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 180, height: 190)
    }

    func smallUsageBlock(label: String, value: Double?, resetDate: Date?) -> some View {
        let remaining = value.map { max(0, min(1, 1.0 - $0)) } ?? 0
        let pct = value.map { v -> Int in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let countdown = widgetCountdown(resetDate)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let p = pct {
                    Text("\(p)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(widgetAccent.opacity(0.1))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(widgetAccent.opacity(0.45))
                        .frame(width: geo.size.width * remaining, height: 5)
                }
            }
            .frame(height: 5)

            if let c = countdown {
                Text(c == "Resetting..." ? c : "Resets in \(c)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Medium Widget View (340×160)

struct MediumWidgetView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content
        }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Text("🐱")
                        .font(.system(size: 14))
                    Text("ClaudeUsage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let badge = store.snapshot?.planName?.replacingOccurrences(of: "Claude ", with: "") {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(widgetAccent.opacity(0.08))
                        .foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.bottom, 10)

            if store.isIdle {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("⏸").font(.system(size: 20))
                        Text("Paused (\(settings.idleThresholdMinutes)m idle)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if let snap = store.snapshot {
                // Two columns: Session | Weekly
                HStack(alignment: .top, spacing: 16) {
                    mediumUsageBlock(
                        label: "Session",
                        value: snap.fiveHourAll,
                        resetDate: snap.fiveHourResetsDate,
                        pace: nil
                    )

                    mediumUsageBlock(
                        label: "Weekly",
                        value: snap.weeklyAll,
                        resetDate: snap.weeklyResetsDate,
                        pace: weeklyPace(snap)
                    )
                }

                Spacer()

                // Cost footer
                if let cd = store.costData, cd.todayTokens > 0 {
                    HStack(spacing: 4) {
                        Text("Today \(cd.formattedTodayCost)")
                            .font(.system(size: 11, weight: .medium))
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(cd.formattedTodayTokens) tokens")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 340, height: 160)
    }

    func mediumUsageBlock(label: String, value: Double?, resetDate: Date?, pace: String?) -> some View {
        let remaining = value.map { max(0, min(1, 1.0 - $0)) } ?? 0
        let pct = value.map { v -> Int in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let countdown = widgetCountdown(resetDate)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let p = pct {
                    Text("\(p)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(widgetAccent.opacity(0.1))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(widgetAccent.opacity(0.45))
                        .frame(width: geo.size.width * remaining, height: 5)
                }
            }
            .frame(height: 5)

            if let c = countdown {
                Text(c == "Resetting..." ? c : "Resets in \(c)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let p = pace {
                Text(p)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func weeklyPace(_ snap: UsageSnapshot) -> String? {
        guard let usage = snap.weeklyAll,
              let resetDate = snap.weeklyResetsDate else { return nil }

        let remaining = resetDate.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        let total: TimeInterval = 7 * 24 * 3600
        let elapsed = total - remaining
        guard elapsed > 300 else { return nil }

        let expectedByNow = elapsed / total
        let ahead = usage > expectedByNow
        let pctDiff = Int((abs(usage - expectedByNow) * 100).rounded())
        let sign = ahead ? "+" : "−"

        return "\(ahead ? "Ahead" : "Behind") (\(sign)\(pctDiff)%)"
    }
}
