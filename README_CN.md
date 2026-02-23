# ClaudeUsage

**一个原生 macOS 菜单栏应用，实时监控你的 Claude Code 用量。**

<p align="center">
  <img src="https://img.shields.io/badge/平台-macOS_13%2B-blue" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" />
  <img src="https://img.shields.io/badge/SPM-兼容-brightgreen" />
  <img src="https://img.shields.io/badge/许可证-MIT-green" />
</p>

<p align="center">
  <a href="README.md">🇺🇸 English</a>
</p>

<p align="center">
  <img src="assets/screenshot-menubar.svg" width="320" alt="ClaudeUsage 弹出面板" />
  &nbsp;&nbsp;&nbsp;
  <img src="assets/screenshot-idle.svg" width="320" alt="ClaudeUsage 空闲状态" />
</p>

## 为什么做 ClaudeUsage？

Claude Max 计划有会话（5小时）和周（7天）用量限制，但没有方便的方式查看消耗了多少——你得打开 CLI 手动运行 `/usage`。ClaudeUsage 安静地待在菜单栏，一眼就能看到百分比，还有消耗速度预测、重置倒计时和费用追踪。

## ClaudeUsage vs CodexBar

> **一句话总结** — ClaudeUsage 直接读取官方 CLI 的用量数据。不碰钥匙串，不逆向 API，不靠可能悄悄出错的 token 计算。772 KB，零依赖，开箱即用。

### 安全与合规

| | ClaudeUsage | CodexBar |
|---|---|---|
| **数据获取方式** | 通过 PTY 启动官方 `claude` CLI，读取 `/usage` 输出 | 从 macOS 钥匙串读取 OAuth token，直接向 `api.anthropic.com` 发送 HTTP 请求；还可回退到浏览器 cookie |
| **合规性** | 使用官方 CLI，和你手动输入 `/usage` 完全一致 | 从钥匙串提取凭证并调用未公开的 OAuth 端点，可能违反 [Anthropic 使用政策](https://www.anthropic.com/policies) |
| **钥匙串访问** | 从不接触钥匙串 | 读取 `Claude Code-credentials`；Chrome cookie 解密也需要钥匙串 |
| **网络请求** | 零 — 所有数据来自本地 CLI 进程 | 向 Anthropic API 发送 HTTP 请求，读取 Safari/Chrome/Firefox 浏览器 cookie |
| **所需权限** | 无 | 可选完全磁盘访问权限（Safari cookie）+ 钥匙串访问弹窗 |

### 精确性

| | ClaudeUsage | CodexBar |
|---|---|---|
| **用量百分比来源** | 官方 CLI `/usage` 输出 — Anthropic 权威数据 | 从 JSONL token 日志自行计算（估算值） |
| **新模型支持** | 自动 — CLI 本身已包含所有模型 | 需手动更新定价表；**缺失 `claude-sonnet-4-6`** 导致[每天 $101 凭空消失](https://github.com/steipete/CodexBar) |
| **消息去重** | 全局 `message.id` 去重，跨所有文件 | 仅文件内去重 — 同一消息跨项目目录重复计算 2 次以上 |
| **准确性风险** | 用量百分比零风险 — 和 Anthropic 显示的完全一致 | JSONL 日志平均 **每条消息 1.7 条重复记录**（最高 5 条）；去重不当 → 费用虚高 2–4 倍 |
| **已知数据 Bug** | — | Credits 差了[好几个数量级](https://github.com/steipete/CodexBar/issues/321)；统计数据[与 CLI 不一致](https://github.com/steipete/CodexBar/issues/341) |

### 体积与简洁性

| | ClaudeUsage | CodexBar |
|---|---|---|
| **应用体积** | **772 KB** | ~50 MB（大 65 倍） |
| **代码规模** | ~10 个 Swift 文件 | 453 个 Swift 文件，共 576 个文件 |
| **依赖项** | 零 | Sparkle, SweetCookieKit, swift-syntax, Commander, swift-log, KeyboardShortcuts |
| **最低系统** | macOS 13 (Ventura) | macOS 14 (Sonoma) |
| **稳定性** | v1.0 正式版 | Beta (v0.18.0-beta.3)；[钥匙串弹窗风暴](https://github.com/steipete/CodexBar/issues)、[Tahoe 启动失败](https://github.com/steipete/CodexBar/issues/363) |
| **构建** | `bash build.sh` — 无需 Xcode | 完整 SPM + 宏 + 多构建目标 |

### 功能对比

| 功能 | ClaudeUsage | CodexBar |
|------|---|---|
| 会话 + 周用量百分比 | ✅ | ✅ |
| 重置倒计时 | ✅ | ✅ |
| 消耗速度预测 & 耗尽预估 | ✅ | ❌ |
| 费用追踪（本地 JSONL） | ✅ | ✅ |
| 智能空闲检测（IOKit） | ✅ | ❌ |
| 多 Provider（OpenAI、Cursor、Gemini…） | ❌ 仅 Claude | ✅ 20 个 Provider |
| 费用历史图表 | ❌ | ✅ |
| 桌面小组件（WidgetKit） | ❌ | ✅ |
| CLI 工具 | ❌ | ✅ |
| Linux 支持 | ❌ | ✅（仅 CLI） |
| 登录时启动 | ✅ | ✅ |

### 总结

**选 ClaudeUsage** — 如果你用 Claude Code，想要一个轻量、精确、尊重隐私的监控工具，读取官方数据，从不碰你的凭证。772 KB，零配置，零风险。

**选 CodexBar** — 如果你需要一个支持 20+ AI 服务的统一仪表盘，且不介意更大的体积、Beta 阶段的稳定性、钥匙串访问弹窗，以及直接提取 API 凭证带来的合规风险。

## 功能特性

### 用量监控
- **菜单栏指示器** — 猫咪图标 🐱 旁显示当前会话用量百分比，始终可见
- **会话限制** — 5 小时滚动窗口用量，带进度条
- **周限制** — 7 天用量，带进度条（全模型 + Sonnet 单独统计）
- **重置倒计时** — 实时显示距离重置的时间，如"Resets in 2d 5h"

### 消耗速度预测
- **超前 / 落后** — 将你的实际消耗与线性预期速度对比
- **耗尽预估** — 如果消耗过快，显示预计何时用完（如"Runs out in 1d 3h"）

### 费用追踪
- 本地扫描 `~/.claude/projects/**/*.jsonl` 会话日志
- 支持 Opus 4.5/4.6、Sonnet 4.5/4.6、Haiku 及旧版模型的独立定价
- 支持阶梯定价（Sonnet 超过 200K token 阈值后价格更高）
- 显示**今日费用**和**最近 30 天**费用及 token 数量
- 通过 `message.id` 去重（流式输出会产生累积的多行记录）

### 智能空闲检测
- 每 15 秒通过 IOKit `HIDIdleTime` 检测系统空闲时间
- 达到空闲阈值后暂停所有轮询，菜单栏显示 ⏸
- 用户回来后自动恢复并立即刷新
- 可配置：1 分钟、5 分钟、10 分钟、30 分钟、1 小时、或从不

### 设置选项
- **刷新间隔** — 1分钟, 3分钟, 5分钟, 10分钟, 30分钟
- **自动休眠** — 空闲后暂停（1分钟–1小时，或从不）
- **显示模式** — 显示剩余 % 或已用 %
- **登录时启动** — 通过 SMAppService 实现

## 架构设计

```
┌─────────────────────────────────────────────────────────┐
│                    ClaudeUsageApp                        │
│              MenuBarExtra (.window 样式)                 │
│         ┌──────────┐    ┌──────────────┐                │
│         │ 猫咪图标 │    │  用量百分比  │                │
│         └──────────┘    └──────────────┘                │
├─────────────────────────────────────────────────────────┤
│                      MenuBarView                        │
│  ┌──────────┬──────────┬──────────┬──────────────────┐  │
│  │ 会话用量 │ 周用量   │ Sonnet   │   费用统计       │  │
│  │ + 进度条 │ + 进度条 │ + 进度条 │  今日 / 30 天    │  │
│  │ + 重置   │ + 重置   │ + 重置   │  $ + Token 数    │  │
│  │          │ + 速度   │          │                  │  │
│  └──────────┴──────────┴──────────┴──────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                      UsageStore                         │
│          @MainActor, @Published 属性                    │
│  ┌────────────────┐  ┌──────────────────────┐           │
│  │  refreshTimer  │  │   idlePollTimer      │           │
│  │  (可配置间隔)  │  │   (每 15 秒)         │           │
│  └───────┬────────┘  └──────────┬───────────┘           │
│          │                      │                       │
│          ▼                      ▼                       │
│  ┌─── Task.detached ───┐  ┌─ checkIdleState() ─┐       │
│  │  (后台线程执行)     │  │ IOKit HIDIdleTime   │       │
│  │                     │  │ → 暂停 / 恢复       │       │
│  │  UsageFetcher.fetch │  └─────────────────────┘       │
│  │  UsageParser.parse  │                               │
│  │  CostScanner.scan   │                               │
│  └─────────────────────┘                               │
└─────────────────────────────────────────────────────────┘

数据来源:
┌────────────────────────┐    ┌──────────────────────────┐
│    Claude CLI (PTY)    │    │  ~/.claude/projects/     │
│  openpty → /usage 命令 │    │    **/*.jsonl            │
│  → ANSI 剥离 + 解析   │    │  → token 费用扫描        │
└────────────────────────┘    └──────────────────────────┘
```

### 数据流

1. **定时器触发** → 主线程调用 `UsageStore.refresh()`
2. **`Task.detached`** 将所有重 I/O 移到后台线程：
   - `UsageFetcher.fetch()` — 通过 PTY 启动 `claude --allowed-tools ""`，等待欢迎界面结束（600ms 安静），发送 `/usage`，读取到停止字符串
   - `UsageParser.parse()` — 剥离 ANSI 转义码（包括 `ESC[NC` 光标右移 → 替换为空格），提取百分比和重置时间
   - `CostScanner.scan()` — 遍历 `~/.claude/projects/` 下最近 30 天修改的 JSONL 文件，提取每条消息的 token 用量，按 message ID 去重，应用每模型定价
3. **回到主线程** — 更新 Published 属性，SwiftUI 重新渲染

### 项目结构

```
ClaudeUsage/
├── Package.swift              # SPM 清单 (macOS 13+, Swift 5.9)
├── build.sh                   # 构建 + .app 包组装脚本
├── Resources/
│   ├── Info.plist             # LSUIElement=YES (不显示 Dock 图标)
│   └── AppIcon.icns           # 生成的猫咪图标
├── Scripts/
│   └── make-icon.swift        # CoreGraphics 图标生成器
└── Sources/ClaudeUsage/
    ├── ClaudeUsageApp.swift   # @main 入口, MenuBarExtra, NSImage 猫咪图标
    ├── MenuBarView.swift      # SwiftUI 弹出界面, 速度计算
    ├── UsageStore.swift       # 状态管理, 定时器, 空闲检测
    ├── UsageFetcher.swift     # PTY 命令行交互 (actor)
    ├── UsageParser.swift      # ANSI 剥离, 百分比和重置时间解析
    ├── UsageData.swift        # UsageSnapshot 数据模型
    ├── CostScanner.swift      # JSONL 日志扫描, 每模型定价
    └── Settings.swift         # UserDefaults, SMAppService
```

## 安装

### 直接下载（推荐）

1. 从[最新 Release](../../releases/latest) 下载 `ClaudeUsage.app.zip`
2. 解压后将 `ClaudeUsage.app` 拖入 `/Applications/`
3. 打开应用 — 猫咪图标出现在菜单栏

### 从源码构建

需要 **macOS 13+** 和 **Swift 5.9+**（Xcode 15 命令行工具或独立 Swift 工具链）。

```bash
git clone https://github.com/pemagic/ClaudeUsage.git
cd ClaudeUsage
bash build.sh
cp -r ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

`build.sh` 执行 `swift build -c release`，生成应用图标，组装 `.app` 包。无需 Xcode 工程文件。

## 使用方法

启动后点击菜单栏的猫咪图标，弹出面板：

- **Session（会话）** — 5 小时滚动窗口用量（如"72% left · Resets in 3h 42m"）
- **Weekly（周）** — 7 天用量及消耗速度（如"Ahead (+12%) · Runs out in 2d 5h"）
- **Sonnet** — Sonnet 模型单独统计（如有）
- **Cost（费用）** — 今日和最近 30 天的估算费用及 token 数
- **Refresh Now** — 立即手动刷新
- **Settings** — 配置刷新间隔、空闲阈值、显示模式

当你停止使用电脑后，菜单栏显示 **⏸**，所有轮询暂停。移动鼠标或按键后自动恢复。

## 技术细节

- CLI 工作目录设为 `/tmp/claudeusage-probe`，避免 macOS TCC 对桌面/文档目录的权限弹窗
- `env -u CLAUDECODE` 防止从 Claude Code 会话内启动时出现"嵌套会话"错误
- 欢迎界面可能加载 10KB+ 的 skill 数据才出现 `/usage` 输出——获取器等待 600ms "安静期"而非固定延迟
- ANSI 光标右移码（`ESC[1C`）在"current week"中出现，剥离时替换为空格
- 费用扫描使用 C 语言 `fgets` 逐行读取，内存效率高
- Sonnet 阶梯定价：超过 200K token 后使用更高的每 token 单价

## 定价表

| 模型 | 输入 ($/MTok) | 输出 ($/MTok) | 缓存读取 | 缓存创建 |
|------|:---:|:---:|:---:|:---:|
| Opus 4.5/4.6 | $5 | $25 | $0.50 | $6.25 |
| Opus 4.1 | $15 | $75 | $1.50 | $18.75 |
| Sonnet 4.5/4.6 | $3 | $15 | $0.30 | $3.75 |
| Sonnet (>200K) | $6 | $22.50 | $0.60 | $7.50 |
| Haiku 4.5 | $1 | $5 | $0.10 | $1.25 |

价格对齐 Anthropic 官方公布的 API 定价（2025 年 2 月）。

## 系统要求

- macOS 13 Ventura 或更高版本
- 已安装 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 并已登录
- Claude **Max** 计划（用量数据仅 Max 可用）

## 许可证

[MIT](LICENSE)
