// lifetime.js — when a companion ends on its own (2.114.0). Dependency-free.
//
// WHY: on 6. 10. 2026 twelve forgotten companions ran on eco-dev, the oldest
// 48 days, holding the ports — nobody cleans by hand. A companion ends itself
// after IDLE_MS with no browser connected and no new screen (default 12 h),
// unless the PM pressed "Držet" on its page (a `.keep` file in the session
// directory); a kept one still ends MAX_MS after it started (default 60 days).
// The screens on disk stay either way.
'use strict';
const fs = require('fs');
const path = require('path');

const HOUR = 3600 * 1000;
const DEFAULT_IDLE_MS = 12 * HOUR;
const DEFAULT_MAX_MS = 60 * 24 * HOUR;

// create({screenDir, idleMs?, maxMs?, now?}) → {touch, keep, unkeep, isKept, check, state}
function create(opts) {
  const screenDir = opts.screenDir;
  const idleMs = opts.idleMs != null ? Number(opts.idleMs) : DEFAULT_IDLE_MS;
  const maxMs = opts.maxMs != null ? Number(opts.maxMs) : DEFAULT_MAX_MS;
  const now = opts.now || (() => Date.now());
  const keepFile = path.join(screenDir, '.keep');
  // the session's birth survives a restart of the process (the 60-day cap counts from it)
  const startFile = path.join(screenDir, '.started');
  let startedAt = now();
  try {
    if (fs.existsSync(startFile)) {
      const t = Date.parse(fs.readFileSync(startFile, 'utf8').trim());
      if (!Number.isNaN(t)) startedAt = t;
    } else {
      fs.mkdirSync(screenDir, { recursive: true });
      fs.writeFileSync(startFile, new Date(startedAt).toISOString() + '\n');
    }
  } catch (e) { /* unwritable dir: count from this process */ }
  let lastActivity = startedAt;
  let connections = 0;

  return {
    touch() { lastActivity = now(); },
    connected() { connections += 1; lastActivity = now(); },
    disconnected() { connections = Math.max(0, connections - 1); lastActivity = now(); },
    keep(by) {
      fs.writeFileSync(keepFile, JSON.stringify({ kept_at: new Date(now()).toISOString(), by: by || 'pm' }) + '\n');
      return true;
    },
    unkeep() { try { fs.unlinkSync(keepFile); } catch (e) { /* not kept */ } return false; },
    isKept() { return fs.existsSync(keepFile); },
    // 'expired' (past maxMs, kept or not), 'idle' (no browser, nothing new for idleMs, not kept), or null
    check() {
      const t = now();
      if (t - startedAt >= maxMs) return 'expired';
      if (this.isKept()) return null;
      if (connections === 0 && t - lastActivity >= idleMs) return 'idle';
      return null;
    },
    state() {
      return { started_at: new Date(startedAt).toISOString(), last_activity: new Date(lastActivity).toISOString(),
               connections, kept: this.isKept(), idle_ms: idleMs, max_ms: maxMs };
    },
  };
}

module.exports = { create, DEFAULT_IDLE_MS, DEFAULT_MAX_MS };
