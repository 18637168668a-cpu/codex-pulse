import { cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { codexBinary } from '../bridge/codex.mjs';

const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const label = 'io.github.codexpulse.bridge';
const appId = 'io.github.codexpulse.app';
export const xml = value => String(value).replace(/[<>&"']/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' }[c]));
function systemRun(command, args, optional = false) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 30000 });
  // Never surface arbitrary subprocess diagnostics: Codex can include account details.
  if (result.status !== 0 && !optional) throw new Error(`${command.split('/').at(-1)} failed. Check installation, permissions and the setup guide.`);
  return result.stdout?.trim() || '';
}

// Dependency injection isolates installer tests from real user applications and services.
export function createInstaller({ root = defaultRoot, homeDir = homedir(), run = systemRun,
  fetcher = fetch, platform = process.platform, env = process.env,
  node = process.execPath, uid = process.getuid?.(), codex = () => codexBinary() } = {}) {
  const support = join(homeDir, 'Library/Application Support/Codex Pulse OSS');
  const defaultApp = join(homeDir, 'Applications/Codex Pulse.app');
  const plist = join(homeDir, 'Library/LaunchAgents', `${label}.plist`);
  const marker = join(support, 'install.json');
  const domain = `gui/${uid}`;
  const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
  const allowedApp = app => [defaultApp, '/Applications/Codex Pulse.app'].includes(app);
  function assertApp(app) {
    if (!allowedApp(app)) throw new Error('Move Codex Pulse.app into Applications (or your user Applications folder), then reopen it before setup.');
    if (existsSync(app) && run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', join(app, 'Contents/Info.plist')]) !== appId) {
      throw new Error('A different app occupies the install location. Move it aside yourself; nothing was overwritten.');
    }
  }
  function settings() {
    if (!existsSync(marker)) {
      if (existsSync(plist)) throw new Error('Unmanaged launch agent exists; refusing to change it.');
      return null;
    }
    const value = JSON.parse(readFileSync(marker, 'utf8'));
    if (value.appId !== appId || !allowedApp(value.app) || !isAbsolute(value.node || '') || !isAbsolute(value.codex || '')) {
      throw new Error('Unknown installation. Nothing changed.');
    }
    if (existsSync(plist)) {
      const installed = readFileSync(plist, 'utf8');
      if (!installed.includes(`<string>${label}</string>`) || !installed.includes(`<string>${xml(join(support, 'bridge/server.mjs'))}</string>`) || !installed.includes(`<string>${xml(value.node)}</string>`)) {
        throw new Error('Launch agent does not match the managed installation. Nothing changed.');
      }
    }
    return value;
  }
  async function preflight(prebuiltApp) {
    if (platform !== 'darwin') throw new Error('macOS is required.');
    if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Node.js 22+ is required.');
    const app = prebuiltApp ? resolve(prebuiltApp) : defaultApp;
    assertApp(app);
    const previous = settings();
    if (previous && previous.app !== app && existsSync(previous.app)) throw new Error('Another Codex Pulse installation exists. Remove its local bridge and app before changing install locations.');
    if (prebuiltApp) {
      if (!existsSync(app)) throw new Error('The downloaded app was not found.');
      if (resolve(root) !== join(app, 'Contents/Resources')) throw new Error('Run setup from the downloaded app itself.');
      run('/usr/bin/codesign', ['--verify', '--deep', '--strict', app]);
    } else run('xcodebuild', ['-version']);
    let binary = env.CODEX_BIN || codex();
    if (!isAbsolute(binary)) binary = run('/usr/bin/which', [binary]);
    if (!isAbsolute(binary)) throw new Error('Codex was not found. Install Codex and sign in with ChatGPT first.');
    run(binary, ['--version']);
    try {
      const response = await fetcher('http://127.0.0.1:43187/health', { signal: AbortSignal.timeout(1500) });
      const data = await response.json();
      if (!response.ok || data.app !== 'codex-pulse' || !previous) throw new Error('Unmanaged service.');
    } catch (error) {
      if (error.cause?.code !== 'ECONNREFUSED') throw new Error('Cannot safely use local port 43187. Stop any conflicting service and retry.');
    }
    console.log('Preflight passed. No changes made.');
    return { app, previous, binary };
  }
  function agentText(value) {
    const variables = {
      PATH: env.PATH || '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin',
      CODEX_BIN: value.codex, PULSE_SOCIAL: value.social ? '1' : '0',
      ...(value.codexHome ? { CODEX_HOME: value.codexHome } : {}),
    };
    return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${label}</string>
<key>ProgramArguments</key><array><string>${xml(value.node)}</string><string>${xml(join(support, 'bridge/server.mjs'))}</string></array>
<key>WorkingDirectory</key><string>${xml(support)}</string>
<key>EnvironmentVariables</key><dict>${Object.entries(variables).map(([k, v]) => `<key>${xml(k)}</key><string>${xml(v)}</string>`).join('')}</dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>30</integer>
</dict></plist>\n`;
  }
  function saveAgent(value, beforeReload = () => {}) {
    const oldPlist = existsSync(plist) ? readFileSync(plist) : null;
    const oldMarker = existsSync(marker) ? readFileSync(marker) : null;
    mkdirSync(dirname(plist), { recursive: true });
    mkdirSync(support, { recursive: true, mode: 0o700 });
    try {
      run('/bin/launchctl', ['bootout', `${domain}/${label}`], true);
      writeFileSync(plist, agentText(value), { mode: 0o600 });
      writeFileSync(marker, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
      run('/bin/launchctl', ['bootstrap', domain, plist]);
    } catch (error) {
      beforeReload();
      if (oldPlist) writeFileSync(plist, oldPlist); else rmSync(plist, { force: true });
      if (oldMarker) writeFileSync(marker, oldMarker); else rmSync(marker, { force: true });
      if (oldPlist) run('/bin/launchctl', ['bootstrap', domain, plist], true);
      throw error;
    }
  }
  async function install(prebuiltApp) {
    const { app, previous, binary } = await preflight(prebuiltApp);
    const built = join(root, 'build/Codex Pulse.app');
    if (!prebuiltApp && !existsSync(built)) throw new Error('Run bash scripts/build.sh first.');
    mkdirSync(support, { recursive: true, mode: 0o700 });
    const backup = join(support, 'backups', `${Date.now()}-${process.pid}`);
    mkdirSync(backup, { recursive: true });
    const bridge = join(support, 'bridge');
    const hadBridge = existsSync(bridge);
    const hadApp = existsSync(app);
    if (hadBridge) cpSync(bridge, join(backup, 'bridge'), { recursive: true });
    if (!prebuiltApp && hadApp) run('/usr/bin/ditto', [app, join(backup, 'Codex Pulse.app')]);
    let rolledBack = false;
    const rollback = () => {
      if (rolledBack) return;
      rolledBack = true;
      rmSync(bridge, { recursive: true, force: true });
      if (hadBridge) cpSync(join(backup, 'bridge'), bridge, { recursive: true });
      if (!prebuiltApp) {
        rmSync(app, { recursive: true, force: true });
        if (hadApp) run('/usr/bin/ditto', [join(backup, 'Codex Pulse.app'), app]);
      }
    };
    try {
      if (!prebuiltApp) {
        mkdirSync(dirname(app), { recursive: true });
        rmSync(app, { recursive: true, force: true });
        run('/usr/bin/ditto', ['--norsrc', '--noextattr', built, app]);
        run('/usr/bin/codesign', ['--verify', '--deep', '--strict', app]);
      }
      rmSync(bridge, { recursive: true, force: true });
      cpSync(join(root, 'bridge'), bridge, { recursive: true });
      saveAgent({ version, appId, app, node, codex: binary,
        codexHome: env.CODEX_HOME || previous?.codexHome,
        social: previous?.social ?? (env.PULSE_SOCIAL === '1') }, rollback);
    } catch (error) { rollback(); throw error; }
    run('/usr/bin/pluginkit', ['-a', join(app, 'Contents/PlugIns/CodexPulseWidgetExtension.appex')], true);
    if (!prebuiltApp) run('/usr/bin/open', [app], true);
    console.log('Local bridge enabled at login. Add Codex Pulse using Edit Widgets.');
  }
  function social(value) {
    if (!['on', 'off'].includes(value)) throw new Error('Expected social on|off.');
    const previous = settings();
    if (!previous) throw new Error('Enable the local bridge first.');
    saveAgent({ ...previous, social: value === 'on' });
    console.log(value === 'on' ? 'Reset radar enabled. codex-reset.com receives normal HTTPS request metadata, never Codex credentials or quota data.' : 'Reset radar disabled.');
  }
  function uninstall(removeApp) {
    const previous = settings();
    if (!previous) throw new Error('No managed local bridge found. Nothing removed.');
    if (removeApp) assertApp(previous.app);
    run('/bin/launchctl', ['bootout', `${domain}/${label}`], true);
    const recovery = join(homeDir, '.Trash', `Codex-Pulse-${Date.now()}-${process.pid}`);
    mkdirSync(recovery, { recursive: true });
    if (removeApp && existsSync(previous.app)) {
      run('/usr/bin/pluginkit', ['-r', join(previous.app, 'Contents/PlugIns/CodexPulseWidgetExtension.appex')], true);
      renameSync(previous.app, join(recovery, 'Codex Pulse.app'));
    }
    if (existsSync(plist)) renameSync(plist, join(recovery, `${label}.plist`));
    renameSync(support, join(recovery, 'Support'));
    console.log('Managed local bridge moved to Trash. Codex login was not touched.' + (removeApp ? ' Remove the desktop widget separately.' : ' You can now move the app to Trash separately.'));
  }
  return { preflight, install, social, uninstall };
}
