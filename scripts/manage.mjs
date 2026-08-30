import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { codexBinary } from '../bridge/codex.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const label = 'io.github.codexpulse.bridge';
const appId = 'io.github.codexpulse.app';
const homeDir = homedir();
const support = join(homeDir, 'Library/Application Support/Codex Pulse OSS');
const app = join(homeDir, 'Applications/Codex Pulse.app');
const plist = join(homeDir, 'Library/LaunchAgents', `${label}.plist`);
const marker = join(support, 'install.json');
const domain = `gui/${process.getuid?.()}`;
const xml = value => String(value).replace(/[<>&"']/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]));
const run = (command, args, optional = false) => {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0 && !optional) throw new Error(`${command} failed: ${result.stderr || result.error?.message || result.status}`);
  return result.stdout?.trim();
};
function assertOwnedApp() {
  if (!existsSync(app)) return;
  if (run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', join(app, 'Contents/Info.plist')]) !== appId) {
    throw new Error('A different app already exists at ~/Applications/Codex Pulse.app. Move it aside yourself before installing.');
  }
}
async function preflight() {
  if (process.platform !== 'darwin') throw new Error('macOS is required.');
  if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Node.js 22+ is required.');
  run('xcodebuild', ['-version']);
  run(codexBinary(), ['--version']);
  assertOwnedApp();
  if (existsSync(plist) && !existsSync(marker)) throw new Error('Unmanaged launch agent exists; refusing to overwrite it.');
  try {
    const response = await fetch('http://127.0.0.1:43187/health', { signal: AbortSignal.timeout(1000) });
    const data = await response.json();
    if (data.app !== 'codex-pulse' || !existsSync(marker)) throw new Error('Port 43187 is already in use. Stop that service first.');
  } catch (error) {
    if (error.cause?.code !== 'ECONNREFUSED') throw error;
  }
  console.log('Preflight passed: macOS, Xcode, Node and Codex detected. No changes made.');
}
function saveAgent(settings) {
  mkdirSync(dirname(plist), { recursive: true });
  const env = {
    PATH: process.env.PATH || '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin',
    CODEX_BIN: settings.codex,
    PULSE_SOCIAL: settings.social ? '1' : '0',
    ...(settings.codexHome ? { CODEX_HOME: settings.codexHome } : {}),
  };
  writeFileSync(plist, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(settings.node)}</string><string>${xml(join(support, 'bridge/server.mjs'))}</string></array>
<key>WorkingDirectory</key><string>${xml(support)}</string>
<key>EnvironmentVariables</key><dict>${Object.entries(env).map(([k, v]) => `<key>${xml(k)}</key><string>${xml(v)}</string>`).join('')}</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>30</integer>
</dict></plist>`, { mode: 0o600 });
  writeFileSync(marker, JSON.stringify(settings, null, 2) + '\n', { mode: 0o600 });
  run('launchctl', ['bootout', `${domain}/${label}`], true);
  run('launchctl', ['bootstrap', domain, plist]);
}
async function install() {
  await preflight();
  const built = join(root, 'build/Codex Pulse.app');
  if (!existsSync(built)) throw new Error('Run bash scripts/build.sh first.');
  mkdirSync(support, { recursive: true, mode: 0o700 });
  mkdirSync(dirname(app), { recursive: true });
  const previous = existsSync(marker) ? JSON.parse(readFileSync(marker, 'utf8')) : null;
  if (existsSync(app)) {
    const backup = join(support, 'backups', String(Date.now()));
    mkdirSync(backup, { recursive: true });
    run('ditto', ['--norsrc', '--noextattr', app, join(backup, 'Codex Pulse.app')]);
  }
  run('ditto', ['--norsrc', '--noextattr', built, app]);
  // iCloud source folders can attach Finder metadata. Strip only our installed build's metadata.
  run('xattr', ['-cr', app]);
  run('codesign', ['--verify', '--deep', '--strict', app]);
  cpSync(join(root, 'bridge'), join(support, 'bridge'), { recursive: true });
  const binary = codexBinary();
  const resolved = binary === 'codex' ? run('/usr/bin/which', ['codex']) : binary;
  saveAgent({ version: '0.1.0', appId, app, node: process.execPath, codex: resolved, codexHome: process.env.CODEX_HOME || previous?.codexHome, social: previous?.social ?? (process.env.PULSE_SOCIAL === '1') });
  run('pluginkit', ['-a', join(app, 'Contents/PlugIns/CodexPulseWidgetExtension.appex')]);
  run('open', [app]);
  console.log('Installed. Right-click desktop → Edit Widgets → Codex Pulse. The bridge starts at login.');
}
function social(value) {
  if (!['on', 'off'].includes(value)) throw new Error('Usage: bash scripts/social.sh on|off');
  if (!existsSync(marker)) throw new Error('Install first.');
  const settings = JSON.parse(readFileSync(marker, 'utf8'));
  if (settings.appId !== appId) throw new Error('Unknown installation.');
  saveAgent({ ...settings, social: value === 'on' });
  run('open', ['codexpulse://refresh']);
  console.log(`Optional third-party feed ${value}. ${value === 'on' ? 'codex-reset.com receives normal HTTPS requests (including your IP), never your quota or Codex credentials.' : ''}`);
}
function uninstall() {
  if (!existsSync(marker)) throw new Error('No managed installation found. Nothing removed.');
  const settings = JSON.parse(readFileSync(marker, 'utf8'));
  if (settings.appId !== appId) throw new Error('Unknown installation. Nothing removed.');
  assertOwnedApp();
  run('launchctl', ['bootout', `${domain}/${label}`], true);
  if (existsSync(app)) run('pluginkit', ['-r', join(app, 'Contents/PlugIns/CodexPulseWidgetExtension.appex')], true);
  const recovery = join(homeDir, '.Trash', `Codex-Pulse-${Date.now()}`);
  mkdirSync(recovery, { recursive: true });
  if (existsSync(app)) renameSync(app, join(recovery, 'Codex Pulse.app'));
  if (existsSync(plist)) renameSync(plist, join(recovery, `${label}.plist`));
  renameSync(support, join(recovery, 'Support'));
  console.log(`App, bridge and launch agent moved to Trash: ${recovery}. Codex credentials were not touched. Remove the widget from your desktop separately.`);
}
try {
  const action = process.argv[2];
  if (action === 'preflight') await preflight();
  else if (action === 'install') await install();
  else if (action === 'social') social(process.argv[3]);
  else if (action === 'uninstall') uninstall();
  else throw new Error('Expected preflight, install, social or uninstall.');
} catch (error) { console.error(error.message); process.exitCode = 1; }
