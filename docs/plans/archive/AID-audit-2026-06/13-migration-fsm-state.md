---
audit: P041
artifact: FSM-state filename migration (state.yaml → fsm-state.yaml) — design + batches
status: Batch A proposed for external review; B/C/D queued
generated: 2026-06-02
scope: unify the FSM state file to a single name (fsm-state.yaml) across the whole plugin
---

# Migration — one FSM state file name: `fsm-state.yaml`

## The real finding (corrects STATE.md "D1 = rename")
This is NOT two names for one file. It is **two different files** that got tangled by an
**incomplete P040 migration**:

| File | Written by | Content | Read by |
|------|------------|---------|---------|
| `fsm-state.yaml` | `aid-json-to-run.sh:630` → `aid-fsm.sh init` | FSM control state (state, current_step, branch, base_commit, mode, created_at…) | the whole pipeline |
| `state.yaml` | `aid-epic-to-json.sh:808` | step-progress array `[{id,status:pending,…}]` (vestige of legacy `plan_progress.json`) | **nobody at runtime** — only its own test |

P040 renamed the FSM file `state.yaml`→`fsm-state.yaml` only at the **producer**
(`aid-json-to-run.sh`). ~half the consumers (auditor, gate runner, compliance backfill,
epic-summary, diagnostic, release, pipeline.md, crash-recovery, aid-run/status/help docs) still
address the FSM file by its **old name `state.yaml`**. Meanwhile `aid-epic-to-json.sh` reused the
freed name `state.yaml` for the now-dead step-array.

**Latent trap:** `aid-fsm.sh:278` fallback ("if no `fsm-state.yaml`, read `state.yaml`") would read
the dead step-array as if it were FSM state (wrong schema). Never fires in the normal chain
(json-to-run always writes fsm-state.yaml), but it is a mine.

## Target state
Exactly **one** FSM file, named `fsm-state.yaml`, everywhere. The dead step-array `state.yaml` is
retired. **One** legacy fallback kept for in-flight/old runs (the single compat point).

## Batches (each reviewed + applied separately)

### Batch A — retire the dead `state.yaml` (step-array)  ← THIS PROPOSAL
Stop `aid-epic-to-json.sh` writing it; remove the `progress` manifest field (no consumer); fix its
test. Pure behavioral change, self-contained.

### Batch B — functional FSM-file refs in SCRIPTS (NARROWED after investigation)
Only **2 functional** spots actually pick the FSM file by the old name and need fixing:
- `aid-release.sh:95` — Layer-2 FSM guard searches legacy `work/runs/` for `state.yaml` only.
- `aid-diagnostic.sh:54` — `has_state` existence check points at `state.yaml` (new runs have none).

Everything else in scripts STAYS untouched (verified):
- `aid-fsm.sh:276-278` fallback → the single legacy bridge.
- `aid-fsm.sh:1481-1492` `read_steps_array()` → reads `fsm-state.yaml.steps` first, legacy `state.yaml`
  sibling as fallback for old runs. Correct as-is.
- `aid-compliance-backfill.sh` → one-shot LEGACY tool that operates on pre-Session-A `state.yaml`
  files by design; renaming would break its purpose. Leave entirely.
- `aid-run-gates.sh` → reads the caller-passed `--state-file` (= FSM file path); no hardcoded
  `state.yaml`. Only its comment (168-169) is stale → Batch C.
- All other `.sh` `state.yaml` mentions are stale COMMENTS → Batch C.

### Batch C — text sweep, classified by SEMANTIC PATTERN (rev. 3 after 2 review rounds)
Two review rounds kept finding "twin" instances of the same error in different files, because the
plan classified by FILE. Rev. 3 classifies by PATTERN so twins cannot hide; known instances listed.

**RULE 2 (DELETE the mention — file is dead):** ANY text that lists `state.yaml` as an OUTPUT /
  PRODUCT of `aid-epic-to-json.sh` — the "EPIC → plan.json + state.yaml" generation pattern. Batch A
  retired that file, so the mention is deleted (NOT renamed — epic-to-json writes no state file).
  Known instances:
    - pipeline.md:129
    - planner.md:33 (the "Writes:" bullet — delete WHOLE bullet) + planner.md:226
    - aid-auto-pipeline.sh:18  ← rev3 FAIL 1 (twin of pipeline.md:129)
    - scripts/README.md:78 (legend) + :64 (ASCII box — remove state.yaml from the arrow-2 column,
      same treatment as :78)  ← rev3 FAIL 2 (twin: box + its own legend)
    - scripts/README.md:183, 192, 203 (manifest `progress` key — keep JSON valid), 222 (numbered
      step 9 — renumber 10→9, 11→10), 230

**RULE 1 (RENAME → fsm-state.yaml):** `state.yaml` meaning the LIVE FSM run-state file — read/write
  instructions, field refs (`.branch`/`.created_at`/`.state`/`.done_phase`), runtime messages,
  run-dir tree listings. Known instances:
    commands/: aid-status.md, aid-plan.md, aid-init.md, aid-help.md, aid-run.md
    skills/:   memory.md, pipeline.md (FSM-file mentions ONLY — NOT the auto-mode-state.yaml lines),
               run-management.md
    agents/:   auditor.md, project-scanner.md
    defaults/: orchestration.yaml:46, templates/verifier-output-template.md, step-verify-template.md
    defaults/hooks/pre-commit: ONLY the :9 comment ("targeted state.yaml lookup")
    scripts/README.md:657 (dir-tree — the run-dir file DOES exist, just renamed)
    .sh comments: aid-run-gates.sh (22,168,169), aid-epic-summary.sh (154 ONLY — NOT :31 fallback),
                  aid-plan-diff.sh (59), aid-diagnostic.sh (34 docstring)
    aid-fsm.sh: 85, 683, 1098, 1377, 1595, 1597 (malformed echo), 1194 (PRECONDITION FAIL echo),
                AND 2096 (`state.yaml.branch (set by Step 2 cmd_init)`)  ← rev3 FAIL 3 (regression)

**EXCEPTIONS — DO NOT TOUCH:**
  - **auto-mode-state.yaml** is a DIFFERENT file (autonomous mode flag). Substring "state.yaml"
    matches it. NEVER rewrite it. Affects pipeline.md:723,1033,1035,1039 + aid-stop.md + others.
  - aid-fsm.sh:276-278 fallback; 1480-1492 read_steps_array legacy sibling; 1302 historical.
  - plan-writing.md:~657-659 detector — keeps BOTH names intentionally.
  - pre-commit:12 + :22 — dual-search `\( -name state.yaml -o -name fsm-state.yaml \)`; keep BOTH.
  - aid-epic-summary.sh:31 + aid-diagnostic.sh:55 — legacy `state.yaml` fallbacks (A5/B2); keep.
  - aid-compliance-backfill.sh (all 11 refs incl. functional paths :102/:225) — legacy tool; leave.
  - CHANGELOG.md (22 refs) — history. scripts/tests/** — Batch D.

**EXECUTION cautions (apply-time, not classification):**
  - DELETE = remove whole bullet/line, never a dangling token ("generates plan.json and ").
  - README:203 delete keeps surrounding JSON valid (commas). README:222 renumber the list.
  - Only FSM-file `state.yaml` substrings change — never `auto-mode-state.yaml`.

### Batch D — tests
`test-aid-fsm.bats` (~50), `test-json-to-run.sh`, `test-run-gates.sh`, `test-fsm.sh`,
`test-integration-phase1.sh`, bats helpers. Run full suite before+after to isolate from the 19
pre-existing failures.

## Never touch
**CHANGELOG.md (22 refs)** — historical release records; rewriting them falsifies history.

## Safety
- The `aid-fsm.sh:278` legacy fallback stays → old in-flight runs still resume.
- Full test suite before + after each code batch.
- Batch-by-batch external review before apply.

---

# BATCH A — verifiable proposal

**Goal:** stop producing the dead `state.yaml` (step-array) and remove its only references inside
the producer + its test. Nobody reads the file or the manifest `progress` field at runtime
(verified: only the script header, README, and the script's own test mention it).

### Change A1 — `scripts/aid-epic-to-json.sh:805-809` — delete the write (Step 17)
BEFORE:
```bash
# =============================================================================
# Step 17: Generate state.yaml
# =============================================================================
progress_json="$(echo "$steps_json" | jq '[.[] | {id: .id, status: "pending", started_at: null, completed_at: null, agent_id: null, result: null}]')"
progress_path="${evidence_dir}/state.yaml"
echo "$progress_json" > "$progress_path" || error_exit "Cannot write state.yaml to $progress_path" 3
```
AFTER: (block removed entirely)

### Change A2 — `scripts/aid-epic-to-json.sh:819-829` — drop `progress` from manifest (Step 19)
BEFORE:
```bash
jq -n \
  --arg plan_json "$plan_json_path" \
  --arg progress "$progress_path" \
  --arg run_id "$run_id" \
  --arg evidence_dir "$evidence_dir" \
  '{
    plan_json: $plan_json,
    progress: $progress,
    run_id: $run_id,
    evidence_dir: $evidence_dir
  }'
```
AFTER:
```bash
jq -n \
  --arg plan_json "$plan_json_path" \
  --arg run_id "$run_id" \
  --arg evidence_dir "$evidence_dir" \
  '{
    plan_json: $plan_json,
    run_id: $run_id,
    evidence_dir: $evidence_dir
  }'
```

### Change A3 — `scripts/aid-epic-to-json.sh` header comments (lines 3, 12, 14)
- L3: `# aid-epic-to-json.sh — Convert an EPIC.md into plan.json + state.yaml`
      → `# aid-epic-to-json.sh — Convert an EPIC.md into plan.json`
- L11-12: `…builds a plan.json conforming to plan.schema.json, creates\n# state.yaml and an evidence directory.`
      → `…builds a plan.json conforming to plan.schema.json, creates\n# an evidence directory.`
- L14: `# stdout: JSON manifest { plan_json, progress, run_id, evidence_dir }`
      → `# stdout: JSON manifest { plan_json, run_id, evidence_dir }`

### Change A4 — `scripts/tests/test-epic-to-json.sh` — fix TEST 3, TEST 9, delete TEST 6
- TEST 3: drop the `progress_path` extraction + its `! -f` missing-check + the `state.yaml`
  word in the test title; keep the plan.json assertions. Remove the `PROGRESS_PATH=` storage line.
- TEST 6 ("state.yaml initializes all steps with status: pending"): **delete the whole test block**
  (it asserts a file that no longer exists).
- **TEST 9 (line 275 + 291)**: remove the `.progress` assertion (line 291
  `jq -e '.progress'`) and the word `progress` from the test title (line 275). Without this,
  TEST 9 fails because A2 removed the `progress` manifest key. *(External review FAIL #1 — fixed.)*

### Change A5 — `scripts/aid-epic-summary.sh:30-31` — repoint to `fsm-state.yaml` (pulled forward)
**Why in Batch A, not B:** this script `die`s on a missing `state.yaml` and reads ONLY FSM fields
from it (`epic_id`, `run_id`, `base_commit`, `total_steps`, `gate_retries`) — none of which exist
in the dead step-array. It is therefore reading the WRONG file today (every real `epic-summary.md`
has a degraded `# unknown done` header). Removing the dead file (A1) would make it `die` →
`|| log_warn` at `aid-fsm.sh:2110` → no summary at all. Repointing it now turns a regression into a
net improvement (real `epic_id` instead of "unknown"). *(External review side-effect note — fixed.)*

BEFORE:
```bash
local state_file="${evidence_dir}/state.yaml"
[[ -f "$state_file" ]] || die "state.yaml not found: $state_file"
```
AFTER (mirrors the `aid-fsm.sh:278` compat pattern so old runs still work):
```bash
local state_file="${evidence_dir}/fsm-state.yaml"
[[ ! -f "$state_file" && -f "${evidence_dir}/state.yaml" ]] && state_file="${evidence_dir}/state.yaml"
[[ -f "$state_file" ]] || die "fsm-state.yaml not found: $state_file"
```

## Out of scope for Batch A (handled later)
- `scripts/README.md` lines describing the dead file (183/192/203/222/230/657) → **Batch C** (docs).
  Between A and C, README briefly still mentions the old output; flagged, harmless.
- All OTHER FSM-file `state.yaml` references that mean the *real* FSM file → **Batch B/C**.
- The `aid-fsm.sh:278` fallback → **stays** (Batch B keeps it as the compat bridge).

## How to verify Batch A
1. `grep -n "state.yaml\|progress" scripts/aid-epic-to-json.sh` → only the (now absent) write is
   gone; no `progress_path`, no `progress:` manifest field, header clean.
2. Run `bash scripts/tests/test-epic-to-json.sh` → passes; no test references state.yaml; TEST 6 gone.
3. `grep -rn "\.progress\b" scripts/ commands/ skills/ agents/` (excluding the deleted test) →
   confirms nobody consumed the manifest field (so removal breaks no caller).
4. Dry-run the script on a sample EPIC → evidence dir contains `plan.json` + `epic_input.md`, and
   **no** `state.yaml`. Manifest stdout has `{plan_json, run_id, evidence_dir}` only.
5. Branch note for the verifier: this branch accumulates Wave-1+ P041 fixes — ignore unrelated prior
   changes; review only the Batch-A diff above.
