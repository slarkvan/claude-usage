# Claude Usage Widget

A macOS menu bar widget that displays your Claude Code usage in real-time.

## Features

- Display Claude Code session and weekly usage percentage in menu bar
- Show account info (email, plan)
- Show reset times for session and weekly quotas
- Auto-refresh every 60 seconds
- Manual refresh and reconnect options

## Screenshot

![Menu Bar](screenshots/menubar.png)

## Requirements

- macOS 13.0+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and logged in
- Optional: `expect` package for better PTY support
  ```bash
  brew install expect
  ```

## Installation

### Download DMG (Recommended)

1. Download the latest DMG from [Releases](https://github.com/anthropics/claude_widget/releases)
2. Open DMG and drag app to Applications folder
3. Run the following command in Terminal (required for unsigned apps):
   ```bash
   find /Applications/ClaudeUsageWidget.app -exec xattr -c {} \;
   ```
4. Open the app from Applications

### Build from Source

```bash
git clone https://github.com/anthropics/claude_widget.git
cd claude_widget

# Build release
./scripts/build-release.sh 1.0.4

# Install
cp -r .build/release/ClaudeUsageWidget.app /Applications/
```

## Usage

Once launched, the widget appears in your menu bar showing:

- `Claude: XX%` - Current session usage percentage
- `Claude: ...` - Connecting
- `Claude: !` - Error (click to see details)

Click the menu bar item to see:
- Session usage and reset time
- Weekly usage and reset time
- Account email and plan
- Refresh / Reconnect / Quit options

## Proxy Support

If you use a proxy (e.g., Clash), the widget will automatically load proxy settings from your shell environment (`~/.zshrc` or `~/.bash_profile`).

## Troubleshooting

### "Error: Status timeout - no data parsed"

1. Make sure Claude Code CLI is installed and working:
   ```bash
   claude --version
   ```
2. Make sure you're logged in to Claude Code
3. Check the debug log:
   ```bash
   cat ~/.claude/widget-debug.log
   ```

### App won't open / "damaged" warning

Run the xattr command to remove quarantine:
```bash
find /Applications/ClaudeUsageWidget.app -exec xattr -c {} \;
```

### Proxy not working

Make sure your proxy environment variables are set in `~/.zshrc`:
```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
```

## How It Works

The widget launches a Claude Code CLI session in the background and sends `/status` commands to fetch usage data. It parses the terminal output (including ANSI escape sequences) to extract usage percentages.

## Debug Log

Debug logs are written to `~/.claude/widget-debug.log`.

## License

MIT
