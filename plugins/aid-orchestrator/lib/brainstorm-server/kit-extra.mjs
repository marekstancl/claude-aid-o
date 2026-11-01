// kit-extra.mjs — what the kit writes in the plan's companion directory, checked in ONE place:
//   - the names the kit keeps for itself (RESERVED: the same list `show` allows, `copy_extra` may never take);
//   - safeTarget: every write and every removal the kit makes goes through it — a normalized relative path,
//     inside the directory, no component (the target included, even a dangling one) a link;
//   - ui.copy_extra[] (P117 (20), WAN P112): repository files outside ui.dir the app reads by a relative path
//     (../tsconfig.base.json), copied beside the copy; `proto` copies by extraTargets, `show` allows exactly these
//     files by it (WAN P119: show refused them);
//   - the kit's block in the copy's .gitignore (WAN P119: Tailwind v4 skipped what the project's .gitignore hid).
// No side effects on import (kit-proto.mjs and kit.mjs both import it; kit.mjs runs a step when imported).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// the names in the plan's directory that belong to the kit
export const RESERVED = [/^proto$/, /^proto-manifest\.json$/, /^proto\.json$/, /^proto\.log$/, /^shots$/, /^mocks\.json$/,
  /^shots\.json$/, /^navrh\.json$/, /^navrh-\d+\.html$/, /^check-\d+x\d+\.png$/, /^answers\.jsonl$/, /^server\.json$/,
  /^proposal\.json$/, /^\.server\.(log|log\.prev|pid)$/, /^\.events$/, /^\.started$/, /^\.keep$/, /^old$/];
export const reserved = name => RESERVED.some(r => r.test(name));

// lstat that says "absent" instead of throwing; a dangling link is present (it is a link)
const lst = p => { try { return fs.lstatSync(p); } catch (e) { if (e.code === 'ENOENT') return null; throw e; } };

// <rel> inside <DIR>: normalized, no "..", no absolute, not under a reserved first name (unless `kit` says the kit
// itself writes there), and no component on the way — the last one included — a link. Returns the absolute path.
export function safeTarget(DIR, rel, die, { kit = false } = {}) {
  if (typeof rel !== 'string' || !rel || path.isAbsolute(rel)) die(`${JSON.stringify(rel)} is not a relative path`);
  const norm = path.normalize(rel);
  if (norm !== rel.replace(/\/+$/, '') || norm.split(path.sep).includes('..') || norm === '.') die(`${rel} is not a plain relative path (no "..", no "./")`);
  if (!kit && reserved(norm.split(path.sep)[0])) die(`${rel} would land on the kit's own ${norm.split(path.sep)[0]}`);
  const root = path.resolve(DIR), abs = path.join(root, norm);
  const rs = lst(root); if (!rs || rs.isSymbolicLink() || !rs.isDirectory()) die(`${root} is not a plain directory`);
  let c = root;
  for (const part of norm.split(path.sep)) {
    c = path.join(c, part);
    const s = lst(c);
    if (s && s.isSymbolicLink()) die(`${c} is a link — the companion directory holds no links`);
  }
  return abs;
}
// the write itself never follows a link put there after the check (O_NOFOLLOW on the last component)
const writeNoFollow = (abs, data) => {
  const fd = fs.openSync(abs, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_NOFOLLOW, 0o644);
  try { fs.writeFileSync(fd, data); } finally { fs.closeSync(fd); }
};
// write a file of the kit (a .gitignore, a manifest) through safeTarget
export function kitWrite(DIR, rel, data, die) { writeNoFollow(safeTarget(DIR, rel, die, { kit: true }), data); }

// the kit's own block in the copy's .gitignore (between the two marker lines) is not a change of the app; compared
// without the block and without trailing newlines (appending it may add the file's missing last newline)
export const GI_BEGIN = '# aid-companion: begin', GI_END = '# aid-companion: end';
export const stripKitBlock = t => t.replace(new RegExp(`${GI_BEGIN}[\\s\\S]*?${GI_END}\\n?`), '').replace(/\n+$/, '');
export const withKitBlock = (t, runtime) => t.includes(GI_BEGIN) ? t
  : (t && !t.endsWith('\n') ? t + '\n' : t) + [GI_BEGIN,
    '# the project\'s .gitignore may hide parts of this copy from the dev server\'s scanners (Tailwind v4: WAN P119)',
    '!*/', ...[...runtime].map(r => r + '/'), GI_END].join('\n') + '\n';
// proto-manifest.json: {version: 2, files, src_files, extra: [{rel, sha256}]}; before 3.14.0 a flat files map
export const manFiles = m => (m && m.version === 2 ? m.files : m) || {};
// the hash a .gitignore is compared by (its text without the kit's block)
export const giSha = text => crypto.createHash('sha256').update(stripKitBlock(text)).digest('hex');
export const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');

// any component of the path (a file inside .env.d/ or credentials/ is as secret as the directory)
const SECRET_PART = /^(\.env.*|.*secret.*|.*credential.*|.*\.(pem|key|p12|pfx)|id_(rsa|ed25519).*|\.ssh|\.aws|\.gnupg)$/i;
const secretPath = p => p.split(/[\\/]/).some(c => SECRET_PART.test(c));

// [{entry, from (real source), to (absolute target), rel (target relative to DIR)}]
export function extraTargets({ DIR, PROJECT, UI, die }) {
  const extra = UI.copy_extra || [];
  if (!Array.isArray(extra)) die('proto: ui.copy_extra must be a list of repository paths');
  const repo = fs.realpathSync(PROJECT), src = path.resolve(PROJECT, UI.dir || '.'), dest = path.join(DIR, 'proto');
  return extra.map((e, i) => {
    const at = `proto: ui.copy_extra[${i}] ${e}`;
    if (typeof e !== 'string' || !e || path.isAbsolute(e)) die(`proto: ui.copy_extra[${i}] must be a path relative to the repository`);
    const from = path.resolve(PROJECT, e);
    let real = ''; try { real = fs.realpathSync(from); } catch { die(`${at} does not exist`); }
    if (real !== repo && !real.startsWith(repo + path.sep)) die(`${at} is outside the repository`);
    if (secretPath(path.relative(repo, real)) || secretPath(e)) die(`${at} looks like a secret (.env, a key, credentials) — it never goes into the copy`);
    if (fs.statSync(real).isDirectory()) die(`${at} is a directory — list the files`);
    const to = path.resolve(dest, path.relative(src, from));
    if (!to.startsWith(path.resolve(DIR) + path.sep) || to.startsWith(path.resolve(dest) + path.sep)) die(`${at} would land at ${to}, not beside the copy in ${DIR}`);
    const rel = path.relative(DIR, to);
    safeTarget(DIR, rel, m => die(`${at}: ${m}`));
    return { entry: e, from: real, to, rel };
  });
}

// remove <rel> (a file the kit put there) and the directories it leaves empty, up to DIR — never through a link
function removeKitFile(DIR, rel, die) {
  const abs = safeTarget(DIR, rel, die), s = lst(abs);
  if (!s || !s.isFile()) return false;
  fs.rmSync(abs);
  for (let d = path.dirname(abs); d !== path.resolve(DIR) && d.startsWith(path.resolve(DIR) + path.sep); d = path.dirname(d)) {
    if (fs.readdirSync(d).length) break;
    fs.rmdirSync(d);
  }
  return true;
}

// bring the files beside the copy to the list: copy what is missing or changed, remove what the list no longer
// names (the kit put it there; `recorded` is the manifest's record). Returns the new record and what it did.
export function syncExtra({ DIR, PROJECT, UI, die, recorded = [] }) {
  const targets = extraTargets({ DIR, PROJECT, UI, die }), done = [];
  for (const t of targets) {
    fs.mkdirSync(path.dirname(t.to), { recursive: true });
    safeTarget(DIR, t.rel, m => die(`proto: ui.copy_extra ${t.entry}: ${m}`));     // again: mkdir walked the path
    const s = lst(t.to);
    if (s && s.isFile() && sha(t.to) === sha(t.from)) continue;
    writeNoFollow(t.to, fs.readFileSync(t.from)); done.push(`copied ${t.rel}`);
  }
  const keep = new Set(targets.map(t => t.rel));
  for (const r of Array.isArray(recorded) ? recorded : []) {
    if (!r || typeof r.rel !== 'string' || keep.has(r.rel)) continue;
    if (removeKitFile(DIR, r.rel, m => die(`proto: the recorded copy_extra ${r.rel}: ${m}`))) done.push(`removed ${r.rel}`);
  }
  return { record: targets.map(t => ({ rel: t.rel, sha256: sha(t.to) })), done };
}
