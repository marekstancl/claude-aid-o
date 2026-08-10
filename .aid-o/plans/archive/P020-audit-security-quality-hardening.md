---
id: P020
type: plan
status: done
created: 2026-02-28
author: PM + AI
---

# P020 — Audit Security & Quality Hardening

## Context

The full project health audit (2026-02-28) scored the AID Orchestrator at **30/100 (FAIL)**. Security scored 32/100 with three path traversal vulnerabilities (CWE-22) across route handlers, CORS misconfiguration, and both servers binding 0.0.0.0 with zero authentication. Documentation scored 21/100 with a Gemini boilerplate GUI README, stale version numbers, and inconsistent step counts. Code quality found a functional bug (`.replace` only replacing the first underscore) and a silent data loss bug in WebSocket replay.

Cross-referencing the audit with the backlog (62 active proposals) and lessons learned identified **7 zombie backlog entries** (IMP-010, IMP-035, IMP-049, IMP-050, IMP-057, IMP-059, IMP-067) that were already fixed but never moved to the Implemented section. These need cleanup to prevent re-work.

This plan addresses all **13 validated findings** plus the backlog cleanup. Plan P019 (pipeline hardening) is a separate, non-overlapping effort and should run first or in parallel.

## Goal

Fix all validated security vulnerabilities, documentation errors, and code quality bugs from the 2026-02-28 audit, and clean up 7 zombie backlog entries — so the next audit scores above 60/100 overall with Security above 70.

## Scope

**In-scope:**
- Path traversal fixes in 3 route files (pipeline.ts, evidence.ts, decisions.ts)
- CORS wildcard handling fix in aid-server config.ts
- CORS middleware addition to aid-gui server
- Default host binding change to 127.0.0.1 in both servers
- GUI README replacement (remove Gemini boilerplate)
- Root README version fix (v1.5.0 → v1.6.0)
- Docusaurus aid-run-epic stale text fix
- Brainstorm step count standardization to 8-step
- Agent frontmatter `name:` field addition (13 files)
- WebSocket replay shape mismatch fix
- App.tsx `.replace` → `.replaceAll` fix
- Backlog cleanup: move 7 zombie entries to Implemented
- CHANGELOG update

**Out-of-scope:**
- Authentication system (S-09 partial — host binding only, auth is a separate effort)
- Rate limiting (S-07 — requires design decisions on per-endpoint limits)
- Security headers / helmet (S-06 — small but separate concern)
- Skill YAML frontmatter (IQ-01 — large effort, 27 files, separate EPIC)
- Frontend accessibility (audit Frontend 0/100 — large effort, separate EPIC)
- Any items covered by P019 (pipeline bugs, test runner, Curator activation)

## Approach

**Two-phase execution** with maximum parallelism in Phase 1. All 14 fixes (Steps 1-14) are independent of each other — they touch different files with zero overlap. Phase 2 (Step 15: CHANGELOG/docs) depends on Phase 1 completing.

**Phase structure:**
- **Phase 1** (Steps 1-14): Security, documentation, code quality, and backlog fixes — all parallelizable
- **Phase 2** (Step 15): CHANGELOG and documentation updates — depends on Phase 1

**Alternatives considered:**
- *Two phases (security first, then docs/quality)* — rejected because all fixes are small and independent. A single phase with parallel groups is faster.
- *Merge into P019* — rejected because P019 focuses on pipeline reliability (bash scripts, test runner, gates). This plan focuses on security/docs/quality (TypeScript routes, markdown files). Different domains, different risk profiles.

## Implementation Steps

**EPIC 1: Steps 1-14 — Security, Documentation, Code Quality & Backlog Fixes**

### Step 1: Fix Path Traversal in Pipeline Theater Route (S-01)

**Objective:** Add `path.resolve()` + `startsWith()` bounds checking to the pipeline theater route to prevent filesystem traversal via `epicId` and `runId` parameters.

**Files:**
- Modify: `packages/aid-server/src/routes/pipeline.ts` (lines ~88-98) — add path containment guard after constructing `runDir`

**Architecture Context:**
The pipeline theater route (`GET /theater/:epicId/:runId`) serves EPIC run evidence to the PipelineTheater UI component. It reads `plan.json`, `plan_progress.json`, and `stage_log.jsonl` from the evidence directory. The route receives `epicId` and `runId` as URL parameters that are interpolated directly into `path.join(fs.aidoPath, '04-engine', 'evidence', epicId, runId)` at line 93. A malicious `epicId` like `../../secrets` would resolve to a path outside the evidence directory. The `fs.exists(runDir)` check at line 96 only validates existence, not containment.

**Implementation Detail:**
After line 93 (`const runDir = join(...)`), add a containment guard:
```typescript
import { resolve, sep } from 'path';

// Inside the route handler, after constructing runDir:
const evidenceBase = resolve(join(fs.aidoPath, '04-engine', 'evidence'));
const resolvedRunDir = resolve(runDir);
if (!resolvedRunDir.startsWith(evidenceBase + sep)) {
  return res.status(400).json({
    ok: false,
    error: { code: 'INVALID_PATH', message: 'Invalid epicId or runId' }
  });
}
```

Additionally, validate the parameter format at the top of the handler to reject obviously malicious input early:
```typescript
const ID_RE = /^[A-Za-z0-9_-]+$/;
if (!ID_RE.test(epicId) || !ID_RE.test(runId)) {
  return res.status(400).json({
    ok: false,
    error: { code: 'INVALID_ID', message: 'epicId and runId must be alphanumeric with hyphens/underscores' }
  });
}
```

Apply the same pattern to the `/progress` and `/stage-log` routes in the same file if they also use `epicId`/`runId` parameters.

**Error Handling:**
- If `resolve(runDir)` escapes the evidence base, return 400 with `INVALID_PATH` error code. Do not expose the resolved path in the error message (information disclosure).
- If the regex check fails, return 400 with `INVALID_ID`. This is the fast path that rejects payloads like `../../etc` before any filesystem access.

**Edge Cases:**
- `epicId` = `E-018-2_3` (valid, contains hyphens and underscores) — passes both regex and containment check
- `epicId` = `../../../etc` — fails regex check immediately (contains `/` and `.`)
- `epicId` = `E-018-2_3`, `runId` = `run-1` (standard format) — passes validation
- Symlink inside evidence directory pointing outside — `resolve()` follows symlinks, so containment check catches this

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Regex validation rejects `epicId`/`runId` containing path separator characters (`.`, `/`, `\`)
- [ ] `resolve()+startsWith()` guard rejects paths that escape the evidence directory
- [ ] Valid `epicId` like `E-018-2_3` with `runId` like `run-1` continues to work
- [ ] Error responses use 400 status with structured JSON (not 500)

**Effort:** S
**AID Role:** backend

---

### Step 2: Fix Path Traversal in GUI Evidence Routes (S-02)

**Objective:** Add path containment guards to the two evidence routes that use `epicId` and `runId` parameters without validation.

**Files:**
- Modify: `packages/aid-gui/server/api/evidence.ts` (lines ~181-184 and ~242-245) — add resolve+startsWith guard to `GET /:epicId` and `GET /:epicId/:runId`

**Architecture Context:**
The GUI embedded server has three evidence route groups: `GET /:epicId` (line 181), `GET /:epicId/:runId` (line 242), and `GET /:epicId/:runId/files/*` (line 266). The third route already has a proper containment guard (lines 290-295 check `resolvedFilePath.startsWith(resolvedRunDir + path.sep)`). The first two routes lack this guard. They construct `epicDirPath` and `runDirPath` via `path.join(evidenceBase(aidoPath), epicId)` and `path.join(evidenceBase(aidoPath), epicId, runId)` respectively. The `isDirectory()` check that follows only verifies the path exists as a directory, not that it's inside the evidence tree.

**Implementation Detail:**
Create a shared validation helper at the top of the file (or in a shared utils module):
```typescript
function validateEvidencePath(aidoPath: string, ...segments: string[]): string | null {
  const base = path.resolve(path.join(aidoPath, '04-engine', 'evidence'));
  const target = path.resolve(path.join(base, ...segments));
  if (!target.startsWith(base + path.sep) && target !== base) {
    return null;
  }
  return target;
}
```

Apply in both routes:
```typescript
// GET /:epicId
const epicDirPath = validateEvidencePath(aidoPath, epicId);
if (!epicDirPath) {
  res.status(400).json({ error: 'Invalid epicId' });
  return;
}

// GET /:epicId/:runId
const runDirPath = validateEvidencePath(aidoPath, epicId, runId);
if (!runDirPath) {
  res.status(400).json({ error: 'Invalid epicId or runId' });
  return;
}
```

**Error Handling:**
- Return 400 with a generic error message. Do not reveal the resolved path.
- The existing `isDirectory()` check remains as a secondary guard — the containment check runs first.

**Edge Cases:**
- `epicId` = `E-018-2_3` (valid) — passes containment check, proceeds to `isDirectory()`
- `epicId` = `../../etc` — fails containment check, returns 400
- `epicId` = `` (empty string) — `path.join(base, '')` resolves to `base` itself, which equals `base` (no `sep` suffix match). The `validateEvidencePath` allows `target === base` explicitly for the `/:epicId` route listing, but the subsequent `isDirectory()` check handles it.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `GET /:epicId` rejects path-traversal payloads with 400
- [ ] `GET /:epicId/:runId` rejects path-traversal payloads with 400
- [ ] Valid EPIC IDs (e.g., `E-018-2_3`) continue to work
- [ ] The existing `files/*` sub-route is not affected (already has its own guard)

**Effort:** S
**AID Role:** backend

---

### Step 3: Fix Path Traversal in POST /decisions Write Route (S-03)

**Objective:** Add path containment guard to the decision write route that constructs a filesystem write path from POST body fields.

**Files:**
- Modify: `packages/aid-gui/server/api/decisions.ts` (lines ~234-242) — add resolve+startsWith guard before writing `pm_decision.json`

**Architecture Context:**
The `POST /decisions` route receives `epicId` and `runId` in the request body (not URL params), trims them, and constructs `runDir = path.join(req.aidoPath, '04-engine', 'evidence', epicId, runId)` at line 242. It then writes `pm_decision.json` to that directory using atomic rename (lines 266-271). Since the values come from the POST body, an attacker can send arbitrary strings like `epicId: "../../etc"` and write files to arbitrary directories. The `fs.stat(runDir).isDirectory()` check at line 244 only prevents writes to non-existent paths.

**Implementation Detail:**
After trimming `epicId` and `runId` (lines 234-235), add validation:
```typescript
const ID_RE = /^[A-Za-z0-9_-]+$/;
if (!ID_RE.test(epicId) || !ID_RE.test(runId)) {
  res.status(400).json({ ok: false, error: { code: 'INVALID_ID', message: 'epicId and runId must be alphanumeric' } });
  return;
}

const evidenceBase = path.resolve(path.join(req.aidoPath, '04-engine', 'evidence'));
const runDir = path.join(evidenceBase, epicId, runId);
const resolvedRunDir = path.resolve(runDir);
if (!resolvedRunDir.startsWith(evidenceBase + path.sep)) {
  res.status(400).json({ ok: false, error: { code: 'INVALID_PATH', message: 'Invalid epicId or runId' } });
  return;
}
```

The regex check provides fast rejection of obviously malicious input. The resolve+startsWith check provides defense-in-depth against edge cases the regex might miss.

**Error Handling:**
- Return 400 with structured JSON error. Do not expose filesystem paths in error messages.
- The existing `fs.stat(runDir)` check remains for verifying the directory exists.

**Edge Cases:**
- `epicId` from PM decision form (e.g., `E-018-2_3`, `runId` = `run-1`) — passes both checks
- `epicId` = `../../etc` — fails regex check (contains `.` and `/`)
- Empty `epicId` or `runId` — already handled by the existing `if (!body.epicId || !body.runId)` check at line 230
- Extremely long `epicId` (1000+ chars) — passes regex but `path.join` handles it; filesystem will reject it naturally

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Regex validation rejects `epicId`/`runId` containing `.`, `/`, `\` characters
- [ ] `resolve()+startsWith()` guard prevents writes outside evidence directory
- [ ] Valid PM decision submissions continue to work
- [ ] Error responses use 400 status with structured JSON

**Effort:** S
**AID Role:** backend

---

### Step 4: Fix CORS Wildcard Misconfiguration (S-04)

**Objective:** Make `AID_CORS_ORIGINS=*` actually enable wildcard CORS by handling the `*` value as a special case before splitting into an array.

**Files:**
- Modify: `packages/aid-server/src/config.ts` (line ~21) — handle `'*'` before `.split(',')`

**Architecture Context:**
The aid-server reads `AID_CORS_ORIGINS` environment variable, splits it by comma into an array, and passes it to the `cors()` middleware as `origin: config.corsOrigins`. When the env var is set to `*` (as in `docker-compose.yml` line 32), the split produces `['*']`. The `cors` npm package treats an array as a whitelist of literal origin strings — it checks `request.headers.origin === '*'`, which never matches because browsers never send `Origin: *`. The wildcard `*` must be passed as a string directly (`origin: '*'`), not inside an array.

**Implementation Detail:**
Change line 21 of `config.ts` from:
```typescript
corsOrigins: (process.env.AID_CORS_ORIGINS ?? 'http://localhost:5173,http://localhost:3000,http://localhost:9911').split(','),
```
to:
```typescript
corsOrigins: (() => {
  const raw = process.env.AID_CORS_ORIGINS ?? 'http://localhost:5173,http://localhost:3000,http://localhost:9911';
  return raw.trim() === '*' ? '*' : raw.split(',').map(s => s.trim());
})(),
```

Update the `ServerConfig` interface type for `corsOrigins` from `string[]` to `string | string[]` (line 9):
```typescript
corsOrigins: string | string[];
```

The `cors()` middleware in `index.ts` (line 28) already accepts both `string` and `string[]` for the `origin` option — no change needed there.

**Error Handling:**
- If `AID_CORS_ORIGINS` contains mixed values like `*,http://localhost:3000`, treat it as a whitelist (split by comma). The `*` entry in the array will be ignored by the cors package — this is the expected behavior for a misconfigured value.
- If `AID_CORS_ORIGINS` is empty string, the default fallback applies.

**Edge Cases:**
- `AID_CORS_ORIGINS=*` → passes `'*'` as string → wildcard CORS enabled
- `AID_CORS_ORIGINS=http://localhost:5173,http://localhost:3000` → splits to array → whitelist mode
- `AID_CORS_ORIGINS` not set → default list → whitelist mode
- `AID_CORS_ORIGINS= * ` (with spaces) → `.trim()` normalizes to `'*'` → wildcard mode

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `AID_CORS_ORIGINS=*` results in wildcard CORS (any origin allowed)
- [ ] `AID_CORS_ORIGINS=http://localhost:5173,http://localhost:3000` results in whitelist CORS
- [ ] Default (no env var) continues to allow localhost origins
- [ ] `ServerConfig.corsOrigins` type updated to `string | string[]`

**Effort:** S
**AID Role:** backend

---

### Step 5: Add CORS Middleware to GUI Embedded Server (S-05)

**Objective:** Add `cors()` middleware to the aid-gui embedded Express server to control cross-origin access to the dashboard API.

**Files:**
- Modify: `packages/aid-gui/server/index.ts` (line ~117) — add `cors()` middleware in `createApp()`
- Modify: `packages/aid-gui/package.json` — add `cors` and `@types/cors` if not already present

**Architecture Context:**
The aid-gui package has its own Express server (`server/index.ts`) that serves REST API routes for pipeline, evidence, decisions, and other endpoints. Unlike the aid-server (which applies `app.use(cors({ origin: config.corsOrigins }))` at line 28 of its `index.ts`), the GUI server has no CORS middleware at all. The `createApp()` function at line 115 only applies `express.json()` before mounting routes. This means the GUI server accepts cross-origin requests from any origin without restriction, including write operations like `POST /decisions` and `POST /ideas`.

**Implementation Detail:**
1. Check if `cors` is already a dependency in `packages/aid-gui/package.json`. If not, it needs to be added.

2. In `packages/aid-gui/server/index.ts`, add the import and middleware:
```typescript
import cors from 'cors';

export function createApp() {
  const app = express();

  // CORS — restrict to same-origin in production, allow dev origins locally
  const allowedOrigins = process.env.AID_GUI_CORS_ORIGINS
    ? process.env.AID_GUI_CORS_ORIGINS.split(',').map(s => s.trim())
    : ['http://localhost:5173', 'http://localhost:3000'];
  app.use(cors({ origin: allowedOrigins }));

  app.use(express.json());
  // ... rest of routes
}
```

3. The default origins cover Vite dev server (5173) and the standard dev port (3000). Production deployments should set `AID_GUI_CORS_ORIGINS` to the actual GUI URL.

**Error Handling:**
- If `AID_GUI_CORS_ORIGINS` is unset, the default allows localhost origins only — this is safe for local development.
- Cross-origin requests from non-allowed origins receive a CORS error from the browser (the `cors` package returns no `Access-Control-Allow-Origin` header).

**Edge Cases:**
- Same-origin requests (GUI frontend to its own embedded server) — CORS is not enforced by browsers for same-origin, so these always work
- Docker Compose setup where GUI and server are on different ports — set `AID_GUI_CORS_ORIGINS` to include the server's origin
- Wildcard `*` in `AID_GUI_CORS_ORIGINS` — handled the same way as Step 4 if needed, but not critical for GUI server

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `cors()` middleware is applied in `createApp()` before route mounting
- [ ] Default allows `localhost:5173` and `localhost:3000`
- [ ] `AID_GUI_CORS_ORIGINS` env var overrides the default origins
- [ ] Cross-origin requests from non-allowed origins are rejected by the browser

**Effort:** S
**AID Role:** backend

---

### Step 6: Change Default Host Binding to 127.0.0.1 (S-09)

**Objective:** Change both servers to bind to `127.0.0.1` by default instead of `0.0.0.0`, so they are only accessible from the local machine unless explicitly configured otherwise.

**Files:**
- Modify: `packages/aid-server/src/config.ts` (line ~19) — change default from `'0.0.0.0'` to `'127.0.0.1'`
- Modify: `packages/aid-gui/server/index.ts` (line ~218) — change hardcoded `"0.0.0.0"` to configurable with `'127.0.0.1'` default
- Modify: `docker-compose.yml` — add `AID_HOST=0.0.0.0` to explicitly opt-in to all-interfaces binding in Docker (containers need this for port mapping)

**Architecture Context:**
The aid-server reads `AID_HOST` from the environment (defaulting to `'0.0.0.0'`) and passes it to `server.listen()` at line 87 of `index.ts`. The aid-gui server hardcodes `"0.0.0.0"` directly in its `server.listen()` call at line 218. Both servers expose unauthenticated endpoints: the aid-server has companion chat (spawns CLI), voice transcription (calls OpenAI API), and pipeline data. The GUI server writes decisions and ideas to the filesystem. Binding `0.0.0.0` makes all of these accessible to any device on the local network.

**Implementation Detail:**
1. In `packages/aid-server/src/config.ts` line 19, change:
```typescript
host: process.env.AID_HOST ?? '0.0.0.0',
```
to:
```typescript
host: process.env.AID_HOST ?? '127.0.0.1',
```

2. In `packages/aid-gui/server/index.ts` line 218, change:
```typescript
server.listen(PORT, "0.0.0.0", () => {
```
to:
```typescript
const HOST = process.env.AID_GUI_HOST ?? '127.0.0.1';
server.listen(PORT, HOST, () => {
```

3. In `docker-compose.yml`, under the `aid-server` service environment section, add:
```yaml
- AID_HOST=0.0.0.0
```
This ensures Docker containers still bind all interfaces (required for Docker port mapping to work).

**Error Handling:**
- If `AID_HOST` is set to an invalid address, `server.listen()` will throw `EADDRNOTAVAIL`. This is existing behavior — no change needed.
- If a user upgrades and their external clients stop connecting, the fix is to set `AID_HOST=0.0.0.0` explicitly.

**Edge Cases:**
- Local development (default) — binds 127.0.0.1, only localhost can access. This is the expected default.
- Docker Compose — `AID_HOST=0.0.0.0` is set explicitly, so container port mapping works
- WSL2 users accessing from Windows host — may need `AID_HOST=0.0.0.0` since Windows host is not 127.0.0.1 from WSL perspective. Document this in the README if needed.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] aid-server defaults to `127.0.0.1` when `AID_HOST` is not set
- [ ] aid-gui defaults to `127.0.0.1` when `AID_GUI_HOST` is not set
- [ ] `docker-compose.yml` explicitly sets `AID_HOST=0.0.0.0` for container use
- [ ] Setting `AID_HOST=0.0.0.0` explicitly still enables all-interfaces binding

**Effort:** S
**AID Role:** backend

---

### Step 7: Replace GUI README Gemini Boilerplate (C-01)

**Objective:** Replace the Gemini/AI Studio boilerplate README in `packages/aid-gui/` with accurate content describing the AID Dashboard GUI.

**Files:**
- Modify: `packages/aid-gui/README.md` — complete replacement of all content

**Architecture Context:**
The `packages/aid-gui/` package is a React + Vite application that provides the AID Dashboard — a web UI for monitoring EPIC pipeline execution, managing decisions, viewing evidence, and interacting with the AI companion. It has its own embedded Express server (`server/index.ts`) for API routes. The current README is a copy-paste from Google AI Studio boilerplate that references Gemini API keys and an unrelated app URL. This is the audit's only Critical finding.

**Implementation Detail:**
Replace the entire file with content that accurately describes:
1. What the package is (AID Dashboard — web UI for AID Orchestrator)
2. How to run it locally (`npm install` → `npm run dev`)
3. Required environment variables (none required for basic local dev; `AID_GUI_CORS_ORIGINS` and `AID_GUI_HOST` for custom configuration)
4. How it connects to aid-server (expects aid-server running on port 9911 by default)
5. Docker Compose usage (reference root `docker-compose.yml`)
6. Key screens: Pipeline Theater, Evidence Vault, Decision Hub, Ideas-to-Execution, Command Center

Keep the README concise — under 60 lines. This is a package-level README, not project documentation.

**Error Handling:**
- No runtime error handling — this is a documentation-only change.

**Edge Cases:**
- The image link on line 2 of the current README (`github.com/user-attachments/...`) may or may not be a valid project asset. Remove it — the GUI package README does not need a banner image.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] No references to Gemini, AI Studio, or `GEMINI_API_KEY` remain
- [ ] README describes how to run the GUI locally (`npm install`, `npm run dev`)
- [ ] README mentions the aid-server dependency (port 9911)
- [ ] README is under 60 lines

**Effort:** S
**AID Role:** docs

---

### Step 8: Fix Root README Version (D-01)

**Objective:** Update the version number on line 3 of the root README from v1.5.0 to v1.6.0.

**Files:**
- Modify: `README.md` (line ~3) — change `v1.5.0` to `v1.6.0`

**Architecture Context:**
The root README line 3 reads: `**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v1.5.0`. The CHANGELOG and Roadmap section of the same file correctly reference v1.6.0 as the current release. This is one of the 8 version sync locations defined in CLAUDE.md. It was missed during the v1.6.0 release.

**Implementation Detail:**
Change line 3 from:
```markdown
**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v1.5.0
```
to:
```markdown
**Multi-agent orchestration plugin for [Claude Code](https://claude.com/claude-code).** v1.6.0
```

**Error Handling:**
- No runtime error handling — this is a documentation-only change.

**Edge Cases:**
- If the current uncommitted work is about to become v1.7.0, this fix should still set it to v1.6.0 (the last released version). The v1.7.0 bump will happen in its own release step.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Line 3 of root README shows `v1.6.0`
- [ ] No other version references are changed (those belong to the release process)

**Effort:** S
**AID Role:** docs

---

### Step 9: Fix Docusaurus aid-run-epic Stale Text (D-02)

**Objective:** Correct the Docusaurus documentation for `/aid-run-epic` which falsely claims plan generation runs automatically.

**Files:**
- Modify: `docs/docs/commands/aid-run-epic.md` (line ~28) — remove the auto-generation claim

**Architecture Context:**
Since v1.6.0, the plan generation pipeline is script-based and must be run explicitly via `/aid-plan-epic` before `/aid-run-epic`. The `aid-run-epic` command now requires `plan.json` to already exist in the EPIC's evidence directory. Line 28 of the Docusaurus docs still says "If not, plan generation runs automatically" — this is stale from the pre-v1.6.0 behavior.

**Implementation Detail:**
Change line 28 from:
```markdown
- Plan JSON should exist (from [`/aid-plan-epic`](./aid-plan-epic)). If not, plan generation runs automatically.
```
to:
```markdown
- Plan JSON **must** exist (from [`/aid-plan-epic`](./aid-plan-epic)). Run `/aid-plan-epic` first to generate all execution artifacts.
```

**Error Handling:**
- No runtime error handling — this is a documentation-only change.

**Edge Cases:**
- Other Docusaurus pages that reference auto-generation — search for "runs automatically" or "auto-generat" across `docs/docs/` to catch any other stale references.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Line 28 states plan.json must exist (no auto-generation claim)
- [ ] References `/aid-plan-epic` as the prerequisite command
- [ ] No other Docusaurus pages contain stale auto-generation claims

**Effort:** S
**AID Role:** docs

---

### Step 10: Standardize Brainstorm Step Count to 8 (D-05)

**Objective:** Fix the three-way step count mismatch (README: 9, Docusaurus: 11, actual skill: 8) by standardizing all references to 8-step.

**Files:**
- Modify: `README.md` (lines ~28 and ~67) — change "9-step" to "8-step"
- Modify: `docs/docs/commands/aid-brainstorm.md` (lines ~43-57) — change "11 structured steps" to "8 structured steps" and update the step table to match the actual skill

**Architecture Context:**
The brainstorming skill (`plugins/aid-orchestrator/skills/brainstorming.md`) defines an 8-step lifecycle: Steps 1-8 where Step 8 delegates plan writing. The root README says "9-step" (lines 28 and 67). The Docusaurus brainstorm command doc says "11 structured steps" and includes steps 9 (EPIC Subagent), 10 (Execution Plan), and 11 (Handoff) that were removed or consolidated into Step 8 in a previous version. The single source of truth is the skill file.

**Implementation Detail:**
1. In `README.md` line 28, change:
```markdown
# → 9-step interactive dialog: context, approaches, trade-offs, architecture, plan
```
to:
```markdown
# → 8-step interactive dialog: context, approaches, trade-offs, architecture, plan
```

2. In `README.md` line 67, change:
```markdown
| `/aid-brainstorm [topic]` | 9-step interactive brainstorming → plan + optional EPIC |
```
to:
```markdown
| `/aid-brainstorm [topic]` | 8-step interactive brainstorming → plan + optional EPIC |
```

3. In `docs/docs/commands/aid-brainstorm.md` line 43, change:
```markdown
The command guides you through 11 structured steps:
```
to:
```markdown
The command guides you through 8 structured steps:
```

4. Update the step table (lines 45-57) to remove steps 9-11 (EPIC Subagent, Execution Plan, Handoff) and adjust remaining step descriptions to match the actual skill. Step 8 should be described as "Document + Handoff — writes the plan document and presents next steps."

**Error Handling:**
- No runtime error handling — this is a documentation-only change.

**Edge Cases:**
- The plugin README (`plugins/aid-orchestrator/README.md`) may also reference a step count — check and update if needed.
- The `/aid-help` command doc may reference the step count — check and update if needed.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Root README says "8-step" on both lines 28 and 67
- [ ] Docusaurus aid-brainstorm.md says "8 structured steps" with correct step table
- [ ] No document in the project references "9-step" or "11-step" brainstorming
- [ ] Step table in Docusaurus matches the actual skill's 8-step lifecycle

**Effort:** S
**AID Role:** docs

---

### Step 11: Add name: Field to 13 Agent Frontmatter Files (IQ-02)

**Objective:** Add the missing `name:` field to the YAML frontmatter of 13 agent files that currently only have `model:`.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/architect.md` — add `name: architect`
- Modify: `plugins/aid-orchestrator/agents/backend.md` — add `name: backend`
- Modify: `plugins/aid-orchestrator/agents/frontend.md` — add `name: frontend`
- Modify: `plugins/aid-orchestrator/agents/domain.md` — add `name: domain`
- Modify: `plugins/aid-orchestrator/agents/qa.md` — add `name: qa`
- Modify: `plugins/aid-orchestrator/agents/security.md` — add `name: security`
- Modify: `plugins/aid-orchestrator/agents/docs-writer.md` — add `name: docs-writer`
- Modify: `plugins/aid-orchestrator/agents/observability.md` — add `name: observability`
- Modify: `plugins/aid-orchestrator/agents/release.md` — add `name: release`
- Modify: `plugins/aid-orchestrator/agents/project-scanner.md` — add `name: project-scanner`
- Modify: `plugins/aid-orchestrator/agents/gate-fixer.md` — add `name: gate-fixer`
- Modify: `plugins/aid-orchestrator/agents/curator.md` — add `name: curator`
- Modify: `plugins/aid-orchestrator/agents/auditor.md` — add `name: auditor`

**Architecture Context:**
Claude Code's plugin system uses YAML frontmatter in agent files for registration. The `name:` field identifies the agent in the dispatch system (visible in `plugin.json` agent listings and in Task tool's `subagent_type` parameter). Five agents already have `name:` (docs-reviewer, run-validator, lessons-extractor, code-reviewer, quality-gates-runner). The 13 missing agents only have `model:` in their frontmatter. Without `name:`, the agent's identity is inferred from the filename stem, but the field should be explicit for consistency and to match the 5 agents that already have it.

**Implementation Detail:**
For each of the 13 files, change the frontmatter from:
```yaml
---
model: {opus|sonnet|haiku}
---
```
to:
```yaml
---
name: {filename-stem}
model: {opus|sonnet|haiku}
---
```

The `name` value should match the filename stem exactly (e.g., `architect.md` → `name: architect`, `docs-writer.md` → `name: docs-writer`). This follows the pattern established by the 5 agents that already have the field.

**Error Handling:**
- No runtime error handling — this is a metadata change.
- If a `name:` value conflicts with an existing agent registration, the plugin validator will catch it during `/plugin validate`.

**Edge Cases:**
- Agent files that also need `description:` — the audit only flags `name:` as missing. Adding `description:` is a separate concern (related to IQ-01 skill frontmatter) and out of scope for this step.
- The 5 agents that already have `name:` — do not modify them.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] All 18 agent files in `plugins/aid-orchestrator/agents/` have `name:` in frontmatter
- [ ] Each `name:` value matches the filename stem
- [ ] `/plugin validate .` passes without errors (if available)

**Effort:** S
**AID Role:** backend

---

### Step 12: Fix WebSocket Replay Shape Mismatch (IMP-053)

**Objective:** Fix the client-side `dispatchReplay()` function to correctly consume raw stage log entries from the server's replay message, instead of expecting a non-existent `.entry` wrapper.

**Files:**
- Modify: `packages/aid-gui/src/hooks/useWebSocket.ts` (lines ~289-295) — fix `dispatchReplay` to read `item` directly instead of `item.entry`

**Architecture Context:**
The WebSocket handler in aid-server (`ws/handler.ts` lines 139-146) sends replay messages with raw stage log entries in the `data` array: `{ type: 'replay', topic: 'pipeline.stage_log', data: allEntries.slice(-200) }`. Each element in `data` is a raw JSONL object (e.g., `{ state: "DISPATCH", action: "...", timestamp: "..." }`). The client's `dispatchReplay()` at line 291 maps each item as `toStageLogEntry(item.entry)`, expecting each element to be wrapped as `{ entry: rawEntry }`. Since the server sends unwrapped entries, `item.entry` is always `undefined`, and all replayed stage log entries are silently lost. This means stage log history is empty after every WebSocket reconnection.

**Implementation Detail:**
Change line 291 of `useWebSocket.ts` from:
```typescript
const entries = msg.data.map((item) => toStageLogEntry(item.entry));
```
to:
```typescript
const entries = msg.data.map((item) => toStageLogEntry(item.entry ?? item));
```

The `item.entry ?? item` pattern is defensive: if the server is ever updated to wrap entries (future-proofing), the `.entry` path works. If the server sends raw entries (current behavior), `item.entry` is undefined and `item` itself is used. This avoids requiring a coordinated server+client deploy.

**Error Handling:**
- `toStageLogEntry()` should handle `undefined` or malformed input gracefully — verify it returns a sensible default or empty object rather than throwing.
- If both `item.entry` and `item` are malformed, the stage log entry will have default/empty fields. This is better than the current behavior (all fields undefined).

**Edge Cases:**
- Server sends wrapped entries in a future version (`{ entry: rawEntry }`) — the `item.entry` path handles this correctly
- Server sends raw entries (current behavior) — the `item` fallback handles this correctly
- Empty replay (`data: []`) — the `entries.length > 0` guard at line 292 prevents an empty store update
- Replay with 200 entries (max) — all 200 are correctly mapped and added to the store

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] After WebSocket reconnection, stage log entries from the replay are visible in the Pipeline Theater
- [ ] `dispatchReplay` correctly maps raw entries (without `.entry` wrapper)
- [ ] No regression for live (non-replay) stage log events
- [ ] Empty replays (`data: []`) do not cause errors

**Effort:** S
**AID Role:** frontend

---

### Step 13: Fix App.tsx .replace() First-Match-Only Bug (CQ-05)

**Objective:** Fix the CSS custom property generation in App.tsx that only replaces the first underscore in FSM state names, causing incorrect CSS variable references for multi-underscore states.

**Files:**
- Modify: `packages/aid-gui/src/App.tsx` (lines ~139-140) — change `.replace('_', '-')` to `.replaceAll('_', '-')`

**Architecture Context:**
The App component sets CSS custom properties `--state-color` and `--state-glow-color` based on the current FSM state name. The state name (e.g., `PLAN_REVIEW`) is lowercased and underscores are replaced with hyphens to form a CSS variable reference like `var(--color-state-plan-review)`. However, JavaScript's `String.replace()` with a string argument (not regex) only replaces the first occurrence. A state like `CURATOR_RESOLVE` produces `curator-resolve` (correct, single underscore). But a hypothetical state with multiple underscores would only have the first one replaced. Additionally, there is a `@ts-ignore` on line 138 suppressing a real CSS property type violation.

**Implementation Detail:**
Change lines 139-140 from:
```typescript
'--state-color': `var(--color-state-${fsmState.toLowerCase().replace('_', '-')})`,
'--state-glow-color': `var(--color-state-${fsmState.toLowerCase().replace('_', '-')})44`
```
to:
```typescript
'--state-color': `var(--color-state-${fsmState.toLowerCase().replaceAll('_', '-')})`,
'--state-glow-color': `var(--color-state-${fsmState.toLowerCase().replaceAll('_', '-')})44`
```

`.replaceAll()` is available in all modern browsers and Node.js 15+. The project targets modern browsers (React + Vite), so this is safe.

Optionally, also address the `@ts-ignore` on line 138 by extracting the style computation into a variable typed appropriately, but this is a separate concern and not required for this fix.

**Error Handling:**
- If `fsmState` is `undefined` or `null`, `.toLowerCase()` will throw. Check if there's already a guard — if not, this is a pre-existing issue unrelated to this fix.

**Edge Cases:**
- `fsmState` = `PLAN_REVIEW` (one underscore) → `plan-review` — works correctly with both `.replace` and `.replaceAll`
- `fsmState` = `IDLE` (no underscore) → `idle` — no replacement needed, works correctly
- `fsmState` = `PHASE_CHECK` (one underscore) → `phase-check` — works correctly
- Current FSM states with multiple underscores: verify if any exist in the current state machine. Even if none currently exist, `.replaceAll` is the correct method for robustness.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] Lines 139-140 use `.replaceAll('_', '-')` instead of `.replace('_', '-')`
- [ ] All FSM state names (including future multi-underscore states) produce correct CSS variable references
- [ ] No TypeScript compilation errors introduced

**Effort:** S
**AID Role:** frontend

---

### Step 14: Clean Up 7 Zombie Backlog Entries

**Objective:** Move 7 backlog entries that were already fixed (but never updated in the backlog) from the Active Proposals table to the Implemented table, preventing duplicate work.

**Files:**
- Modify: `.aid-o/04-engine/backlog.md` — move 7 entries from Active to Implemented section

**Architecture Context:**
The backlog is managed by the AID Curator agent during EPIC runs. When fixes are applied inline by the Curator (marked with `[IMPLEMENTED inline]` tags) or by regular development, the backlog entries should be moved to the Implemented section. Seven entries were verified as already fixed in the current codebase but remain in the Active Proposals table. This creates a risk of re-work: a future Curator or PM might pick up these entries and attempt to fix something that is already fixed.

**Implementation Detail:**
Move these 7 entries from the Active Proposals table to the Implemented table:

| ID | What was reported | Why it's invalid | Move to Implemented with note |
|----|---|---|---|
| **IMP-010** | 18/19 commands missing `user_invocable: true` | All 14 command files have `user_invocable: true` in frontmatter | `Implemented — all 14 commands have frontmatter (verified 2026-02-28)` |
| **IMP-035** | `/aid-help` omits `/aid-first-aid` and `/aid-stop` | Both are listed on lines 80-81 and detailed on lines 197-212 | `Implemented — both commands documented in aid-help (verified 2026-02-28)` |
| **IMP-049** | `handleLinkEpic` calls `updateIdea` instead of `linkIdea` | Line 631 calls `client.linkIdea()` correctly | `Implemented — handleLinkEpic calls linkIdea (verified 2026-02-28)` |
| **IMP-050** | GET /backlog reads from `memory/backlog.md` (wrong path) | `backlog.ts:59` reads from `04-engine/backlog.md` (correct) | `Implemented — correct path in backlog.ts (verified 2026-02-28)` |
| **IMP-057** | `dangerouslySetInnerHTML` XSS in AICompanion | `lib/companion.ts` `md()` wraps output in `DOMPurify.sanitize()` | `Implemented — DOMPurify applied in md() function (verified 2026-02-28)` |
| **IMP-059** | sessionId path traversal in session-store | UUID v4 regex validation at every call site via `isValidSessionId()`/`assertValidSessionId()` | `Implemented — UUID v4 validation guards all paths (verified 2026-02-28)` |
| **IMP-067** | `stepsTotal == stepsCompleted` (same field) | `stepsTotal` computed from `per_epic[].steps_total`; `total_steps_executed` is only fallback | `Implemented — stepsTotal uses per_epic aggregate (verified 2026-02-28)` |

For each entry:
1. Remove the row from the Active Proposals table
2. Add a row to the Implemented table with the format: `| {ID} | {type} | {area} | Verified fixed 2026-02-28 — {brief note} | 2026-02-28 |`
3. Update the "Active proposals" count in the header line (62 → 55)

**Error Handling:**
- If the backlog file format has changed since the last read, the Curator manages the file — manual edits should follow the existing table format exactly.

**Edge Cases:**
- IMP-057 and IMP-059 have `[IMPLEMENTED inline E-016-2_3 curator fix]` tags in their descriptions — these confirm the fixes were applied during that EPIC run. The Curator noted the implementation but did not move the entries to Implemented.
- IMP-050, IMP-049, IMP-067 have no implementation tags — they were fixed by regular development without Curator involvement.

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] 7 entries (IMP-010, IMP-035, IMP-049, IMP-050, IMP-057, IMP-059, IMP-067) removed from Active Proposals
- [ ] 7 corresponding entries added to Implemented table with verification notes
- [ ] Active proposals count in header updated from 62 to 55
- [ ] No other backlog entries are modified

**Effort:** S
**AID Role:** docs

---

**EPIC 2: Steps 15-15 — CHANGELOG and Documentation Updates**

### Step 15: Update CHANGELOG and Documentation

**Objective:** Add CHANGELOG entries for all changes in this plan and update `Last Updated` dates in modified files.

**Files:**
- Modify: `CHANGELOG.md` — add entries under `## [Unreleased]`
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical to root CHANGELOG
- Modify: All agent files modified in Step 11 — update any `Last Updated` footer if present

**Architecture Context:**
Per CLAUDE.md rules: both CHANGELOGs must be identical, every modified skill/agent file must have its `Last Updated` date bumped, and the CHANGELOG format follows Keep a Changelog with `- **Bold Name** — description` entries. This step ensures documentation consistency across all changes.

**Implementation Detail:**
Add entries under `## [Unreleased]` (create the section if it doesn't exist, above `## [1.6.0]`):

```markdown
## [Unreleased]

### Fixed
- **Path Traversal in Route Handlers** — added resolve()+startsWith() bounds checking to pipeline theater, evidence, and decisions routes (CWE-22 mitigation)
- **CORS Wildcard Misconfiguration** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of failing silently as a literal string match
- **WebSocket Replay Data Loss** — fixed shape mismatch in `dispatchReplay()` that silently discarded all stage log entries on reconnect
- **CSS Variable First-Match Bug** — `.replace('_', '-')` changed to `.replaceAll('_', '-')` in App.tsx FSM state color mapping
- **GUI README Gemini Boilerplate** — replaced Google AI Studio template with accurate AID Dashboard documentation
- **Root README Version** — corrected inline version from v1.5.0 to v1.6.0
- **Docusaurus aid-run-epic** — removed stale claim that plan generation runs automatically (plan.json must now pre-exist)
- **Brainstorm Step Count** — standardized all references to 8-step (was 9 in README, 11 in Docusaurus)

### Added
- **GUI Server CORS Middleware** — `cors()` middleware added to aid-gui embedded Express server with configurable origins via `AID_GUI_CORS_ORIGINS`
- **Agent Frontmatter name: Field** — added `name:` to 13 agent files for consistent plugin registration

### Changed
- **Default Host Binding** — both servers now default to `127.0.0.1` instead of `0.0.0.0` (set `AID_HOST=0.0.0.0` to restore old behavior)
- **Backlog Cleanup** — 7 zombie entries (IMP-010, IMP-035, IMP-049, IMP-050, IMP-057, IMP-059, IMP-067) moved to Implemented after verification
```

Copy the identical content to `plugins/aid-orchestrator/CHANGELOG.md`.

**Error Handling:**
- No runtime error handling — documentation only.

**Edge Cases:**
- If `## [Unreleased]` already exists from P019 changes, append to it (do not create a duplicate section).
- Agent files may not have `Last Updated` footers — only update the footer if one already exists. Do not add new footers to files that don't have them.

**Dependencies:**
- No dependencies within this EPIC — chain queue mode ensures Phase 1 (Steps 1-14) is complete before Phase 2 starts

**Acceptance Criteria:**
- [ ] Root `CHANGELOG.md` contains all entries under `## [Unreleased]`
- [ ] `plugins/aid-orchestrator/CHANGELOG.md` is identical to root
- [ ] All modified files with existing `Last Updated` footers are bumped to current date
- [ ] CHANGELOG entries follow the `- **Bold Name** — description` format

**Effort:** S
**AID Role:** docs

---

## Testing Strategy

**Security fixes (Steps 1-3):** Test with curl using path traversal payloads:
```bash
curl http://localhost:9911/api/p/default/pipeline/theater/../../etc/run-1  # should return 400
curl -X POST http://localhost:3000/api/p/default/decisions -d '{"epicId":"../../etc","runId":"x"}'  # should return 400
```
Verify that valid EPIC IDs (e.g., `E-018-2_3/run-1`) continue to work.

**CORS fix (Step 4):** Set `AID_CORS_ORIGINS=*`, start the server, and verify cross-origin requests from a different port are accepted. Then set to a specific origin list and verify only those origins work.

**WebSocket replay (Step 12):** Start both servers, connect to the GUI, trigger a WebSocket reconnection (e.g., restart aid-server briefly), and verify stage log entries appear in the Pipeline Theater after reconnect.

**CSS variable fix (Step 13):** Check that FSM state colors render correctly for all states in the GUI. No state should show a fallback/default color when a specific color is defined.

**Documentation fixes (Steps 7-10):** Visual review of changed files. No automated tests needed.

**Agent frontmatter (Step 11):** Run `/plugin validate .` if available, or manually verify all 18 agent files have `name:` field.

## Constraints

- No new npm dependencies except `cors` + `@types/cors` for the GUI server (Step 5) — and only if not already present
- All security fixes must use defense-in-depth (regex + resolve+startsWith, not just one)
- Both CHANGELOGs must remain identical at all times
- Changes must not break Docker Compose deployment (`AID_HOST=0.0.0.0` explicit in docker-compose.yml)
- Backlog edits must follow the existing table format exactly

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Host binding change breaks Docker | Low | High | Explicit `AID_HOST=0.0.0.0` in docker-compose.yml |
| CORS type change (`string \| string[]`) causes TS errors | Low | Low | The `cors` package accepts both types natively |
| Backlog manual edit conflicts with Curator | Medium | Low | Step 14 follows the exact table format; next Curator run will merge cleanly |
| WSL2 users lose access after 127.0.0.1 default | Low | Medium | Document `AID_HOST=0.0.0.0` workaround in README |

## Success Criteria

- [ ] All 3 path traversal vulnerabilities are fixed with defense-in-depth (regex + containment check)
- [ ] `AID_CORS_ORIGINS=*` enables actual wildcard CORS
- [ ] GUI server has CORS middleware
- [ ] Both servers default to 127.0.0.1 (with Docker override)
- [ ] GUI README accurately describes the AID Dashboard
- [ ] All version references show v1.6.0
- [ ] All brainstorm step references say 8-step
- [ ] All 18 agent files have `name:` in frontmatter
- [ ] WebSocket replay correctly populates stage log after reconnect
- [ ] FSM state CSS variables handle multi-underscore states
- [ ] 7 zombie backlog entries moved to Implemented
- [ ] CHANGELOG is complete and identical in both locations

## Next Steps

After plan approval:
1. Run `/aid-plan-epic .aid-o/01-plans/P020-audit-security-quality-hardening.md` to generate EPICs
2. Run `/aid-epic-queue` to verify queue
3. Run `/aid-first-aid` or `/aid-run-epic` to execute
