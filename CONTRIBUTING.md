# Contributing

Thanks for helping make a tiny utility reliable.

Start with a reproducible issue: macOS version, CPU architecture, Xcode version, Node version, Codex version, and the failing step. Never attach tokens, full account payloads, personal paths, or unredacted logs.

Before opening a pull request:

1. Keep it focused. Discuss substantial new features first.
2. Run `npm test`. Tests must not require a real login or public feed.
3. For UI changes, run `bash scripts/test-native.sh` and inspect both languages, 100% values, long weekly countdowns, and missing data.
4. Run `bash scripts/build.sh` on macOS for native changes.
5. Stage the intended files and run `node scripts/check-release.mjs`.

Please preserve the read-only boundary, explicit missing/stale states, optional social feed, and small dependency surface. No credential scraping, automatic quota resets, account switching, or fake engagement features.

Good first contributions: clean-machine setup feedback, Intel build/install verification, accessible text sizing, and additional languages. Contributions are licensed under the repository's MIT license.
