# Installation & troubleshooting

## What gets installed

| Item | Location |
| --- | --- |
| App and WidgetKit extension | `~/Applications/Codex Pulse.app` |
| Bridge and install settings | `~/Library/Application Support/Codex Pulse OSS/` |
| User LaunchAgent | `~/Library/LaunchAgents/io.github.codexpulse.bridge.plist` |
| Local endpoint | `http://127.0.0.1:43187` |

Only a logged-in user's service is installed. No root service, firewall rule or global security change is needed. `install.sh --dry-run` checks tools, existing app identity and port availability without installing. It does not verify your account login or claim full clean-machine compatibility.

## Prerequisites

Install full Xcode from Apple, open it once and complete its first-run setup. Ensure `xcodebuild -version` resolves to that Xcode; selecting a different developer directory is a system setup choice you perform yourself.

Install Node.js 22 or later and sign into Codex normally. For a CLI installation, use `codex login` with your ChatGPT account. If no binary is on PATH, the bridge checks the standard Codex and ChatGPT app resource paths. Override with `CODEX_BIN=/absolute/path/to/codex` if necessary. If you intentionally use a non-default `CODEX_HOME`, set it during installation; it is kept only in your local install settings.

Run the commands in the [README](../README.md#quick-start), then add the widget through the macOS desktop widget gallery. The app can be closed; the LaunchAgent keeps the bridge available at login. Your Mac must be awake and online for fresh account data.

## Common problems

**Widget missing from the gallery:** open the installed app once, close/reopen the gallery, and search “Codex Pulse” or “Codex Usage”. If still missing, check the extension registration with:

```bash
pluginkit -m -A -D -i io.github.codexpulse.app.widget
```

**No data / cached:** open Codex Pulse and use Refresh widgets. Verify you are signed into Codex with ChatGPT rather than an API-key-only session. An unsupported quota window remains unavailable, not zero. Check the bridge without exposing credentials:

```bash
curl http://127.0.0.1:43187/health
curl http://127.0.0.1:43187/api/local/usage
```

The second command prints personal usage values. Do not paste them publicly without reviewing them. A 503 means the bridge could not obtain supported quota data; it is not proof that your quota is exhausted.

**Countdown is waiting/updating:** the cached reset timestamp has passed. A new account read is needed. The app does not assume your quota reset just because the clock reached zero.

**Old layout after update:** close the companion app, reopen it, and request refresh. If needed, remove and re-add the widget. macOS can retain rendered timelines. Do not disable system security or kill unrelated system services to refresh a widget.

**Port conflict:** stop the other service or choose another port in both the native source and bridge configuration, then rebuild. The packaged native app expects port 43187. `PULSE_PORT` by itself only changes the standalone bridge.

**Node or Codex moved after an upgrade:** rerun the installer to update the LaunchAgent's absolute executable paths. If another unrelated app already uses the install location, move it aside manually; the installer will not overwrite it.

**Signing warnings:** the source build uses a local ad-hoc signature. It is not a notarized downloadable app. If your managed Mac blocks local builds, follow your organization's policy; this project does not provide a security-bypass script.

## Manual development mode

```bash
node bridge/server.mjs
# In another terminal:
bash scripts/build.sh
```

This starts no LaunchAgent. `PULSE_SOCIAL=1 node bridge/server.mjs` explicitly enables third-party feed requests. Do not run a second bridge on the installed service's port.

## Remove

```bash
bash scripts/uninstall.sh
```

The managed app, bridge directory and LaunchAgent are moved to a timestamped folder in Trash. They can be recovered; reinstallation is the simplest way to start again. Codex credentials are not touched. Remove the desktop widget separately. macOS may retain the widget sandbox's last-known sanitized payload after removal.

Build scripts retain generated files under `build/` and temporary `codex-pulse-build.*` / `codex-pulse-preview.*` directories. These are not part of the repository or the running installation.
