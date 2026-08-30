# Codex Pulse

**Your Codex quota. A glance away.**

A native macOS desktop widget for **5-hour and weekly usage**, with separate reset countdowns — days included.

[English](README.md) · [简体中文](README.zh-CN.md) · [Install](#quick-start) · [Security](SECURITY.md) · [Contribute](CONTRIBUTING.md)

![Codex Pulse native widget showing two usage percentages and separate reset countdowns](docs/images/hero-en.png)

*Rendered from the actual SwiftUI views. All numbers and posts above are synthetic demo data.*

[![CI](https://github.com/18637168668a-cpu/codex-pulse/actions/workflows/ci.yml/badge.svg)](https://github.com/18637168668a-cpu/codex-pulse/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

## Why this exists

I wanted to glance at my desktop and know two things: **how much have I used, and when does each limit reset?** A weekly countdown that only shows hours isn't enough. A browser tab isn't a desktop widget.

Codex Pulse keeps the answer small, readable, and on the desktop.

- **Used, not remaining:** 5-hour and weekly percentages side by side.
- **Two reset clocks:** each quota has its own countdown, including days.
- **Native SwiftUI + WidgetKit:** small and medium widgets; English and Simplified Chinese follow your system language.
- **Read-only local bridge:** Node.js built-ins only. No Electron, web development server, telemetry, or extra API key.
- **Honest missing-data states:** unavailable values show `—`; cached values are labeled, never replaced by demo percentages.
- **Optional reset radar:** recent public posts from @thsottiaux, filtered with transparent text rules. Off by default. Not an official announcement service.

If this saves you a few trips to the usage page, a ⭐ helps other Codex users find it. Useful bug reports help even more.

## Quick start

**v0.1 is a source-build preview, not a signed/notarized app download.**

You need:

- macOS 14 or later. Apple Silicon has been locally tested; Intel installation is not yet verified.
- Full **Xcode 15+**, selected as the active developer directory. Command Line Tools alone are insufficient. The release build was tested with Xcode 26.4.
- **Node.js 22+** on your PATH.
- **Codex CLI or desktop app**, already signed in with a ChatGPT account whose quota windows are available. API-key-only login is not the intended mode.

```bash
git clone https://github.com/18637168668a-cpu/codex-pulse.git
cd codex-pulse
bash scripts/install.sh --dry-run
bash scripts/install.sh
```

The installer builds locally, uses an ad-hoc signature, installs into `~/Applications`, and registers a user LaunchAgent for the bridge. No sudo or Apple signing certificate is requested. It refuses to overwrite an unrelated app.

Then **right-click the desktop → Edit Widgets → search “Codex Pulse” → add a small or medium widget**. macOS requires this final placement step. You can close the companion app afterwards.

If Codex is installed elsewhere, pass its executable path:

```bash
CODEX_BIN="/path/to/codex" bash scripts/install.sh
```

To update, pull the repository and rerun the installer. Remove/re-add the widget if macOS keeps an old rendered view. See [installation and troubleshooting](docs/INSTALL.md) for paths, manual operation, and removal.

## Optional reset radar

```bash
bash scripts/social.sh on
# Later:
bash scripts/social.sh off
```

Opting in fetches a public third-party feed from [codex-reset.com](https://codex-reset.com). The provider receives a normal HTTPS request, including your IP address, **not your Codex credentials or quota data**.

The radar only considers recent links to @thsottiaux on X. It distinguishes **“possible reset”** from **“reset reported”**, rejects obvious negations, and links back to the post. These are keyword heuristics, not model-based predictions or proof that your account reset. The feed may lag, omit posts, or become unavailable. This project is not affiliated with its provider, X, or OpenAI.

## How it works

```text
Codex login → codex app-server → read-only localhost bridge → WidgetKit
                                 ↑ optional public feed
```

The bridge uses the documented [`account/rateLimits/read`](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt) method and forwards only supported quota fields. It does not start model turns, read chats, redeem resets, or request purchases.

- Listens on `127.0.0.1:43187`; rejects foreign Host/Origin headers; no permissive CORS.
- Caches quota reads for 30 seconds and optional feed reads for 5 minutes, on demand.
- Requests a widget timeline refresh after 5 minutes and supplies minute-resolution countdown entries for an hour. **macOS controls actual refresh timing**; this is not second-by-second quota tracking. See [Apple's refresh guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- Saves the last sanitized widget payload in the widget's sandbox. Credentials remain managed by Codex. Other local processes can reach the loopback endpoint; it is not an authentication boundary.
- Shows only actual 300-minute and 10,080-minute windows. Unsupported or unavailable windows are not guessed.

## Development

No `npm install` is needed; the bridge has no package dependencies.

```bash
npm test                       # bridge, privacy boundaries, failure and radar tests
bash scripts/test-native.sh    # countdown tests + EN/ZH rendered layout previews
bash scripts/build.sh          # local native app build + signature verification
```

| Directory | Purpose |
| --- | --- |
| `native/` | SwiftUI companion app and WidgetKit extension |
| `bridge/` | Restricted stdio client, local HTTP service, optional feed filter |
| `scripts/` | Local build, install, uninstall and radar toggle |
| `tests/` | Synthetic fixtures only; no login required for automated tests |

## Status & roadmap

This is an early, deliberately small release. The local bridge and native build are tested; installation still needs feedback across clean Macs and Codex versions. There is no App Store distribution or notarized binary yet.

Next priorities: clean-machine/Intel testing, better installation diagnostics, accessible larger-text layouts, and additional languages. Feature requests and reproducible reports are welcome; please remove account data from screenshots and logs.

Built with Codex, refined from daily use. [MIT licensed](LICENSE). Independent community project; Codex and macOS belong to their respective owners.
