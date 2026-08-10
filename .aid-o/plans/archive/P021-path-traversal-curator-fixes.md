---
id: P021
type: plan
status: done
created: "2026-02-28"
author: "pm+claude"
---

# P021 — Path Traversal Guards + Curator Process Fixes

## Context

AID Orchestrator is a Claude Code plugin with two Express.js servers: `aid-server` (main API) and `aid-gui` (dashboard backend). EPIC E-020-1_2 added CWE-22 path traversal guards to `pipeline.ts`, `decisions.ts`, and the GUI `evidence.ts` routes. A shared helper module `path-validation.ts` provides `isValidPathComponent()`, `isWithinDirectory()`, and `validateEvidencePath()`. However, the Curator review (FIRST AID session FA-20260228T180451Z) identified **3 additional routes** that still pass user-supplied URL parameters directly into `path.join()` without validation — audit.ts (aid-gui), epics.ts (aid-server), and evidence.ts (aid-server). Additionally, two documentation cross-reference issues and one script classification bug were found.

Tech stack: TypeScript, Express.js, Node.js `path` module, bash scripts.
Pattern to follow: defense-in-depth from `path-validation.ts` — regex rejection + resolve + startsWith.

## Goal

All user-supplied path parameters (`epicId`, `runId`, wildcard `files/*`) across both servers are validated against CWE-22 path traversal. Curator documentation cross-references are fixed. Extensionless file classification in the EPIC generation script is corrected.

## Scope

### Affected files

- `packages/aid-server/src/routes/evidence.ts` — fix `startsWith` on unresolved path
- `packages/aid-gui/server/api/audit.ts` — add `isValidPathComponent` guard
- `packages/aid-server/src/routes/epics.ts` — add `isValidPathComponent` guard
- `plugins/aid-orchestrator/skills/improvement-proposals.md` — add cross-reference
- `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` — fix extensionless heuristic

### Not in scope

- `packages/aid-gui/src/` (frontend React code)
- `packages/aid-server/src/routes/companion.ts` (separate concern, no path params at risk)
- `packages/aid-server/src/routes/pipeline.ts` (already fixed in E-020-1_2)
- `packages/aid-gui/server/api/evidence.ts` (already correct — uses normalize+resolve+startsWith)
- `packages/aid-gui/server/api/decisions.ts` (already fixed in E-020-1_2)
- IMP-077 (`aid-run-epic.md` file refs) — verified resolved; `step_output.json` no longer appears in dispatch templates

## Approach

Each security fix follows the identical defense-in-depth pattern established in E-020-1_2:

1. **Layer 1 — Regex rejection:** Call `isValidPathComponent(param)` on every user-supplied path segment. This rejects `.`, `/`, `\` characters before any path construction.
2. **Layer 2 — Bounds checking:** After `path.join()`, call `path.resolve()` and verify with `startsWith(resolvedBase + path.sep)`. This catches encoding tricks the regex missed.

The helpers already exist — no new utility code is needed. Each step is a 2-5 line addition to an existing route handler.

## Implementation Steps

**EPIC 1: Steps 1-3 — Security Fixes**

### Step 1: Fix aid-server evidence.ts path traversal

**Objective:** Replace the broken `startsWith` check on unresolved path with proper `path.resolve()` validation. Add `isValidPathComponent` guards on `epicId` and `runId` parameters.

**Files:**
- Modify: `packages/aid-server/src/routes/evidence.ts`

**Architecture Context:** The `GET /:epicId/:runId/files/*` route at line 44 constructs a filesystem path using `path.join(fs.aidoPath, '04-engine', 'evidence', epicId, runId, filePath)`. The current check at line 55 (`fullPath.startsWith(evidenceBase)`) operates on the unresolved string — `path.join()` preserves `..` segments in the output string, so a request like `GET /evidence/E-001/run1/files/../../../../etc/passwd` would pass the prefix check. The GUI equivalent at `aid-gui/server/api/evidence.ts:304-319` correctly uses `path.normalize()` + `path.resolve()` + `startsWith()` with `path.sep` suffix.

**Implementation Detail:**
1. Add import: `import { isValidPathComponent, isWithinDirectory } from './path-validation.js';`
2. After line 48 (`const filePath = req.params['0'] ?? '';`), add:
   ```typescript
   if (!isValidPathComponent(req.params.epicId) || !isValidPathComponent(req.params.runId)) {
     return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'Invalid path parameter' } });
   }
   ```
3. Replace lines 53-57 (the existing `startsWith` check) with:
   ```typescript
   const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
   const resolvedFull = path.resolve(fullPath);
   const resolvedBase = path.resolve(evidenceBase);
   if (!isWithinDirectory(resolvedFull, resolvedBase)) {
     return res.status(403).json({ ok: false, error: { code: 'FORBIDDEN', message: 'Path traversal not allowed' } });
   }
   ```
4. Add `import * as path from 'node:path';` if not already present (file uses `join` from destructured import — need the namespace for `path.resolve`).

**Error Handling:** Returns 400 for invalid path component characters, 403 for resolved path escaping evidence directory. Existing 404 for missing files remains unchanged.

**Edge Cases:**
- `epicId` containing URL-encoded dots (`%2e%2e`) — Express decodes params before route handler, so `..` arrives decoded; regex catches the dots.
- `filePath` (wildcard `*`) containing `..` — `path.resolve()` catches this in Layer 2 even though Layer 1 only validates `epicId` and `runId`.
- Empty `filePath` — already handled at line 49 (returns 400).

**Dependencies:** `path-validation.ts` exists in same directory (created in E-020-1_2).

**Acceptance Criteria:**
- [ ] `curl /evidence/../../etc/run1/files/x` returns 400 (invalid epicId)
- [ ] `curl /evidence/E-001/run1/files/../../../etc/passwd` returns 403 (path escapes evidence)
- [ ] `curl /evidence/E-001/run1/files/plan.json` still returns 200 for existing files
- [ ] No TypeScript compilation errors

**Effort:** S

**AID Role:** security

### Step 2: Fix aid-gui audit.ts path traversal

**Objective:** Add `isValidPathComponent` guard on `epicId` parameter before using it in `path.join()`.

**Files:**
- Modify: `packages/aid-gui/server/api/audit.ts`

**Architecture Context:** The `GET /audit/:epicId` route at line 157 passes `req.params.epicId` directly into `path.join(req.aidoPath, '04-engine', 'evidence', epicId)` at line 165. No validation exists. An attacker could use `GET /audit/../../etc` to traverse outside the evidence directory. The GUI middleware module at `packages/aid-gui/server/api/middleware.ts` already exports `isValidPathComponent`.

**Implementation Detail:**
1. Add import: `import { isValidPathComponent } from './middleware.js';` (or add to existing import if middleware is already imported).
2. After line 159 (`const epicId = req.params.epicId;`), immediately before the `if (!epicId)` check, add:
   ```typescript
   if (!isValidPathComponent(epicId)) {
     sendError(res, 400, 'BAD_REQUEST', 'Invalid EPIC ID');
     return;
   }
   ```
3. The existing `!epicId` check on line 160 becomes redundant (isValidPathComponent rejects empty strings) but leave it for readability.

**Error Handling:** Returns 400 with `BAD_REQUEST` code. Existing 404 for missing directories and 500 for internal errors unchanged.

**Edge Cases:**
- `epicId` = `"audit-2026"` (contains hyphen, no dots) — passes validation (hyphens are safe).
- `epicId` = `"..%2f..%2fetc"` — Express decodes to `../../etc`, dots caught by regex.
- The `GET /audit/` (list) route at line 9 does not use params — not affected.

**Dependencies:** `middleware.ts` already exports `isValidPathComponent` (created in E-020-1_2).

**Acceptance Criteria:**
- [ ] `curl /audit/../../etc` returns 400
- [ ] `curl /audit/E-020-1_2` still returns valid audit data (or 404 if no report)
- [ ] No TypeScript compilation errors

**Effort:** S

**AID Role:** security

### Step 3: Fix aid-server epics.ts path injection

**Objective:** Add `isValidPathComponent` guard on `epicId` parameter in the run endpoint to prevent path injection via `readdir` filename matching and YAML queue entry creation.

**Files:**
- Modify: `packages/aid-server/src/routes/epics.ts`

**Architecture Context:** The `POST /:epicId/run` route at line 137 uses `req.params.epicId` in `files.find(f => f.startsWith(${epicId}-))` at line 159 and writes it into `epic-queue.yaml` as `epic_id` and in the `path` field. While this route doesn't directly serve files (lower severity than Steps 1-2), a crafted `epicId` with path separators could match unexpected filenames via `startsWith()` and inject malformed entries into the queue YAML. The `path-validation.ts` helper exists in the same package.

**Implementation Detail:**
1. Add import: `import { isValidPathComponent } from './path-validation.js';`
2. After line 151 (`const epicId = req.params.epicId;`), add:
   ```typescript
   if (!isValidPathComponent(epicId)) {
     return res.status(400).json({
       ok: false,
       error: { code: 'BAD_REQUEST', message: 'Invalid EPIC ID' },
     });
   }
   ```

**Error Handling:** Returns 400 before any filesystem access. Existing 404 (EPIC not found) and 409 (already queued) unchanged.

**Edge Cases:**
- `epicId` = `"E-021-path-traversal"` — contains hyphens, no dots → passes.
- `epicId` = `"../../../etc"` — dots caught by regex → 400.
- The `GET /epics/` (list) route at line 80 does not use epicId param — not affected.

**Dependencies:** `path-validation.ts` exists in same directory.

**Acceptance Criteria:**
- [ ] `curl -X POST /epics/../../etc/run -d '{"mode":"now"}'` returns 400
- [ ] `curl -X POST /epics/E-021/run -d '{"mode":"now"}'` still works (or 404 if EPIC missing)
- [ ] No TypeScript compilation errors

**Effort:** S

**AID Role:** security

**EPIC 2: Steps 4-5 — Documentation + Script Fixes**

### Step 4: Fix improvement-proposals.md cross-reference

**Objective:** Add `first-aid-controller.md` cross-reference for auto-mode CURATOR_RESOLVE behavior to Section 6 of `improvement-proposals.md`.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/improvement-proposals.md`

**Architecture Context:** Section 6 ("Orchestrator Integration — CURATOR_RESOLVE State") at line 274 describes the 3-tier auto-evaluate algorithm. It references `epic-orchestration.md` (line 379) and `run-epic.md` (line 380) but does NOT reference `first-aid-controller.md`, which contains the auto-mode override behavior (unconditional dispatch, effort-based deferral threshold). Agents consulting Section 6 during auto-mode miss the FIRST AID-specific rules.

**Implementation Detail:**
1. After the Section 6 closing (after the reference table ending at line 380), add a new paragraph:
   ```markdown
   For CURATOR_RESOLVE auto-mode behavior (unconditional dispatch, effort-based deferral threshold), **see:** `skills/first-aid-controller.md` Section "CURATOR_RESOLVE — Auto-Mode Behavior".
   ```
2. Add to the reference table:
   ```markdown
   | `first-aid-controller.md` | CURATOR_RESOLVE auto-mode overrides — unconditional dispatch, effort threshold |
   ```
3. Update `**Last Updated:**` date at the file footer.

**Error Handling:** N/A (documentation change).

**Edge Cases:** N/A.

**Dependencies:** None.

**Acceptance Criteria:**
- [ ] `grep "first-aid-controller" improvement-proposals.md` returns at least 2 matches (cross-ref + table row)
- [ ] `Last Updated` date is current

**Effort:** S

**AID Role:** docs

### Step 5: Fix extensionless file heuristic in aid-plan-to-epic.sh

**Objective:** Add an allowlist of known extensionless filenames so the scope classification logic treats them as files, not directories.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh`

**Architecture Context:** The scope classification awk block starting at line 580 splits paths into files (have extension) and directories (end with `/` or have no extension in basename). The heuristic `basename !~ /\./` at line 584 treats any path whose last segment has no dot as a directory. This misclassifies common extensionless files like `Dockerfile`, `Makefile`, `Procfile`, `.gitignore`, `.env`, `.dockerignore`, `.editorconfig`, `Vagrantfile`, `Gemfile`, `Rakefile`, `LICENSE`, `CODEOWNERS`. These get emitted as directory paths, which are then suppressed when file-level paths in the same directory exist — effectively dropping them from scope.

**Implementation Detail:**
1. In the awk block (line 580-612), before the classification at line 584, add an extensionless file allowlist check:
   ```awk
   # Known extensionless files — always classify as file, not directory
   if (basename ~ /^(Dockerfile|Makefile|Procfile|Vagrantfile|Gemfile|Rakefile|LICENSE|CODEOWNERS|Brewfile)$/ ||
       basename ~ /^\./) {
     # Dotfiles (.env, .gitignore, .dockerignore, .editorconfig) and
     # known capitalized files are always files
     nf++; files[nf] = $0
     next
   }
   ```
2. Place this BEFORE the existing `if ($0 ~ /\/$/ || basename !~ /\./)` block so the allowlist takes priority.
3. The `basename ~ /^\./` catch handles all dotfiles (they start with `.`, which the current heuristic sees as "has no extension" since the dot is the first character, not a separator).

**Error Handling:** Invalid paths are already handled upstream (empty lines filtered, paths trimmed). The awk block processes only non-empty, trimmed path strings.

**Edge Cases:**
- `src/Dockerfile` — basename `Dockerfile` matches allowlist → classified as file. Correct.
- `src/.env.example` — basename starts with `.` → classified as file. Correct (has dot but also starts with dot).
- `docker/` — ends with `/` → classified as directory by existing check (runs before allowlist). Correct.
- `src/utils` — no extension, not in allowlist, no leading dot → classified as directory. This is the correct conservative default for ambiguous paths.

**Dependencies:** None. Self-contained awk modification.

**Acceptance Criteria:**
- [ ] Run existing test suite: `bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` — all tests pass
- [ ] Manual test: create a temporary plan with a step containing `**Files:** Modify: src/Dockerfile, Create: src/.env` → verify scope contains them as file entries
- [ ] Paths ending with `/` are still classified as directories

**Effort:** S

**AID Role:** backend

## Testing Strategy

- **Security steps (1-3):** Manual curl verification with traversal payloads + TypeScript compilation check. No unit test framework exists for these Express routes (they use integration-style manual testing).
- **Docs step (4):** Grep verification.
- **Script step (5):** Existing test suite (`run-all-tests.sh`, 93 tests) must pass. Add a new test case to `test-plan-to-epic.sh` for extensionless file classification if the test fixture infrastructure supports it.

## Constraints

- No new npm dependencies.
- Security fixes must use existing `isValidPathComponent` / `isWithinDirectory` / `validateEvidencePath` helpers — no new utility code.
- API response shapes must not change (same JSON structure for success and error responses).
- Script changes must not break existing 93-test suite.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `isValidPathComponent` rejects valid EPIC IDs containing dots (e.g., `E-1.0`) | Low | Medium | Current EPIC ID format uses hyphens and underscores, no dots. If a future format adds dots, the regex must be updated. |
| Extensionless allowlist incomplete | Low | Low | Conservative default (treat unknown as directory) is safe — just less precise for FIRST AID parallel detection. Allowlist can be extended. |

## Success Criteria

1. Zero CWE-22 path traversal vulnerabilities in aid-server and aid-gui route handlers that use `epicId`, `runId`, or wildcard path params.
2. All 3 HIGH Curator findings (IMP-080, IMP-081, IMP-082) resolved.
3. IMP-078 cross-reference added.
4. IMP-079 extensionless heuristic fixed.
5. IMP-077 verified as already resolved (no action needed).
6. Existing test suite passes without regressions.

## Next Steps

After plan approval:
1. Run `/aid-plan-epic P021-path-traversal-curator-fixes.md` to generate EPICs + queue entries
2. Execute via `/aid-first-aid` or `/aid-run-epic`
