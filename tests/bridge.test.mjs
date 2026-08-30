import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CodexBridge, normalizeUsage } from '../bridge/codex.mjs';
import { createPulseServer } from '../bridge/server.mjs';
import { analyzeResetSignal, filterSignals } from '../bridge/social.mjs';

const window = (duration, used = 27) => ({ windowDurationMins: duration, usedPercent: used, resetsAt: 1900000000 });
const raw = () => ({ rateLimits: { primary: window(300), secondary: window(10080, 61), credits: { balance: 'PRIVATE' } }, rateLimitResetCredits: { private: true } });

test('normalization strips everything except quota windows', () => {
  assert.deepEqual(normalizeUsage(raw()), { rateLimits: { primary: window(300), secondary: window(10080, 61) } });
});
test('a missing weekly window remains null, not a copy of the short window', () => {
  assert.equal(normalizeUsage({ rateLimits: { primary: window(300) } }).rateLimits.secondary, null);
});
test('windows are selected by duration, not field position', () => {
  const value = normalizeUsage({ rateLimitsByLimitId: { codex: { primary: window(10080), secondary: window(300, 42) } } });
  assert.equal(value.rateLimits.primary.usedPercent, 42);
});
test('unsupported windows and invalid numbers are rejected', () => {
  for (const w of [window(15), window(300, NaN), window(300, -1), window(300, 101)]) {
    assert.throws(() => normalizeUsage({ rateLimits: { primary: w } }));
  }
  assert.throws(() => normalizeUsage({ rateLimits: { limitId: 'other', primary: window(300) } }));
});
test('missing reset timestamp is not manufactured', () => {
  const value = normalizeUsage({ rateLimits: { primary: { ...window(300), resetsAt: null } } });
  assert.equal(value.rateLimits.primary.resetsAt, null);
});

async function service(t, options = {}) {
  const server = createPulseServer({ bridge: { rateLimits: async () => raw(), stop() {} }, ...options });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return `http://127.0.0.1:${server.address().port}`;
}
test('usage endpoint is read-only, sanitized, and has no permissive CORS header', async t => {
  const base = await service(t);
  const response = await fetch(base + '/api/local/usage');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('access-control-allow-origin'), null);
  const value = await response.json();
  assert.equal(value.stale, false);
  assert.ok(value.updatedAt > 0);
  assert.equal(JSON.stringify(value).includes('PRIVATE'), false);
  assert.equal((await fetch(base + '/api/local/usage', { method: 'POST' })).status, 405);
  assert.equal((await fetch(base + '/account/rateLimitResetCredit/consume')).status, 404);
});
test('rejects foreign origins, DNS rebinding hostnames, and cross-site requests', async t => {
  const base = await service(t);
  for (const headers of [{ Origin: 'https://example.com' }, { Host: 'attacker.test' }, { 'Sec-Fetch-Site': 'cross-site' }]) {
    const status = await new Promise((resolve, reject) => {
      const req = httpRequest(base + '/api/local/usage', { headers }, response => { response.resume(); resolve(response.statusCode); });
      req.on('error', reject); req.end();
    });
    assert.equal(status, 403, JSON.stringify(headers));
  }
});
test('deduplicates concurrent reads and caches successful quota responses', async t => {
  let calls = 0;
  const base = await service(t, { bridge: { async rateLimits() { calls++; await new Promise(r => setTimeout(r, 20)); return raw(); }, stop() {} } });
  await Promise.all(Array.from({ length: 10 }, () => fetch(base + '/api/local/usage')));
  assert.equal(calls, 1);
});
test('offline cache is explicitly marked stale and keeps the original timestamp', async t => {
  let now = 100000;
  let fail = false;
  const base = await service(t, { now: () => now, bridge: { async rateLimits() { if (fail) throw new Error('PRIVATE'); return raw(); }, stop() {} } });
  const first = await (await fetch(base + '/api/local/usage')).json();
  now += 31000; fail = true;
  const second = await (await fetch(base + '/api/local/usage')).json();
  assert.equal(second.stale, true);
  assert.equal(second.updatedAt, first.updatedAt);
});
test('first failed read returns unavailable, never fake usage or internal errors', async t => {
  const base = await service(t, { bridge: { async rateLimits() { throw new Error('PRIVATE'); }, stop() {} } });
  const response = await fetch(base + '/api/local/usage');
  assert.equal(response.status, 503);
  assert.equal((await response.text()).includes('PRIVATE'), false);
});
test('radar is opt-in and never calls the feed while disabled', async t => {
  const base = await service(t, { socialLoader() { throw new Error('should never run'); } });
  assert.deepEqual((await (await fetch(base + '/api/local/tibo')).json()).signals, []);
});
test('upstream stale status is preserved, including on cache hits', async t => {
  const base = await service(t, { social: true, socialLoader: async () => ({ enabled: true, sourceStale: true, signals: [] }) });
  for (let i = 0; i < 2; i++) assert.equal((await (await fetch(base + '/api/local/tibo')).json()).stale, true);
});
test('radar signals distinguish reports, future hints, negations and unrelated posts', () => {
  assert.equal(analyzeResetSignal('We have reset the usage limits.').level, 'reported');
  assert.equal(analyzeResetSignal('We will reset the limits tomorrow.').level, 'possible');
  assert.equal(analyzeResetSignal('Reset soon, but not today.').level, 'possible');
  for (const text of ["We haven't reset the limits.", 'No reset today.', 'Limits have not been reset.', 'Nice weather today.']) assert.equal(analyzeResetSignal(text), null);
});
test('radar rejects old posts and wrong authors, sorts recent signals, keeps safe fields only', () => {
  const now = Date.now();
  const tweet = { text: 'We will reset the limits tomorrow.', at: new Date(now - 1000).toISOString(), url: 'https://x.com/thsottiaux/status/123', private: 'PRIVATE' };
  const signals = filterSignals({ tweets: [tweet, { ...tweet, url: 'javascript:alert(1)' }, { ...tweet, at: new Date(now - 8 * 86400000).toISOString() }, { ...tweet, url: 'https://x.com/other/status/123' }] }, now);
  assert.equal(signals.length, 1);
  assert.equal(JSON.stringify(signals).includes('PRIVATE'), false);
});
test('bridge permits only initialization and read, and handles a real stdio handshake', async t => {
  const folder = mkdtempSync(join(tmpdir(), 'pulse-test-'));
  const fixture = join(folder, 'mock-codex');
  writeFileSync(fixture, `#!/usr/bin/env node
const rl = require('node:readline').createInterface({input:process.stdin});
rl.on('line', line => { const m=JSON.parse(line); if(m.id) process.stdout.write(JSON.stringify({id:m.id,result:m.method==='initialize'?{}:{rateLimits:{primary:{usedPercent:7,windowDurationMins:300,resetsAt:1900000000}}}})+'\\n'); });
`, { mode: 0o700 });
  const bridge = new CodexBridge({ binary: fixture, timeout: 1000 });
  t.after(() => bridge.stop());
  await assert.rejects(bridge.send('thread/start'), /not allowed/);
  assert.equal((await bridge.rateLimits()).rateLimits.primary.usedPercent, 7);
});
test('missing Codex binary rejects cleanly and allows a later retry', async () => {
  const bridge = new CodexBridge({ binary: '/nonexistent/pulse-codex-test', timeout: 100 });
  await assert.rejects(bridge.rateLimits());
  await assert.rejects(bridge.rateLimits());
  bridge.stop();
});
