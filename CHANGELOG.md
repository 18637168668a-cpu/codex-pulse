# Changelog

## 0.1.3 — clearer Tibo radar typography

- Enlarged the Tibo reset radar title, status label, message, reason and footer text.
- Kept the CP quota meter colors, countdowns, radar behavior, and read-only boundaries unchanged.

## 0.1.2 — widget contrast patch

- Improved widget text contrast against the dark gradient background.
- Kept cyan/purple quota accents, countdowns, radar behavior, and read-only boundaries unchanged.

## 0.1.1 — downloadable unnotarized prerelease

- Universal macOS 14+ DMG and ZIP distribution with bundled Node.js and local bridge.
- GUI actions: **Enable/repair bridge**, **Remove local bridge**, and explicit reset radar enable/disable controls (radar off by default).
- Requires Codex CLI or desktop app already signed in with a ChatGPT account.
- Ad-hoc signed and unnotarized; prerelease only. Intel execution and clean-machine installation remain unverified.

## 0.1.0 — source preview

- Native small and medium macOS widgets, with English and Simplified Chinese.
- Side-by-side 5-hour and weekly **used** percentages.
- Separate day/hour/minute reset countdowns.
- Standalone read-only Node bridge using built-in modules only.
- Explicit missing data, stale-cache states, and no fake live percentages.
- Optional opt-in third-party reset radar with source links and heuristic labels.
- Local build, install, radar toggle and recoverable uninstall scripts.
- Synthetic layout previews, quota/privacy/HTTP/stdio/radar tests, and GitHub CI.

Known limitations: source builds require full Xcode and Node; no notarized binary; WidgetKit refresh is system-scheduled; clean-machine installation and Intel support need more validation; the optional third-party feed may lag or fail.
