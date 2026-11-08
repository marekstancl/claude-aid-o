// kit-proto.mjs — `aid-companion.sh proto`: a copy of the application's UI outside the repository, its
// dev server on a free loopback port in its own process group. The agent builds the variants in the copy
// (behind ?v=<klic>); the repository stays clean. Called by kit.mjs with the shared context.
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import { spawn, execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
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

// 3.17.0 live preview: the copy runs against the dev API the project ALLOWS (ui.live.allowed_api, an allowlist of
// hosts/IPs; every URL in ui.live.env is resolved and each of its addresses must be one of theirs), in a clean
// environment (never the agent's keys), and no value is a secret (VITE_* lands in the page). proto.json keeps the
// digest, never the values.
import dns from 'node:dns/promises';
export async function liveEnv(UI, die) {
  const live = UI.live || {}, env = live.env, allowed = (live.allowed_api || []).map(h => String(h).toLowerCase());
  const example = `\n  ui:\n    live:\n      env:\n        VITE_API_TARGET: http://10.20.20.22:8000\n      allowed_api: [10.20.20.22]`;
  if (!env || typeof env !== 'object' || !Object.keys(env).length) die(`proto --live: project.yaml has no ui.live.env — declare what points the copy at the DEV API, for example:${example}`);
  if (!allowed.length) die(`proto --live: project.yaml has no ui.live.allowed_api — the hosts or IPs of the dev API the live copy may reach (an allowlist), for example:${example}`);
  const ips = async h => { try { return (await dns.lookup(h, { all: true })).map(a => a.address); } catch { return []; } };
  const hosts = allowed.map(a => a.replace(/:\d+$/, '').replace(/^\[|\]$/g, ''));   // an entry may name host:port
  const okIps = new Set((await Promise.all(hosts.map(ips))).flat().concat(hosts));
  for (const [k, v] of Object.entries(env)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) die(`proto --live: ui.live.env key '${k}' is not a variable name`);
    if (/KEY|TOKEN|SECRET|PASS|CREDENTIAL|AUTH/i.test(k)) die(`proto --live: ui.live.env ${k} looks like a secret — the live copy's env reaches the page (VITE_*) and its log; give it no secret`);
    // every value is ONE whole URL (http/https/ws/wss): a bare host or host:port could not be checked
    const val = String(v);
    let url; try { url = new URL(val); } catch {}
    if (!url || !/^(https?|wss?):$/.test(url.protocol) || /\s/.test(val)) die(`proto --live: ui.live.env ${k} must be one whole URL (http://host:port/…) — '${val}' is not; a bare host or a template cannot be checked against ui.live.allowed_api`);
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, ''), port = url.port || (/^(https|wss):$/.test(url.protocol) ? '443' : '80');
    const addr = net.isIP(host) ? [host] : await ips(host);
    const portOk = allowed.filter(a => /:\d+$/.test(a)).length === 0 || allowed.some(a => a.endsWith(':' + port));
    if (!addr.length || !addr.every(a => okIps.has(a)) || !portOk) die(`proto --live: ui.live.env ${k} points at ${host}:${port} (${addr.join(', ') || 'does not resolve'}), not one of ui.live.allowed_api — the live preview reaches the dev API only`);
  }
  const digest = crypto.createHash('sha256').update(JSON.stringify(Object.entries(env).sort())).digest('hex').slice(0, 16);
  // the dev server's whole environment: what a node toolchain needs, and the declared values — never the agent's keys
  const keep = Object.fromEntries(Object.entries(process.env).filter(([k]) => /^(PATH|HOME|LANG|LC_[A-Z]+|TZ|TMPDIR|TERM|NODE_ENV|NODE_OPTIONS|npm_config_cache)$/.test(k)));
  return { env: { ...keep, ...Object.fromEntries(Object.entries(env).map(([k, v]) => [k, String(v)])) }, digest };
}

export async function run({ DIR, PLAN, PROJECT, UI, die, manifest }) {
  const LIVE = process.env.AID_COMPANION_LIVE === '1' ? await liveEnv(UI, die) : null;
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
    // a copy started with another environment (mocks vs live, another dev API) is restarted, never reused
    if (alive && (r.live_env || null) !== (LIVE ? LIVE.digest : null)) die(`proto: the running copy (pid ${r.pid}) runs ${r.live_env ? 'live' : 'on mocks'}, this asks for ${LIVE ? (r.live_env ? 'live with another ui.live.env' : 'live') : 'mocks'} — the PM may be looking at it; stop it first: aid-companion.sh down --plan ${PLAN}`);
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
    writeMan({ version: 2, files: manifest(dest), src_files: manifest(src), extra: recordedBefore() });
  } else if (!fs.existsSync(manFile)) {
    die(`proto: ${dest} exists without its manifest (${manFile}) — the copy's changes cannot be told from the app; run: aid-companion.sh proto --plan ${PLAN} --refresh`);
  }
  const state = settle();
  if (LIVE) {   // a .env* of the app would point the dev server elsewhere than the declared dev API (Vite loads them)
    for (const f of fs.readdirSync(dest)) if (/^\.env(\..*)?$/.test(f) && fs.lstatSync(path.join(dest, f)).isFile()) {
      fs.rmSync(path.join(dest, f)); console.error(`proto --live: removed ${f} from the copy (the live copy takes its API from ui.live.env only)`);
    }
  }

  const port = await freePort();
  const args = UI.dev_cmd.map(a => String(a).replaceAll('{port}', String(port)));
  const log = fs.openSync(safeTarget(DIR, 'proto.log', die, { kit: true }), fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_APPEND | fs.constants.O_NOFOLLOW, 0o644);
  const child = spawn(args[0], args.slice(1), { cwd: dest, detached: true, stdio: ['ignore', log, log], env: LIVE ? { ...LIVE.env, BROWSER: 'none' } : { ...process.env, BROWSER: 'none' } });
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
  // the live copy listens on loopback only: the PM reaches it through the proxy alone (dev_cmd decides --host)
  let listen = ''; if (LIVE) { try { listen = execFileSync('ss', ['-ltnH', `sport = :${port}`], { encoding: 'utf8' }); } catch { stop('cannot tell where the dev server listens (ss failed) — the live preview needs it on loopback'); } }
  const addrs = [...listen.matchAll(/\s(\S+):\d+\s/g)].map(m => m[1]);
  if (addrs.some(a => !/^(127\.0\.0\.1|\[::1\]|::1)$/.test(a))) stop(`the dev server listens on ${addrs.join(', ')}, not only on loopback — ui.dev_cmd must bind 127.0.0.1 (--host 127.0.0.1)`);
  const out = { pid: pgid, pgid, starttime: startOf(pgid), cmd: args[0], port, url, dir: dest, reused: false, live_env: LIVE ? LIVE.digest : null };
  kitWrite(DIR, 'proto.json', JSON.stringify(out, null, 1), die);
  console.log(JSON.stringify({ ...out, ...state, next: LIVE
    ? `build the variants in ${dest} behind window.AID_VARIANT (the live preview sets it from ?v=<klic>) from ui.components only; write live.json (kolo, body[] {bod, otazka, varianty[] {klic, popis, cesta}}) and run: aid-companion.sh live --plan ${PLAN}`
    : `build the variants in ${dest} behind ?v=<klic> from ui.components only; then write mocks.json and shots.json and run: aid-companion.sh shots --plan ${PLAN}` }));
}
