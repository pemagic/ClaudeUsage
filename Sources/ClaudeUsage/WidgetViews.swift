import SwiftUI

// MARK: - Fresh Color Palette

extension Color {
    /// Ocean blue — Session usage
    static let widgetBlue = Color(red: 0.29, green: 0.62, blue: 0.96)
    /// Coral pink — Weekly usage
    static let widgetPink = Color(red: 1.0, green: 0.42, blue: 0.54)
    /// Mint green — Cost tracking
    static let widgetGreen = Color(red: 0.31, green: 0.80, blue: 0.44)
    /// Warm purple — Cat / branding
    static let widgetPurple = Color(red: 0.55, green: 0.49, blue: 0.96)
}

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

// MARK: - Small Widget View (160×190)

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
                    .foregroundStyle(Color.widgetPurple)
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
                // Session block
                smallUsageBlock(
                    label: "Session",
                    value: snap.fiveHourAll,
                    resetDate: snap.fiveHourResetsDate,
                    color: .widgetBlue
                )

                Spacer().frame(height: 12)

                // Weekly block
                smallUsageBlock(
                    label: "Weekly",
                    value: snap.weeklyAll,
                    resetDate: snap.weeklyResetsDate,
                    color: .widgetPink
                )

                Spacer()

                // Cost line
                if let cd = store.costData, cd.todayTokens > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.widgetGreen)
                            .frame(width: 6, height: 6)
                        Text("\(cd.formattedTodayCost)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.widgetGreen)
                        Text("today")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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

    func smallUsageBlock(label: String, value: Double?, resetDate: Date?, color: Color) -> some View {
        let remaining = value.map { max(0, min(1, 1.0 - $0)) } ?? 0
        let pct = value.map { v -> Int in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let countdown = widgetCountdown(resetDate)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                if let p = pct {
                    Text("\(p)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * remaining, height: 6)
                }
            }
            .frame(height: 6)

            if let c = countdown {
                Text(c == "Resetting..." ? c : "Resets in \(c)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(Color.widgetPurple)
                }
                Spacer()
                if let badge = store.snapshot?.planName?.replacingOccurrences(of: "Claude ", with: "") {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.widgetPurple.opacity(0.18))
                        .foregroundStyle(Color.widgetPurple)
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
                        color: .widgetBlue,
                        pace: nil
                    )

                    mediumUsageBlock(
                        label: "Weekly",
                        value: snap.weeklyAll,
                        resetDate: snap.weeklyResetsDate,
                        color: .widgetPink,
                        pace: weeklyPace(snap)
                    )
                }

                Spacer()

                // Cost footer
                if let cd = store.costData, cd.todayTokens > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.widgetGreen)
                            .frame(width: 6, height: 6)
                        Text("Today \(cd.formattedTodayCost)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.widgetGreen)
                        Text("·").foregroundStyle(.secondary)
                        Text("\(cd.formattedTodayTokens) tokens")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
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

    func mediumUsageBlock(label: String, value: Double?, resetDate: Date?, color: Color, pace: String?) -> some View {
        let remaining = value.map { max(0, min(1, 1.0 - $0)) } ?? 0
        let pct = value.map { v -> Int in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let countdown = widgetCountdown(resetDate)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                if let p = pct {
                    Text("\(p)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * remaining, height: 7)
                }
            }
            .frame(height: 7)

            if let c = countdown {
                Text(c == "Resetting..." ? c : "Resets in \(c)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let p = pace {
                Text(p)
                    .font(.system(size: 10))
                    .foregroundStyle(color.opacity(0.7))
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
