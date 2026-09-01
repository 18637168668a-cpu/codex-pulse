import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, cpSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInstaller, xml } from '../scripts/installer.mjs';

function fixture(t, overrides = {}) {
  const homeDir = mkdtempSync(join(tmpdir(), 'pulse-installer-'));
  t.after(() => rmSync(homeDir, { recursive: true, force: true }));
  const app = join(homeDir, 'Applications/Codex Pulse.app');
  const root = join(app, 'Contents/Resources');
  const support = join(homeDir, 'Library/Application Support/Codex Pulse OSS');
  const plist = join(homeDir, 'Library/LaunchAgents/io.github.codexpulse.bridge.plist');
  const marker = join(support, 'install.json');
  mkdirSync(join(root, 'bridge'), { recursive: true });
  writeFileSync(join(root, 'bridge/server.mjs'), 'fixture-new');
  writeFileSync(join(root, 'package.json'), '{"version":"0.1.1"}');
  const calls = [];
  const state = { failBootstrap: false, appId: 'io.github.codexpulse.app', busy: false };
  const run = (command, args, optional) => {
    calls.push([command, args, optional]);
    if (command.endsWith('PlistBuddy')) return state.appId;
    if (command.endsWith('which')) return '/fixture/codex';
    if (command.endsWith('ditto')) { cpSync(args.at(-2), args.at(-1), { recursive: true }); return ''; }
    if (command.endsWith('launchctl') && args[0] === 'bootstrap' && state.failBootstrap && !optional) throw new Error('bootstrap failed');
    return '';
  };
  const fetcher = async () => {
    if (state.busy) return { ok: true, json: async () => ({ app: 'codex-pulse' }) };
    throw Object.assign(new Error('offline'), { cause: { code: 'ECONNREFUSED' } });
  };
  const config = { root, homeDir, run, fetcher, platform: 'darwin', env: { PATH: '/fixture/bin', CODEX_BIN: '/fixture/codex' }, node: join(root, 'runtime/node'), uid: 501, ...overrides };
  return { app, root, support, plist, marker, calls, state, config, installer: createInstaller(config) };
}

test('prebuilt installation needs neither Xcode nor a source checkout and defaults radar off', async t => {
  const f = fixture(t);
  await f.installer.install(f.app);
  assert.ok(!f.calls.some(([command]) => command === 'xcodebuild'));
  assert.ok(f.calls.some(([command]) => command.endsWith('codesign')));
  const value = JSON.parse(readFileSync(f.marker, 'utf8'));
  assert.equal(value.app, f.app);
  assert.equal(value.version, '0.1.1');
  assert.equal(value.social, false);
  assert.equal(value.node, join(f.root, 'runtime/node'));
  assert.equal(readFileSync(join(f.support, 'bridge/server.mjs'), 'utf8'), 'fixture-new');
  assert.ok(readFileSync(f.plist, 'utf8').includes('<key>RunAtLoad</key><true/>'));
});

test('source preflight still checks Xcode but creates no files', async t => {
  const f = fixture(t);
  await f.installer.preflight();
  assert.ok(f.calls.some(([command]) => command === 'xcodebuild'));
  assert.ok(!existsSync(f.support));
  assert.ok(!existsSync(f.plist));
});

test('refuses setup from mounted disk images or downloads', async t => {
  const f = fixture(t);
  await assert.rejects(f.installer.install('/Volumes/Codex Pulse/Codex Pulse.app'), /Move Codex Pulse/);
  assert.ok(!existsSync(f.plist));
});

test('refuses unrelated same-name applications without changes', async t => {
  const f = fixture(t);
  f.state.appId = 'org.someone.else';
  await assert.rejects(f.installer.install(f.app), /different app/);
  assert.ok(!existsSync(f.support));
});

test('refuses existing unmanaged LaunchAgents', async t => {
  const f = fixture(t);
  mkdirSync(join(f.config.homeDir, 'Library/LaunchAgents'), { recursive: true });
  writeFileSync(f.plist, 'unmanaged');
  await assert.rejects(f.installer.install(f.app), /Unmanaged launch agent/);
  assert.equal(readFileSync(f.plist, 'utf8'), 'unmanaged');
});

test('refuses an unmanaged server even if it claims the correct application name', async t => {
  const f = fixture(t);
  f.state.busy = true;
  await assert.rejects(f.installer.install(f.app), /port 43187/);
  assert.ok(!existsSync(f.support));
});

test('repair preserves custom Codex home and explicit radar choice', async t => {
  const f = fixture(t, { env: { CODEX_BIN: '/fixture/codex', CODEX_HOME: '/custom/codex & data' } });
  await f.installer.install(f.app);
  f.installer.social('on');
  const next = createInstaller({ ...f.config, env: { CODEX_BIN: '/fixture/codex' } });
  await next.install(f.app);
  const value = JSON.parse(readFileSync(f.marker, 'utf8'));
  assert.equal(value.codexHome, '/custom/codex & data');
  assert.equal(value.social, true);
  assert.ok(readFileSync(f.plist, 'utf8').includes('/custom/codex &amp; data'));
});

test('failed first bootstrap removes new settings and bridge', async t => {
  const f = fixture(t);
  f.state.failBootstrap = true;
  await assert.rejects(f.installer.install(f.app), /bootstrap failed/);
  assert.ok(!existsSync(f.marker));
  assert.ok(!existsSync(f.plist));
  assert.ok(!existsSync(join(f.support, 'bridge')));
  assert.ok(existsSync(f.app));
});

test('failed repair restores previous bridge and settings before restarting it', async t => {
  const f = fixture(t);
  await f.installer.install(f.app);
  const previousPlist = readFileSync(f.plist, 'utf8');
  const previousMarker = readFileSync(f.marker, 'utf8');
  writeFileSync(join(f.root, 'bridge/server.mjs'), 'fixture-update');
  f.state.failBootstrap = true;
  await assert.rejects(f.installer.install(f.app), /bootstrap failed/);
  assert.equal(readFileSync(join(f.support, 'bridge/server.mjs'), 'utf8'), 'fixture-new');
  assert.equal(readFileSync(f.plist, 'utf8'), previousPlist);
  assert.equal(readFileSync(f.marker, 'utf8'), previousMarker);
  assert.ok(f.calls.some(([command, args, optional]) => command.endsWith('launchctl') && args[0] === 'bootstrap' && optional));
});

test('failed radar change rolls back the old option', async t => {
  const f = fixture(t);
  await f.installer.install(f.app);
  f.state.failBootstrap = true;
  assert.throws(() => f.installer.social('on'), /bootstrap failed/);
  assert.equal(JSON.parse(readFileSync(f.marker, 'utf8')).social, false);
});

test('bridge removal retains app and Codex login, moves only managed files to Trash', async t => {
  const f = fixture(t);
  const login = join(f.config.homeDir, '.codex/auth.json');
  mkdirSync(join(f.config.homeDir, '.codex'));
  writeFileSync(login, 'synthetic-login');
  await f.installer.install(f.app);
  f.installer.uninstall(false);
  assert.ok(existsSync(f.app));
  assert.equal(readFileSync(login, 'utf8'), 'synthetic-login');
  assert.ok(!existsSync(f.plist));
  assert.ok(!existsSync(f.support));
  const trash = join(f.config.homeDir, '.Trash');
  assert.ok(existsSync(join(trash, readdirSync(trash)[0], 'Support/install.json')));
});

test('modified managed plist is protected from radar or removal actions', async t => {
  const f = fixture(t);
  await f.installer.install(f.app);
  writeFileSync(f.plist, 'another service');
  assert.throws(() => f.installer.uninstall(false), /does not match/);
  assert.throws(() => f.installer.social('on'), /does not match/);
  assert.equal(readFileSync(f.plist, 'utf8'), 'another service');
});

test('paths are safely XML escaped without invoking a shell', () => {
  assert.equal(xml('A<&>"\''), 'A&lt;&amp;&gt;&quot;&apos;');
});
