import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';

const files = execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' }).split('\0').filter(Boolean);
if (!files.length) throw new Error('Stage the release files before running this check.');
const forbidden = /(?:^|\/)(?:node_modules|build|dist|DerivedData|xcuserdata|\.env|auth\.json|hosts\.yml)(?:\/|$)|\.(?:p12|p8|pem|key|mobileprovision|provisionprofile|log)$/;
const secrets = [
  /gh[pousr]_[A-Za-z0-9]{20,}/,
  /github_pat_[A-Za-z0-9_]{30,}/,
  /sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}/,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /\/Users\/[A-Za-z0-9_-]+\//,
  /(?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*[A-Z0-9]{10}/,
];
const problems = [];
for (const file of files) {
  if (forbidden.test(file)) problems.push(`${file}: forbidden release path`);
  if (statSync(file).size > 2 * 1024 * 1024) problems.push(`${file}: unexpectedly large file`);
  if (/\.png$/.test(file)) continue;
  const content = readFileSync(file, 'utf8');
  if (secrets.some(pattern => pattern.test(content))) problems.push(`${file}: possible secret or personal path (value withheld)`);
}
if (problems.length) { console.error(problems.join('\n')); process.exitCode = 1; }
else console.log(`Release hygiene passed for ${files.length} tracked files. This is not a full security audit.`);
