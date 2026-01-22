# Claude Code 使用量状态栏小工具

## 项目概述

这是一个 macOS 状态栏小工具，用于实时显示 Claude Code 的 API 使用量。它通过与 Claude Code CLI 交互，自动获取并展示 Opus 和 Sonnet 模型的使用百分比。

## 核心功能

- 在 macOS 状态栏显示 Claude 使用量百分比
- 支持查看 Opus（当前会话）和 Sonnet（每周配额）的使用情况
- 显示配额重置时间
- 每 60 秒自动刷新数据
- 支持手动刷新和重新连接

## 技术方案

### 架构设计

```
┌─────────────────┐
│   StatusBar     │  ← 用户界面层（状态栏 + 下拉菜单）
└────────┬────────┘
         │
┌────────▼────────┐
│ StatusBarController │  ← 控制层（协调各组件）
└────────┬────────┘
         │
┌────────▼────────┐
│ ClaudePTYSession │  ← PTY 会话层（与 Claude CLI 交互）
└────────┬────────┘
         │
┌────────▼────────┐
│  StatusParser   │  ← 数据解析层（解析 ANSI 输出）
└─────────────────┘
```

### 核心模块说明

#### 1. main.swift - 程序入口

```swift
// 创建无 Dock 图标的后台应用
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // 关键：隐藏 Dock 图标
app.run()
```

#### 2. StatusBarController.swift - 状态栏控制器

**职责：**
- 创建和管理状态栏图标
- 构建下拉菜单
- 协调 PTY 会话和 UI 更新
- 管理定时刷新任务

**状态栏显示格式：**
- `Claude O: XX%` - Opus 模型使用量
- `Claude S: XX%` - Sonnet 模型使用量
- `Claude: ...` - 正在连接
- `Claude: X` - 会话未运行
- `Claude: !` - 发生错误

**菜单结构：**
```
┌─────────────────────┐
│ Status: Connected   │  ← 连接状态
├─────────────────────┤
│ Opus: 85%          │  ← Opus 使用量
│ Sonnet: 21%        │  ← Sonnet 使用量
├─────────────────────┤
│ Resets: 3pm        │  ← 重置时间
├─────────────────────┤
│ Refresh Now    ⌘R  │  ← 手动刷新
│ Reconnect          │  ← 重新连接
├─────────────────────┤
│ Quit           ⌘Q  │  ← 退出程序
└─────────────────────┘
```

#### 3. ClaudePTYSession.swift - PTY 会话管理

**核心挑战：**
Claude Code CLI 使用交互式终端 UI（TUI），不支持直接命令行参数获取状态。因此需要通过 PTY（伪终端）模拟真实终端环境。

**解决方案：**

1. **PTY 模拟** - 使用 `unbuffer` 或 `script` 命令创建伪终端环境
   ```swift
   // 优先使用 unbuffer（需要安装 expect）
   if useUnbuffer {
       process?.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/unbuffer")
       process?.arguments = ["-p", claudePath]
   } else {
       // 回退到 script 命令
       process?.executableURL = URL(fileURLWithPath: "/bin/bash")
       process?.arguments = ["-c", "script -q /dev/null \(claudePath)"]
   }
   ```

2. **自动确认信任对话框**
   ```swift
   // 启动后 3 秒自动按回车确认
   DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
       self.sendInput("\r")
   }
   ```

3. **发送 /status 命令并导航到 Usage 标签**
   ```swift
   func sendStatus() {
       sendInput("/status")           // 输入命令
       sendInput("\t")                // Tab 自动补全
       sendInput("\r")                // 回车执行
       sendInput("\u{1B}[C")          // 右箭头导航
       sendInput("\u{1B}[C")          // 再次右箭头到 Usage 标签
   }
   ```

**会话状态检测：**
- 检测主提示符（`❯` 或 `? for shortcuts`）表示会话就绪
- 区分信任对话框和主界面，避免误判

#### 4. StatusParser.swift - 状态解析器

**职责：**
- 清除 ANSI 转义序列
- 从终端输出中提取使用量数据

**ANSI 清除正则：**
```swift
let pattern = "\\x1B\\[[0-9;]*[a-zA-Z]|\\x1B\\][^\\x07]*\\x07|..."
```

**数据提取模式：**
```swift
// 使用量模式: "XX% used"
let percentPattern = "(\\d+)%\\s*used"

// 重置时间模式: "Resets 3pm" 或 "Resets Jan 27, 4pm"
let resetPattern = "Resets?\\s+([^\\n]+)"
```

**解析逻辑：**
1. 按行遍历，查找 `% used` 模式
2. 根据上下文（current session / current week）判断是 Opus 还是 Sonnet
3. 提取重置时间信息

## 数据模型

```swift
struct UsageData {
    var opusPercent: Int?    // Opus 使用百分比
    var sonnetPercent: Int?  // Sonnet 使用百分比
    var resetTime: String?   // 重置时间
}
```

## 文件结构

```
claude_widget/
├── Package.swift              # Swift 包配置
└── Sources/
    ├── main.swift             # 程序入口
    ├── AppDelegate.swift      # 应用代理
    ├── StatusBarController.swift  # 状态栏控制
    ├── ClaudePTYSession.swift # PTY 会话管理
    └── StatusParser.swift     # 输出解析
```

## 依赖要求

- macOS 13.0+
- Swift 5.9+
- Claude Code CLI（已安装并可用）
- 可选：expect 包（用于 unbuffer 命令，提供更好的 PTY 支持）
  ```bash
  brew install expect
  ```

## 构建与运行

```bash
# 构建
swift build -c release

# 运行
.build/release/ClaudeUsageWidget

# 或直接运行（调试模式）
swift run
```

## 调试日志

程序会将调试日志写入 `~/.claude/widget-debug.log`，包含：
- PTY 会话启动过程
- 发送的命令和时间
- 原始终端输出
- 解析结果

## 实现难点与解决方案

### 难点 1：Claude CLI 无直接 API

**问题：** Claude Code CLI 是交互式 TUI 应用，没有提供直接获取状态的命令行参数。

**解决：** 通过 PTY 会话模拟真实终端，发送键盘输入获取数据。

### 难点 2：ANSI 转义序列

**问题：** 终端输出包含大量 ANSI 颜色和控制序列，难以直接解析。

**解决：** 使用正则表达式清除所有 ANSI 转义序列后再解析。

### 难点 3：异步输出处理

**问题：** 终端输出是流式的，数据可能分多次到达。

**解决：**
- 使用输出缓冲区累积数据
- 设置超时机制（15秒）
- 检测特定模式后延迟解析，确保数据完整

### 难点 4：信任对话框

**问题：** Claude 首次运行会显示信任文件夹对话框。

**解决：** 启动后延迟发送回车键自动确认。

## 未来改进方向

1. **更可靠的状态获取** - 等待 Claude Code 提供官方 API
2. **通知功能** - 当使用量接近限制时发送系统通知
3. **历史记录** - 记录使用量变化趋势
4. **多账户支持** - 支持切换不同的 Claude 账户
5. **UI 美化** - 添加图标、进度条等视觉元素
