import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export function codexBinary() {
  if (process.env.CODEX_BIN) return process.env.CODEX_BIN;
  return [
    '/Applications/Codex.app/Contents/Resources/codex',
    '/Applications/ChatGPT.app/Contents/Resources/codex',
    join(homedir(), 'Applications/Codex.app/Contents/Resources/codex'),
  ].find(existsSync) || 'codex';
}

// This bridge intentionally exposes no thread, login, purchase or reset actions.
export class CodexBridge {
  constructor({ binary = codexBinary(), timeout = 15000 } = {}) {
    this.binary = binary;
    this.timeout = timeout;
    this.pending = new Map();
    this.nextId = 1;
    this.child = null;
    this.ready = null;
  }

  start() {
    if (this.ready) return this.ready;
    const child = spawn(this.binary, ['app-server'], {
      stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, TERM: 'dumb' },
    });
    this.child = child;
    // Drain diagnostics but never persist or return them (they may contain account details).
    child.stderr.resume();
    child.stdin.on('error', () => {});
    const lines = createInterface({ input: child.stdout });
    lines.on('line', line => {
      let message;
      try { message = JSON.parse(line); } catch { return; }
      const pending = this.pending.get(String(message.id));
      if (!pending) return;
      clearTimeout(pending.timer);
      this.pending.delete(String(message.id));
      if (message.error) pending.reject(new Error('Codex rejected the read request. Check your Codex login.'));
      else pending.resolve(message.result);
    });
    const failed = () => {
      if (this.child !== child) return;
      this.stop();
    };
    child.once('error', failed);
    child.once('exit', failed);
    this.ready = this.send('initialize', {
      clientInfo: { name: 'codex-pulse', title: 'Codex Pulse', version: '0.1.2' },
    }).then(() => {
      child.stdin.write(JSON.stringify({ method: 'initialized' }) + '\n');
    }).catch(error => { this.stop(); throw error; });
    return this.ready;
  }

  send(method, params) {
    if (!['initialize', 'account/rateLimits/read'].includes(method)) {
      return Promise.reject(new Error('Method not allowed: read-only bridge.'));
    }
    if (!this.child?.stdin.writable) return Promise.reject(new Error('Codex is not running.'));
    const id = String(this.nextId++);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('Codex read timed out.'));
      }, this.timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.child.stdin.write(JSON.stringify({ id, method, ...(params === undefined ? {} : { params }) }) + '\n', error => {
        if (!error) return;
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new Error('Codex connection closed.'));
      });
    });
  }

  async rateLimits() {
    try {
      await this.start();
      return await this.send('account/rateLimits/read');
    } catch (error) { this.stop(); throw error; }
  }

  stop() {
    const child = this.child;
    this.child = null;
    this.ready = null;
    for (const item of this.pending.values()) {
      clearTimeout(item.timer);
      item.reject(new Error('Codex connection closed.'));
    }
    this.pending.clear();
    child?.kill('SIGTERM');
  }
}

export function normalizeUsage(result) {
  const bucket = result?.rateLimitsByLimitId?.codex ?? result?.rateLimits;
  if (!bucket || (bucket.limitId && bucket.limitId !== 'codex')) throw new Error('No Codex rate limit bucket.');
  const windows = [bucket.primary, bucket.secondary].filter(Boolean);
  const clean = duration => {
    const w = windows.find(item => item.windowDurationMins === duration);
    if (!w || !Number.isFinite(w.usedPercent) || w.usedPercent < 0 || w.usedPercent > 100) return null;
    return {
      usedPercent: Math.round(w.usedPercent),
      windowDurationMins: duration,
      resetsAt: Number.isSafeInteger(w.resetsAt) && w.resetsAt > 0 ? w.resetsAt : null,
    };
  };
  const primary = clean(300);
  const secondary = clean(10080);
  if (!primary && !secondary) throw new Error('No supported 5-hour or weekly limits.');
  // Whitelist fields; never forward plan, identity, balance or reset-credit metadata.
  return { rateLimits: { primary, secondary } };
}
