export const FEED_URL = 'https://codex-reset.com/api/feed';

export function analyzeResetSignal(text) {
  const mentionsReset = /\breset(?:s|ting)?\b|usage limits?|rate limits?/i.test(text);
  if (!mentionsReset) return null;
  const negated = /\b(?:not|never)\s+(?:been\s+)?reset|\b(?:haven't|hasn't|didn't|won't)\b|no reset|not today|reset (?:failed|did not)/i.test(text);
  const future = /\b(?:soon|tomorrow|later today|will reset|going to reset|might reset|may reset|feeling like)\b|next \d+ (?:minutes|hours)/i.test(text);
  if (negated) {
    if (future && /not today/i.test(text)) return { level: 'possible', label: 'Possible · not today', strength: 'medium', reason: 'Future reset language, but today is explicitly excluded.' };
    return null;
  }
  if (future) return { level: 'possible', label: 'Possible reset', strength: 'medium', reason: 'Future-looking reset language; not confirmation that your account has reset.' };
  const reported = /\b(?:have|has|we['’]ve|i['’]ve)\s+(?:now\s+)?reset\b|limits?\s+(?:have|has)\s+been\s+reset|reset button pressed|full reset applied/i.test(text);
  if (reported) return { level: 'reported', label: 'Reset reported', strength: 'high', reason: 'The post reports a reset. Verify your own quota above; this is a text heuristic.' };
  return null;
}

export function filterSignals(data, now = Date.now()) {
  return (Array.isArray(data?.tweets) ? data.tweets : []).flatMap(tweet => {
    const text = String(tweet.text || '').slice(0, 4000);
    const at = Date.parse(tweet.at);
    const url = String(tweet.url || '');
    // Only this account, recent posts, and valid external links. No provider-supplied HTML.
    if (!/^https:\/\/(?:x|twitter)\.com\/thsottiaux\/status\/\d+\/?(?:\?.*)?$/i.test(url)) return [];
    if (!Number.isFinite(at) || at > now + 300000 || now - at > 7 * 86400000) return [];
    const resetAnalysis = analyzeResetSignal(text);
    return resetAnalysis ? [{ text, at: new Date(at).toISOString(), url, resetAnalysis }] : [];
  }).sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, 3);
}

export async function fetchSocial() {
  const response = await fetch(FEED_URL, {
    headers: { Accept: 'application/json', 'User-Agent': 'Codex-Pulse/0.1.3' },
    signal: AbortSignal.timeout(10000), redirect: 'error',
  });
  if (!response.ok) throw new Error('Public feed unavailable.');
  const body = await response.text();
  if (body.length > 2000000) throw new Error('Public feed too large.');
  const data = JSON.parse(body);
  return { enabled: true, source: FEED_URL, sourceStale: data.stale === true, signals: filterSignals(data) };
}
