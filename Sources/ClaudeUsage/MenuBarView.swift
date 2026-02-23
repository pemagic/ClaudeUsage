import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var settings: Settings

    var body: some View {
        Group {
            usageSection
            Divider()
            settingsMenu
            Divider()
            Button("↺ Refresh Now") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r", modifiers: [])
            Divider()
            Button("Quit ClaudeUsage") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Usage section

    @ViewBuilder
    var usageSection: some View {
        if store.isIdle {
            HStack {
                Image(systemName: "moon.zzz")
                Text("已休眠（\(settings.idleThresholdMinutes) 分钟无操作）")
                    .foregroundStyle(.secondary)
            }
        } else if let snap = store.snapshot {
            Text("当前会话")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            usageRow(label: "5h（全部模型）",
                     value: snap.fiveHourAll,
                     resetIn: snap.fiveHourResetsAt)
            usageRow(label: "5h（Opus）",
                     value: snap.fiveHourOpus,
                     resetIn: nil)
            Divider()
            Text("本周")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            usageRow(label: "周用量（全部）",
                     value: snap.weeklyAll,
                     resetIn: snap.weeklyResetsAt)
            usageRow(label: "周用量（Opus）",
                     value: snap.weeklyOpus,
                     resetIn: nil)
            Divider()
            Text("更新于 \(snap.fetchedAt, style: .time)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } else if store.isLoading {
            HStack {
                ProgressView().scaleEffect(0.6)
                Text("正在获取用量…").foregroundStyle(.secondary)
            }
        } else {
            Text(store.lastError ?? "暂无数据").foregroundStyle(.red)
        }
    }

    func usageRow(label: String, value: Double?, resetIn: String?) -> some View {
        let pct: Int? = value.map { v in
            let ratio = settings.showRemaining ? (1.0 - v) : v
            return Int((ratio * 100).rounded())
        }
        let display = pct.map { p in
            resetIn.map { "\(p)% · \($0)" } ?? "\(p)%"
        } ?? "—"
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

    // MARK: - Settings menu

    @ViewBuilder
    var settingsMenu: some View {
        Menu("⚙ 设置") {
            // Refresh interval
            Menu("刷新间隔") {
                ForEach(Settings.refreshOptions, id: \.self) { minutes in
                    Button {
                        settings.refreshInterval = minutes
                        store.scheduleRefreshTimer()
                    } label: {
                        HStack {
                            if settings.refreshInterval == minutes {
                                Image(systemName: "checkmark")
                            }
                            Text(minutes == 1 ? "1 分钟" : "\(minutes) 分钟")
                        }
                    }
                }
            }

            Divider()

            // Idle / auto-sleep threshold
            Menu("自动休眠") {
                ForEach(Settings.idleOptions, id: \.minutes) { option in
                    Button {
                        settings.idleThresholdMinutes = option.minutes
                        store.scheduleRefreshTimer()
                    } label: {
                        HStack {
                            if settings.idleThresholdMinutes == option.minutes {
                                Image(systemName: "checkmark")
                            }
                            Text(option.label)
                        }
                    }
                }
            }

            Divider()

            // Display mode
            Menu("显示方式") {
                Button {
                    settings.showRemaining = true
                } label: {
                    HStack {
                        if settings.showRemaining { Image(systemName: "checkmark") }
                        Text("剩余用量")
                    }
                }
                Button {
                    settings.showRemaining = false
                } label: {
                    HStack {
                        if !settings.showRemaining { Image(systemName: "checkmark") }
                        Text("已用用量")
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
                    Text("开机启动")
                }
            }
        }
    }
}
