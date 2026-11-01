// kit-extra.mjs — ui.copy_extra[] (P117 (20), WAN P112): files of the repository outside ui.dir the app reads by a
// relative path (../tsconfig.base.json, ../shared/x.ts), copied beside the copy at the same relative place. One
// place says where each lands and refuses what may not (a secret, outside the repository, a directory, the kit's own
// files, through a link): `proto` copies by it, `show` allows exactly these files by it (WAN P119: show refused them).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// the kit's own block in the copy's .gitignore (between the two marker lines) is not a change of the app
export const GI_BEGIN = '# aid-companion: begin', GI_END = '# aid-companion: end';
// compared without the block and without trailing newlines (appending it may add the file's missing last newline)
export const stripKitBlock = t => t.replace(new RegExp(`${GI_BEGIN}[\\s\\S]*?${GI_END}\\n?`), '').replace(/\n+$/, '');
export const withKitBlock = (t, runtime) => t.includes(GI_BEGIN) ? t
  : (t && !t.endsWith('\n') ? t + '\n' : t) + [GI_BEGIN,
    '# the project\'s .gitignore may hide parts of this copy from the dev server\'s scanners (Tailwind v4: WAN P119)',
    '!*/', ...[...runtime].map(r => r + '/'), GI_END].join('\n') + '\n';
// proto-manifest.json: {version: 2, files, extra: [{rel, sha256}]}; a copy made before 3.14.0 holds the flat files map
export const manFiles = m => (m && m.version === 2 ? m.files : m) || {};
export const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');

const KIT = new Set(['proto', 'shots', 'old', 'proto.json', 'proto-manifest.json', 'proto.log', 'server.json', 'mocks.json', 'shots.json', 'navrh.json', 'answers.jsonl', 'proposal.json']);
// any component of the path (a file inside .env.d/ or credentials/ is as secret as the directory)
const SECRET_PART = /^(\.env.*|.*secret.*|.*credential.*|.*\.(pem|key|p12|pfx)|id_(rsa|ed25519).*|\.ssh|\.aws|\.gnupg)$/i;
const secretPath = p => p.split(/[\\/]/).some(c => SECRET_PART.test(c));

// [{entry, from (real source), to (absolute target), rel (target relative to DIR)}] — every check but the write's
export function extraTargets({ DIR, PROJECT, UI, die }) {
  const extra = UI.copy_extra || [];
  if (!Array.isArray(extra)) die('proto: ui.copy_extra must be a list of repository paths');
  const repo = fs.realpathSync(PROJECT), src = path.resolve(PROJECT, UI.dir || '.'), dest = path.join(DIR, 'proto');
  return extra.map((e, i) => {
    if (typeof e !== 'string' || !e || path.isAbsolute(e)) die(`proto: ui.copy_extra[${i}] must be a path relative to the repository`);
    const from = path.resolve(PROJECT, e);
    let real = ''; try { real = fs.realpathSync(from); } catch { die(`proto: ui.copy_extra[${i}] ${e} does not exist`); }
    if (real !== repo && !real.startsWith(repo + path.sep)) die(`proto: ui.copy_extra[${i}] ${e} is outside the repository`);
    if (secretPath(path.relative(repo, real)) || secretPath(e)) die(`proto: ui.copy_extra[${i}] ${e} looks like a secret (.env, a key, credentials) — it never goes into the copy`);
    if (fs.statSync(real).isDirectory()) die(`proto: ui.copy_extra[${i}] ${e} is a directory — list the files`);
    const to = path.resolve(dest, path.relative(src, from));
    if (!to.startsWith(path.resolve(DIR) + path.sep) || to.startsWith(path.resolve(dest) + path.sep)) die(`proto: ui.copy_extra[${i}] ${e} would land at ${to}, not beside the copy in ${DIR}`);
    const rel = path.relative(DIR, to);
    if (KIT.has(rel.split(path.sep)[0])) die(`proto: ui.copy_extra[${i}] ${e} would overwrite the kit's own ${rel}`);
    return { entry: e, from: real, to, rel };
  });
}

// no link on the way: a link inside the companion directory could steer the write outside it or onto the kit's own
// files (Codex review of P117 F) — every existing component is checked, then the real parent
function safeParent(DIR, t, die) {
  const dirReal = fs.realpathSync(DIR), dest = path.join(DIR, 'proto');
  for (let c = path.dirname(t.to); c.startsWith(path.resolve(DIR) + path.sep); c = path.dirname(c)) {
    if (fs.existsSync(c) && fs.lstatSync(c).isSymbolicLink()) die(`proto: ui.copy_extra ${t.entry}: ${c} is a link — the companion directory holds no links`);
  }
  if (fs.existsSync(t.to) && fs.lstatSync(t.to).isSymbolicLink()) die(`proto: ui.copy_extra ${t.entry}: ${t.to} is a link`);
  fs.mkdirSync(path.dirname(t.to), { recursive: true });
  const parentReal = fs.realpathSync(path.dirname(t.to));
  if (!(parentReal + path.sep).startsWith(dirReal + path.sep) || (parentReal + path.sep).startsWith(fs.realpathSync(dest) + path.sep)
      || KIT.has(path.relative(dirReal, path.join(parentReal, path.basename(t.to))).split(path.sep)[0])) die(`proto: ui.copy_extra ${t.entry} does not land beside the copy`);
}

// bring the files beside the copy to the list: copy what is missing or changed, remove what the list no longer
// names (the kit put it there). Returns the new record [{rel, sha256}] and what it did.
export function syncExtra({ DIR, PROJECT, UI, die, recorded = [] }) {
  const targets = extraTargets({ DIR, PROJECT, UI, die }), done = [];
  for (const t of targets) {
    const want = sha(t.from);
    if (fs.existsSync(t.to) && !fs.lstatSync(t.to).isSymbolicLink() && sha(t.to) === want) continue;
    safeParent(DIR, t, die);
    fs.copyFileSync(t.from, t.to); done.push(`copied ${t.rel}`);
  }
  const keep = new Set(targets.map(t => t.rel));
  for (const r of recorded) {
    if (keep.has(r.rel)) continue;
    const to = path.resolve(DIR, r.rel);
    if (!to.startsWith(path.resolve(DIR) + path.sep) || KIT.has(r.rel.split(path.sep)[0])) continue;   // never outside, never the kit's
    if (fs.existsSync(to) && !fs.lstatSync(to).isSymbolicLink()) { fs.rmSync(to); done.push(`removed ${r.rel}`); }
  }
  return { record: targets.map(t => ({ rel: t.rel, sha256: sha(t.to) })), done };
}
