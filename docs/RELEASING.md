# Releasing Codex Pulse

## Preview release contract

The v0.1.3 preview is a universal macOS 14+ app bundle. Its downloadable files are named `Codex-Pulse-VERSION-universal-unsigned.dmg` and `.zip`. “Unsigned” means **not Developer ID signed**: the app is ad-hoc signed only so its nested code can be checked locally. It is published as a draft prerelease, and users may need to approve it in macOS security settings.

The package includes the official Node.js v22.23.2 Darwin arm64 and x64 runtimes merged into one universal executable. The two official tarballs are pinned by SHA-256 in `scripts/fetch-node-runtime.sh`; that script verifies each checksum before merging them with `lipo`. The Node.js license is shipped as `Codex Pulse.app/Contents/Resources/runtime/NODE-LICENSE.txt`.

No Xcode or external Node installation is required to run a packaged app. The app owns `Contents/Resources/bridge`, `scripts/manage.mjs`, `scripts/installer.mjs`, `package.json`, and `runtime/node`. The GUI invokes:

```text
Contents/Resources/runtime/node Contents/Resources/scripts/manage.mjs install-prebuilt --app /actual/path/Codex Pulse.app
```

Source checkout behavior remains separate: `bash scripts/build.sh` does not download Node and still uses the developer's Node installation.

## Build a preview locally

Use a clean checkout on macOS with full Xcode and Node 22+. The first release build downloads the two pinned Node archives from nodejs.org into the ignored `build/node-runtime-cache/`; later builds reuse the verified cache.

```bash
npm test
bash scripts/test-native.sh
node scripts/check-release.mjs
bash scripts/package-release.sh
```

This produces the DMG and ZIP in `dist/` and verifies the app, universal architectures, embedded resources, ZIP contents, and mounted DMG. Do not rename an artifact to remove `unsigned` unless Developer ID signing and notarization completed.

To refresh a corrupt or intentionally replaced cache:

```bash
bash scripts/fetch-node-runtime.sh --output /tmp/codex-pulse-runtime --refresh
```

## GitHub draft prerelease

Push a tag in the exact form `vMAJOR.MINOR.PATCH` whose value equals `package.json` (for example `v0.1.3`). The workflow checks out that tagged commit, runs bridge and native tests, validates release hygiene, packages the artifacts, and creates a **draft prerelease**. It uses only pinned actions and the workflow token; it does not receive signing credentials.

`workflow_dispatch` is safe only when run from the release tag itself. It repeats exact-tag validation before it can create a release.

## Developer ID signing and notarization

Do not publish a signed-looking build without a valid Developer ID Application certificate and Apple notarization credentials. The current project has only Apple Development credentials, which are insufficient.

When those credentials exist, build the bundled app, then run `scripts/sign-and-notarize.sh` with these environment variables supplied by a secret manager or secure local shell:

```text
DEVELOPER_ID_APPLICATION
APPLE_ID
APPLE_APP_SPECIFIC_PASSWORD
APPLE_TEAM_ID
```

The script fails before modifying the app if any value is absent. It signs the embedded Node binary, widget extension, and app with hardened runtime, submits a temporary ZIP to `notarytool`, waits for acceptance, staples the app, then verifies Gatekeeper assessment. It never prints credential values. Package only this stapled app and state that its release is Developer ID signed and notarized.
