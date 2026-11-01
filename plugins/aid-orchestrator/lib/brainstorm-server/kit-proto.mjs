// kit-proto.mjs — `aid-companion.sh proto`: a copy of the application's UI outside the repository, its
// dev server on a free loopback port in its own process group. The agent builds the variants in the copy
// (behind ?v=<klic>); the repository stays clean. Called by kit.mjs with the shared context.
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { spawn, execFileSync } from 'node:child_process';
import { syncExtra, withKitBlock, manFiles, kitWrite, safeTarget, sha, giSha } from './kit-extra.mjs';

const RUNTIME = new Set(['node_modules', 'dist', 'dev-dist', '.git', '.vite', 'vite-cache', '.next', '.turbo', 'coverage', 'storybook-static']);

const freePort = () => new Promise((ok, no) => {
  const s = net.createServer(); s.once('error', no);
  s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
});
const stat = pid => { try { return fs.readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1].split(' '); } catch { return null; } };
// pgrp is field 5 of /proc/<pid>/stat (index 2 after the comm), starttime field 22 (index 19)
const pgrpOf = pid => { const f = stat(pid); return f ? +f[2] : null; };
const startOf = pid => { const f = stat(pid); return f ? f[19] : null; };
function portOwners(port) {
  try {
    const out = execFileSync('ss', ['-ltnpH', `sport = :${port}`], { encoding: 'utf8' });
    return [...out.matchAll(/pid=(\d+)/g)].map(m => +m[1]);
  } catch { return []; }
}

export async function run({ DIR, PLAN, PROJECT, UI, die, manifest }) {
  const need = k => die(`proto: project.yaml has no ui.${k} — add it, for example:\n  ui:\n    dir: ui\n    components: ui/src/components/shared\n    dev_cmd: ["npx", "vite", "--port", "{port}", "--host", "127.0.0.1", "--strictPort"]\n    ready_path: /\n    api_prefix: /api/`);
  if (!UI.dir) need('dir');
  if (!Array.isArray(UI.dev_cmd) || !UI.dev_cmd.length) need('dev_cmd (a list of arguments, one of them {port})');
  if (!UI.dev_cmd.some(a => String(a).includes('{port}'))) die('proto: ui.dev_cmd must pass {port} to the dev server (it gets a free loopback port)');
  const src = path.resolve(PROJECT, UI.dir);
  if (!fs.existsSync(path.join(src, 'package.json'))) die(`proto: ${src} has no package.json — ui.dir names the directory of the UI application`);
  if (!fs.existsSync(path.join(src, 'node_modules'))) die(`proto: ${src}/node_modules is missing — install the UI's dependencies there first (a workspace or pnpm layout without node_modules in ui.dir is not supported; write it to aid-plugin-issues.md)`);

  const dest = path.join(DIR, 'proto'), manFile = path.join(DIR, 'proto-manifest.json'), rec = path.join(DIR, 'proto.json');
  // an existing copy is brought to today's settings before it is reused (WAN P117, P119): the kit's .gitignore block,
  // the copy_extra files beside it; and it says how many files of the app changed since the copy was made
  const writeMan = m => kitWrite(DIR, 'proto-manifest.json', JSON.stringify(m, null, 1), die);
  const settle = () => {
    safeTarget(DIR, 'proto', die, { kit: true }); safeTarget(DIR, 'proto-manifest.json', die, { kit: true });
    const man = JSON.parse(fs.readFileSync(manFile, 'utf8')), gi = safeTarget(DIR, 'proto/.gitignore', die, { kit: true });
    const t = fs.existsSync(gi) ? fs.readFileSync(gi, 'utf8') : '';
    const was = { ...manFiles(man) };
    // a manifest from before 3.14.0 hashed the .gitignore byte for byte: an unchanged one is re-hashed the new way
    if (man.version !== 2 && was['.gitignore'] && t && sha(gi) === was['.gitignore']) was['.gitignore'] = giSha(t);
    const w = withKitBlock(t, RUNTIME);
    if (w !== t) kitWrite(DIR, 'proto/.gitignore', w, die);
    const { record, done } = syncExtra({ DIR, PROJECT, UI, die, recorded: man.extra && man.extra.length ? man.extra : recordedBefore() });
    // stale: today's ui.dir against the snapshot of it taken when the copy was made, by the same function on both sides
    const srcWas = man.src_files, now = manifest(src);
    const stale = srcWas ? new Set([...Object.keys(srcWas), ...Object.keys(now)].filter(k => srcWas[k] !== now[k])).size : null;
    writeMan({ version: 2, files: was, src_files: srcWas || null, extra: record });
    return { stale, extra: done,
      ...(stale ? { refresh: `${stale} file(s) of the app changed since this copy was made — a new copy (your variants set aside): aid-companion.sh proto --plan ${PLAN} --refresh` } : {}),
      ...(stale === null ? { refresh: 'this copy was made before 3.14.0 and cannot say whether the app changed since; aid-companion.sh proto --plan ' + PLAN + ' --refresh makes a new one' } : {}) };
  };
  // proto --refresh set the old manifest aside: its copy_extra record still says which files beside the copy are the kit's
  const recordedBefore = () => {
    const f = process.env.AID_COMPANION_EXTRA_RECORDED;
    try { return f ? (JSON.parse(fs.readFileSync(f, 'utf8')).extra || []) : []; } catch { return []; }
  };
  // a running prototype of this plan is reused only when it is still ours
  if (fs.existsSync(rec)) {
    const r = JSON.parse(fs.readFileSync(rec, 'utf8'));
    let alive = startOf(r.pid) === r.starttime && pgrpOf(r.pid) === r.pgid;
    if (alive) {   // ours, but still serving? the port must be the group's and answer
      const owners = portOwners(r.port);
      let up = false; try { up = (await fetch(r.url + (UI.ready_path || '/'))).status === 200; } catch {}
      if (up && owners.length && owners.every(p => pgrpOf(p) === r.pgid)) { console.log(JSON.stringify({ ...r, reused: true, ...settle() })); return; }
      try { process.kill(-r.pgid, 'SIGTERM'); } catch {}
    }
    fs.rmSync(rec);
  }
  if (!fs.existsSync(dest)) {
    // a symlink in the app is copied as its content, and only when it points inside ui.dir: a link kept as a
    // link would let an edit in the copy change the repository (Codex, 19. 10. 2026)
    const srcReal = fs.realpathSync(src);
    fs.cpSync(src, dest, { recursive: true, dereference: true, filter: s => {
      if (s !== src && RUNTIME.has(path.basename(s))) return false;
      if (fs.lstatSync(s).isSymbolicLink()) {
        let real = ''; try { real = fs.realpathSync(s); } catch {}
        if (!real.startsWith(srcReal + path.sep)) die(`proto: ${s} is a link to ${real || 'nothing'}, outside ${src} — the copy cannot hold it; make it a file or point it inside ui.dir`);
      }
      return true;
    } });
    // node_modules: a directory of our own whose entries link to the app's — the dev server writes its caches
    // there (Vite: .vite, .vite-temp), and the app's may not be writable (ACTA's is root's: EACCES, AC9 19. 10.)
    const nm = path.join(dest, 'node_modules'); fs.mkdirSync(nm);
    for (const e of fs.readdirSync(path.join(src, 'node_modules'))) {
      if (e === '.vite' || e === '.vite-temp' || e === '.cache') continue;
      fs.symlinkSync(path.join(src, 'node_modules', e), path.join(nm, e));
    }
    writeMan({ version: 2, files: manifest(dest), src_files: manifest(src), extra: [] });
  } else if (!fs.existsSync(manFile)) {
    die(`proto: ${dest} exists without its manifest (${manFile}) — the copy's changes cannot be told from the app; run: aid-companion.sh proto --plan ${PLAN} --refresh`);
  }
  const state = settle();

  const port = await freePort();
  const args = UI.dev_cmd.map(a => String(a).replaceAll('{port}', String(port)));
  const log = fs.openSync(path.join(DIR, 'proto.log'), 'a');
  const child = spawn(args[0], args.slice(1), { cwd: dest, detached: true, stdio: ['ignore', log, log], env: { ...process.env, BROWSER: 'none' } });
  child.unref();
  const pgid = child.pid, url = `http://127.0.0.1:${port}`, ready = UI.ready_path || '/';
  const stop = why => { try { process.kill(-pgid, 'SIGTERM'); } catch {} die(`proto: ${why} (log: ${path.join(DIR, 'proto.log')})`); };
  const until = Date.now() + 90_000;
  let ok = false;
  while (Date.now() < until) {
    if (!stat(pgid)) {
      let tail = ''; try { tail = fs.readFileSync(path.join(DIR, 'proto.log'), 'utf8').trim().split('\n').slice(-4).join(' | '); } catch {}
      stop(`the dev server exited before it answered (${args.join(' ')}): ${tail}`);
    }
    try { const r = await fetch(url + ready); if (r.status === 200) { ok = true; break; } } catch {}
    await new Promise(r => setTimeout(r, 500));
  }
  if (!ok) stop(`no HTTP 200 from ${url}${ready} within 90 s`);
  const owners = portOwners(port);
  if (!owners.length || !owners.every(p => pgrpOf(p) === pgid)) stop(`port ${port} answers, but not from the process group we started (owners: ${owners.join(', ') || 'unknown'}) — another process took it`);
  const out = { pid: pgid, pgid, starttime: startOf(pgid), cmd: args[0], port, url, dir: dest, reused: false };
  fs.writeFileSync(rec, JSON.stringify(out, null, 1));
  console.log(JSON.stringify({ ...out, ...state, next: `build the variants in ${dest} behind ?v=<klic> from ui.components only; then write mocks.json and shots.json and run: aid-companion.sh shots --plan ${PLAN}` }));
}
