---
id: P026
type: plan
status: done
created: 2026-03-16
author: PM + AI
---

# Plan: Multi-Layer DONE State Defense

## Context

AID Orchestrator v2.7.0 introduced mechanically enforced FSM transitions with precondition checks. However, the DONE state has a gap: the `done-advance review → release` sub-phase is the only mechanical checkpoint, but the LLM can skip it entirely and go straight to `git commit` or `aid-release.sh`. This has caused Curator + Auditor agents to be skipped in at least 2 runs (v2.6.0 and v2.7.0 implementation).

**Root cause:** Bash can refuse to cooperate at transition boundaries, but if the LLM never calls the transition, there is no enforcement. The defense needs multiple independent checkpoints across the tool chain.

## Goal

Add 2 additional enforcement layers so that even if the LLM skips `done-advance`, either `aid-release.sh` or the git pre-commit hook will block the operation.

## Scope

**In scope:**
- `aid-release.sh` FSM state check (Layer 2)
- Git pre-commit hook on FSM branches (Layer 3)
- Hook installation via `/aid-init`
- Documentation updates

**Out of scope:**
- Post-run audit script (Layer 4 — deferred, independent)
- Claude Code hooks (per-user, not per-project)
- Changes to `aid-fsm.sh` (Layer 1 already complete)

## Approach

### Option A: Minimal (Script-only)

Add checks to `aid-release.sh` + standalone hook file, manual installation.

**Pros:** Smallest blast radius (2 files), no `/aid-init` changes.
**Cons:** Manual hook install = nobody does it.

### Option B: Integrated (Script + Init) — Recommended

Same checks + `/aid-init` auto-installs hook with marker-based append/upgrade.

**Pros:** Automatic for new projects, upgrade path for existing, single source of truth in `defaults/`.
**Cons:** Modifies `/aid-init`, must handle existing hooks.

### Option C: Integrated + Claude Code hook

Option B + Claude Code `hooks.preCommit` in settings.json.

**Pros:** Double protection.
**Cons:** Per-user config, not per-project. Adds Claude Code dependency.

### Decision

**Chosen:** Option B
**Rationale:** Automatic installation is critical — a defense that requires manual setup is no defense. Marker-based append safely coexists with existing hooks.

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | `aid-release.sh` FSM check | Add soft `done_phase` check at start of release script | S |
| 2 | Pre-commit hook template | Create `defaults/hooks/pre-commit` with branch-filtered FSM guard | S |
| 3 | `/aid-init` hook install | Add hook installation step with marker-based append/upgrade | S |
| 4 | Documentation | Update `aid-run.md`, `pipeline.md`, CHANGELOG | S |

## Design Details

### Layer 2: `aid-release.sh` FSM Check

Insert after bump type validation, before version read:

```bash
STATE_FILE=$(find .aid-o/work/runs/ -name "state.yaml" 2>/dev/null | head -1)
if [[ -n "$STATE_FILE" ]]; then
  DONE_PHASE=$(grep '^done_phase:' "$STATE_FILE" | awk '{print $2}')
  FSM_STATE=$(grep '^state:' "$STATE_FILE" | awk '{print $2}')
  if [[ "$FSM_STATE" == "DONE" && "$DONE_PHASE" != "release" ]]; then
    echo "ERROR: FSM state is DONE but done_phase=${DONE_PHASE:-<not set>}." >&2
    echo "Run Curator + Auditor first, then: aid-fsm.sh done-advance review release" >&2
    exit 1
  fi
fi
```

**Behavior:** Soft check — if no `state.yaml` exists, release proceeds (manual workflow).

### Layer 3: Git Pre-Commit Hook

Branch-filtered: only activates on `task/*` and `epic/*` branches.

```bash
#!/usr/bin/env bash
# AID-ORCHESTRATOR-HOOK-START (do not edit this block manually)
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
case "$BRANCH" in
  task/*|epic/*) ;;
  *) exit 0 ;;
esac
STATE_FILE=$(find .aid-o/work/runs/ -name "state.yaml" 2>/dev/null | head -1)
[[ -z "$STATE_FILE" ]] && exit 0
FSM_STATE=$(grep '^state:' "$STATE_FILE" | awk '{print $2}')
DONE_PHASE=$(grep '^done_phase:' "$STATE_FILE" | awk '{print $2}')
if [[ "$FSM_STATE" == "DONE" && "$DONE_PHASE" != "release" ]]; then
  echo "AID HOOK: Commit blocked — FSM is in DONE/${DONE_PHASE:-review}." >&2
  echo "Run Curator + Auditor, then: aid-fsm.sh done-advance review release" >&2
  exit 1
fi
if [[ "$FSM_STATE" == "READY" ]]; then
  echo "AID HOOK: Commit blocked — FSM is in READY (not yet executing)." >&2
  exit 1
fi
# AID-ORCHESTRATOR-HOOK-END
exit 0
```

### `/aid-init` Hook Installation

Logic:
1. Check if `.git/hooks/pre-commit` exists
2. If exists — search for `AID-ORCHESTRATOR-HOOK-START` marker
   - Found → replace block between START/END (upgrade)
   - Not found → append AID block (coexistence)
3. If not exists → copy template, `chmod +x`

Runs as last step after `.aid-o/` structure creation.

## Constraints

- Hook must not interfere with non-FSM commits (branch filter)
- Hook must not break if `.aid-o/` directory is missing
- `aid-release.sh` must work without FSM (manual releases)
- No changes to `aid-fsm.sh` (Layer 1 is complete)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Existing pre-commit hook overwritten | M | H | Marker-based append, never overwrite |
| Hook blocks legitimate non-FSM commit | L | M | Branch pattern filter + soft state.yaml check |
| `aid-release.sh` bypassed via manual `git tag` | M | L | Acceptable — audit trail catches it |

## Success Criteria

- `aid-release.sh` exits 1 when `done_phase != release` and `state.yaml` exists
- Pre-commit hook blocks commit on `task/*` branch when in DONE/review
- Pre-commit hook passes on `main` branch regardless of FSM state
- `/aid-init` installs hook without destroying existing hooks
- `/aid-init` upgrade replaces AID block, preserves user hooks

## Next Steps

- [ ] Implement steps 1-4
- [ ] Test all 3 layers independently
- [ ] Run `/aid-init` in test project to verify hook installation

---

**Last Updated:** 2026-03-16
