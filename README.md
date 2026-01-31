# PRs and Issues Preview

A macOS menu bar app for monitoring GitHub pull requests and issues across multiple repositories.

## Features

- **Menu bar icon** with PR count badge
- **PR list** grouped by repository with last commit message
- **Issues section** with hover descriptions
- **Click to open** PRs in Ghostty + your editor
- **Auto-refresh** every 15 minutes
- **System notifications** for new commits and comments
- **GitHub Actions status** display (pass/fail/pending)

## Requirements

- macOS 14.0+ (Sonoma)
- Command Line Tools (`xcode-select --install`)
- [Ghostty](https://ghostty.org) - Terminal emulator (PRs open in Ghostty tabs)
- [Neovim](https://neovim.io) - Text editor
- [nvim-raccoon](https://github.com/bajor/nvim-raccoon) - Neovim plugin for PR review

## Installation

```bash
# Build and install to /Applications
make install-app

# Or manually:
make build-app
cp -r ".build/PRs and Issues Preview.app" /Applications/

# Run it
open "/Applications/PRs and Issues Preview.app"

# Uninstall
make uninstall-app
```

### Xcode Development

To open in Xcode:
```bash
open Package.swift
```

For code signing, copy the template and add your Team ID:
```bash
cp Config/Signing.xcconfig.template Config/Signing.xcconfig
# Edit Config/Signing.xcconfig with your DEVELOPMENT_TEAM
```

## Configuration

Create `~/.config/pr-review/config.json`:

```json
{
  "github_token": "ghp_your_default_token",
  "github_username": "your-username",
  "repos": [
    "owner/repo-name",
    "my-org/project",
    "another-org/service"
  ],
  "excluded_repos": [
    "my-org/internal-tools",
    "another-org/archived-project"
  ],
  "tokens": {
    "my-org": "ghp_token_for_my_org",
    "another-org": "ghp_token_for_another_org"
  },
  "clone_root": "~/.local/share/pr-review/repos",
  "poll_interval_seconds": 300,
  "ghostty_path": "/Applications/Ghostty.app",
  "nvim_path": "/opt/homebrew/bin/nvim",
  "notifications": {
    "new_commits": true,
    "new_comments": true,
    "sound": true
  }
}
```

**Token resolution:** When accessing a repo, the app checks if the owner/org exists in the `tokens` map. If found, that token is used; otherwise falls back to `github_token`.

**Auto-discovery:** If `repos` is not specified, the app auto-discovers repos from your tokens.

**Excluding repos:** Use `excluded_repos` to hide specific repos from the PR list. This is useful when using auto-discovery but wanting to ignore certain repos.

### Auto-Start on Login

The app can be configured to start automatically on login. A LaunchAgent is created at:
```
~/Library/LaunchAgents/com.prsandissuespreview.plist
```

To enable/disable:
```bash
# Enable
launchctl load ~/Library/LaunchAgents/com.prsandissuespreview.plist

# Disable
launchctl unload ~/Library/LaunchAgents/com.prsandissuespreview.plist
```

## Usage

Once running, you'll see **"PR"** (or **"PR N"** where N is the count) in your menu bar.

**Menu Bar Features:**
- Shows all open PRs from configured repos
- Displays PR title and last commit message
- Click a PR to clone/update and open in Ghostty with Neovim + Raccoon plugin
- **Issues section** - Shows all open issues from configured repos
  - Hover to see issue description
  - Click "Go to GitHub" to open issue in browser
- **Open All PRs** - Opens all PRs in separate Ghostty tabs
- **Refresh** - Manually refresh PR list
- **Quit** - Exit the app

**Ghostty Behavior:**
- If Ghostty is already running -> PR opens in a **new tab** (Cmd+T)
- If Ghostty is not running -> Ghostty launches and **maximizes** (Cmd+Shift+F)

## Development

```bash
# Run all tests and linting
make test

# Run Swift tests only
make test-app

# Build the macOS app
make build-app

# Clean build artifacts
make clean
```

## License

MIT
