# Changelog

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
