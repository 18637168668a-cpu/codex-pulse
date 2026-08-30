# Security & privacy

Codex Pulse is a local, read-only utility. It uses Codex's existing login via `codex app-server` and requests only `account/rateLimits/read` after initialization. It does not read `auth.json`, browser cookies, conversations, or token files directly. It never invokes resets, payments, or model turns.

The localhost API returns an explicit allowlist of quota fields plus freshness metadata. Raw account responses and subprocess diagnostics are not logged. No telemetry or analytics is included. The widget keeps a sanitized last-known payload in its own sandbox; uninstalling the app does not guarantee macOS clears that sandbox immediately.

The bridge binds to IPv4 loopback and checks Host, Origin and cross-site fetch metadata. It does not expose arbitrary RPC or enable CORS. This reduces browser-origin and DNS-rebinding risks, but **other processes on the same Mac can access the endpoint**. Do not proxy it onto a public interface or a multi-user network. Codex itself still contacts its normal services to read account limits.

Optional social radar is off by default. When enabled, it contacts `https://codex-reset.com/api/feed`; that provider receives the usual network metadata. No account data is sent. Feed content is untrusted plain text, not executable instructions. Only recent HTTPS links to the intended X account are accepted. Classification is heuristic and may be incorrect. Clicking a source link opens X in your browser.

Local builds use ad-hoc signatures, not Apple notarization. The installer does not disable Gatekeeper, change global security settings, install system-wide services, or request sudo. Inspect scripts before running them.

## Reporting

Use this repository's **Security → Report a vulnerability** when private reporting is available. Do not put tokens, account dumps, or exploit details containing private data in public issues. For non-sensitive reliability bugs, use the bug template with synthetic values or a redacted screenshot.

Before committing, run `node scripts/check-release.mjs`. This is a lightweight safeguard, not a substitute for a security audit.
