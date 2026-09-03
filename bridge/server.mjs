import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { CodexBridge, normalizeUsage } from './codex.mjs';
import { fetchSocial } from './social.mjs';

export function createPulseServer({ bridge = new CodexBridge(), social = false, socialLoader = fetchSocial, now = Date.now } = {}) {
  const cache = new Map();
  const pending = new Map();
  async function cached(key, ttl, loader) {
    const old = cache.get(key);
    if (old && now() - old.at < ttl) return { ...old.value, updatedAt: old.at, stale: old.value.sourceStale === true };
    if (!pending.has(key)) {
      pending.set(key, (async () => {
        try {
          const value = await loader();
          const at = now();
          cache.set(key, { value, at });
          return { ...value, updatedAt: at, stale: value.sourceStale === true };
        } catch {
          if (old) return { ...old.value, updatedAt: old.at, stale: true };
          throw new Error('No data');
        } finally { pending.delete(key); }
      })());
    }
    return pending.get(key);
  }
  const server = createServer(async (request, response) => {
    const json = (status, value) => {
      response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' });
      response.end(JSON.stringify(value));
    };
    const port = server.address().port;
    const hosts = [`localhost:${port}`, `127.0.0.1:${port}`];
    if (!hosts.includes(request.headers.host) ||
        (request.headers.origin && !hosts.map(host => `http://${host}`).includes(request.headers.origin)) ||
        request.headers['sec-fetch-site'] === 'cross-site') return json(403, { error: 'Local requests only.' });
    if (request.method !== 'GET') return json(405, { error: 'Read-only service.' });
    let path;
    try { path = new URL(request.url, 'http://localhost').pathname; } catch { return json(400, { error: 'Invalid request.' }); }
    if (path === '/' || path === '/health') return json(200, { app: 'codex-pulse', version: '0.1.3', readOnly: true, socialEnabled: social });
    try {
      if (path === '/api/local/usage') return json(200, await cached('usage', 30000, async () => normalizeUsage(await bridge.rateLimits())));
      if (path === '/api/local/tibo') return json(200, social
        ? await cached('social', 300000, socialLoader)
        : { enabled: false, signals: [], stale: false, updatedAt: now() });
      return json(404, { error: 'Not found.' });
    } catch {
      return json(503, { error: path.endsWith('usage') ? 'Usage unavailable. Check Codex installation and ChatGPT login.' : 'Optional public feed unavailable.' });
    }
  });
  server.on('close', () => bridge.stop());
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PULSE_PORT || 43187);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('PULSE_PORT must be 1024–65535.');
  const server = createPulseServer({ social: process.env.PULSE_SOCIAL === '1' });
  server.on('error', error => { console.error(`Codex Pulse: ${error.code || 'startup failed'}`); process.exitCode = 1; });
  server.listen(port, '127.0.0.1', () => console.log(`Codex Pulse listening on 127.0.0.1:${port}; read-only; social ${process.env.PULSE_SOCIAL === '1' ? 'enabled' : 'disabled'}.`));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
    server.close(() => process.exit(0));
    server.closeAllConnections();
    setTimeout(() => process.exit(0), 1000).unref();
  });
}
