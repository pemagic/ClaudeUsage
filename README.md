# ClaudeUsage

**macOS menu bar app that monitors your Claude Code usage in real time.**

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-blue" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

## Features

- **Menu bar percentage** — see your current session usage at a glance (cat icon 🐱)
- **Session & weekly limits** — track 5-hour session and 7-day weekly usage with progress bars
- **Pace prediction** — shows if you're ahead/behind expected weekly consumption, with run-out estimates
- **Reset countdown** — real-time countdown to next session/weekly reset
- **Cost tracking** — scans local JSONL logs to calculate daily & 30-day token cost (per-model pricing)
- **Auto-sleep** — pauses polling when your Mac is idle (configurable: 1m–1h), resumes on return
- **Lightweight** — pure Swift/SwiftUI, SPM only, no Xcode project needed, ~1200 lines total

## How It Works

ClaudeUsage launches `claude --allowed-tools ""` in a PTY, sends the `/usage` command, and parses the TUI output. Cost data comes from scanning `~/.claude/projects/**/*.jsonl` session logs with per-token pricing aligned to Anthropic's published rates.

## Install

### Download

Grab the latest `ClaudeUsage.app.zip` from [Releases](../../releases).

### Build from Source

Requires **macOS 13+** and **Swift 5.9+** (Xcode 15 or swiftly/swift toolchain).

```bash
git clone https://github.com/pemagic/ClaudeUsage.git
cd ClaudeUsage
bash build.sh
cp -r ClaudeUsage.app /Applications/
```

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Refresh Interval | 1m, 3m, 5m, 10m, 30m | 5m |
| Auto-sleep After | Never, 1m, 5m, 10m, 30m, 1h | 30m |
| Display | Remaining / Used | Remaining |
| Launch at Login | On / Off | Off |

## Requirements

- macOS 13 Ventura or later
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (`~/.local/bin/claude` or on PATH)
- Claude Max plan (usage data only available on Max)

## License

MIT

---

# ClaudeUsage

**在 macOS 菜单栏实时监控 Claude Code 用量。**

## 功能特性

- **菜单栏百分比显示** — 一眼看到当前会话用量（猫咪图标 🐱）
- **会话 & 周用量** — 追踪 5 小时会话限制和 7 天周限制，带进度条
- **用量预测** — 显示周用量消耗速度是超前还是落后，预估耗尽时间
- **重置倒计时** — 实时显示距离下次会话/周重置的剩余时间
- **费用追踪** — 扫描本地 JSONL 日志，按模型单价计算每日和 30 天 token 费用
- **自动休眠** — 电脑空闲时自动暂停轮询（可配置：1分钟–1小时），回来自动恢复
- **轻量** — 纯 Swift/SwiftUI，仅用 SPM，无需 Xcode 工程，总共约 1200 行代码

## 工作原理

ClaudeUsage 通过 PTY 启动 `claude --allowed-tools ""`，发送 `/usage` 命令并解析 TUI 输出。费用数据来自扫描 `~/.claude/projects/**/*.jsonl` 会话日志，按 Anthropic 官方公布的模型单价计算。

## 安装

### 直接下载

从 [Releases](../../releases) 页面下载最新的 `ClaudeUsage.app.zip`。

### 从源码构建

需要 **macOS 13+** 和 **Swift 5.9+**（Xcode 15 或 swiftly/swift 工具链）。

```bash
git clone https://github.com/pemagic/ClaudeUsage.git
cd ClaudeUsage
bash build.sh
cp -r ClaudeUsage.app /Applications/
```

## 设置选项

| 设置项 | 可选值 | 默认值 |
|--------|--------|--------|
| 刷新间隔 | 1分钟, 3分钟, 5分钟, 10分钟, 30分钟 | 5分钟 |
| 自动休眠 | 从不, 1分钟, 5分钟, 10分钟, 30分钟, 1小时 | 30分钟 |
| 显示方式 | 剩余 / 已用 | 剩余 |
| 登录时启动 | 开 / 关 | 关 |

## 系统要求

- macOS 13 Ventura 或更高版本
- 已安装 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)（`~/.local/bin/claude` 或在 PATH 中）
- Claude Max 计划（仅 Max 计划有用量数据）

## 许可证

MIT
