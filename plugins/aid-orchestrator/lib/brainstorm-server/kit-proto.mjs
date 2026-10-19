// kit-proto.mjs — `aid-companion.sh proto`: a copy of the application's UI outside the repository, its
// dev server on a free loopback port in its own process group. The agent builds the variants in the copy
// (behind ?v=<klic>); the repository stays clean. Called by kit.mjs with the shared context.
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { spawn, execFileSync } from 'node:child_process';

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
  // a running prototype of this plan is reused only when it is still ours
  if (fs.existsSync(rec)) {
    const r = JSON.parse(fs.readFileSync(rec, 'utf8'));
    if (startOf(r.pid) === r.starttime && pgrpOf(r.pid) === r.pgid) { console.log(JSON.stringify({ ...r, reused: true })); return; }
    fs.rmSync(rec);
  }
  if (!fs.existsSync(dest)) {
    fs.cpSync(src, dest, { recursive: true, filter: s => !RUNTIME.has(path.basename(s)) || s === src });
    // node_modules: a directory of our own whose entries link to the app's — the dev server writes its caches
    // there (Vite: .vite, .vite-temp), and the app's may not be writable (ACTA's is root's: EACCES, AC9 19. 10.)
    const nm = path.join(dest, 'node_modules'); fs.mkdirSync(nm);
    for (const e of fs.readdirSync(path.join(src, 'node_modules'))) {
      if (e === '.vite' || e === '.vite-temp' || e === '.cache') continue;
      fs.symlinkSync(path.join(src, 'node_modules', e), path.join(nm, e));
    }
    fs.writeFileSync(manFile, JSON.stringify(manifest(dest), null, 1));
  } else if (!fs.existsSync(manFile)) {
    die(`proto: ${dest} exists without its manifest (${manFile}) — the copy's changes cannot be told from the app; move ${dest} away and run proto again`);
  }

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
  console.log(JSON.stringify({ ...out, next: `build the variants in ${dest} behind ?v=<klic> from ui.components only; then write mocks.json and shots.json and run: aid-companion.sh shots --plan ${PLAN}` }));
}
