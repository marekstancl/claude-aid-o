#!/usr/bin/env bash
# =============================================================================
# aid-fixture-plan.sh — THE one place a fixture seeds a plan
#
# WHY THIS FILE EXISTS, and it is not a convenience. Three times in three weeks
# a FAIL-CLOSED precondition was added to EPIC generation, the fixtures of the
# suites on the merge path were updated, and the fixtures of the `aid-tier: t2`
# suites were not — because nothing runs those to the end, so the breakage
# surfaced in a nightly days later and was repaired fifteen files at a time:
#
#   2026-08-05  the source plan must be COMMITTED on the target branch (P073 S11)
#   2026-08-14  DoD gate resolution requires a real execution.yaml   (IMP-503)
#   2026-08-24  the plan must have a rendered PM page                (P086 S4)
#
# Every one of those was a correct precondition and a correct refusal. The
# defect was never the rule — it was that fifteen fixtures each carried their
# own private idea of "a plan is now ready to generate from".
#
# So there is one idea, here. A fourth precondition is one edit in this file.
#
# WHAT IT DELIBERATELY DOES **NOT** DO: switch anything off. There is no seam
# that disables the gate for tests. A fixture that satisfies the real
# precondition proves the real path still works; a fixture that skips it proves
# only that skipping works, and would have hidden all three breakages above
# rather than reporting them.
#
# Usage (bats via test-helpers.bash, or a flat .sh harness that sources it):
#   aid_fixture_seed_plan <project_root> <plan_source> [plan_basename]
#
# Sourced, never executed.
# =============================================================================
[[ -n "${_AID_FIXTURE_PLAN_SH_LOADED:-}" ]] && declare -F aid_fixture_seed_plan >/dev/null 2>&1 && return 0
_AID_FIXTURE_PLAN_SH_LOADED=1

# aid_fixture_seed_plan <project_root> <plan_source> [plan_basename]
#
# Leaves <project_root> in the state EPIC generation demands. Echoes the path of
# the seeded plan. Returns non-zero — loudly — when it cannot, because a fixture
# that half-seeds is a test that fails later for the wrong reason.
aid_fixture_seed_plan() {
  local root="${1:?aid_fixture_seed_plan: project root required}"
  local src="${2:?aid_fixture_seed_plan: source plan required}"
  local name="${3:-$(basename "$src")}"

  # LOUD, NOT ACCOMMODATING. A fixture that half-seeds is a test that fails
  # later for the wrong reason, and the wrong reason is what costs the hours.
  [[ -d "$root" ]] || { echo "aid_fixture_seed_plan: no project root at ${root}" >&2; return 2; }
  [[ -r "$src"  ]] || { echo "aid_fixture_seed_plan: no readable plan at ${src}" >&2; return 2; }
  [[ "$name" == */* ]] && { echo "aid_fixture_seed_plan: plan name must be a basename, got '${name}' — the plan lives in <root>/.aid-o/plans" >&2; return 2; }
  [[ "$name" =~ ^P[0-9]+ ]] || { echo "aid_fixture_seed_plan: '${name}' does not start with P<number> — the PM page's identity comes from that id, so an unnumbered plan would own an ambiguous page" >&2; return 2; }

  # THREE levels up: lib -> tests -> scripts -> the plugin root. The first cut
  # went two, so `$plugin/scripts/lib/...` resolved to `scripts/scripts/lib/...`,
  # nothing was found, and the page was never rendered — while the helper
  # returned 0. That is the "half-seeded fixture" this file exists to prevent,
  # and it is why the missing-library branches below REFUSE instead of skipping.
  local plugin="${AID_PLUGIN_PATH:-}"
  if [[ -z "$plugin" ]]; then
    plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
  fi

  # ── 1. IMP-503 (2026-08-14): a real execution.yaml, or DoD gate resolution
  #       refuses. An empty `gates:` mapping is a valid, deliberate outcome.
  mkdir -p "$root/.aid-o/config" "$root/.aid-o/plans" "$root/.aid-o/work/evidence"
  local exec_yaml="$root/.aid-o/config/execution.yaml"
  if [[ -e "$exec_yaml" && ! -f "$exec_yaml" ]]; then
    echo "aid_fixture_seed_plan: ${exec_yaml} exists but is not a regular file" >&2
    return 2
  fi
  [[ -f "$exec_yaml" ]] || printf 'gates: {}\n' > "$exec_yaml"

  # ── 2. The plan itself.
  local plan="$root/.aid-o/plans/$name"
  # RE-SEEDING IN PLACE is the documented way to make an edited plan valid again
  # (see the convergence note below), and then source and destination are the
  # same file — `cp` refuses that. Copy only when they genuinely differ.
  if [[ ! "$src" -ef "$plan" ]]; then
    cp -- "$src" "$plan" || return 2
  fi

  # ── 3. P073 Step 11 (2026-08-05): generation refuses a source plan that is
  #       not committed on the target branch — UNLESS the workspace deliberately
  #       does not track it. `.aid-o/` gitignored is the "unshared" shape the
  #       preflight's own message names, and committing there would fail. So the
  #       question asked is git's, not a guess: does this repo track that path?
  if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$root" check-ignore -q "$plan" 2>/dev/null; then
      # A commit is required, so the branch must be one. On a detached HEAD the
      # commit would land nowhere a target branch can see.
      git -C "$root" symbolic-ref -q HEAD >/dev/null || {
        echo "aid_fixture_seed_plan: ${root} is on a detached HEAD and its .aid-o is tracked — generation needs the plan committed on a branch" >&2
        return 1
      }
      git -C "$root" add -- "$plan" >/dev/null 2>&1 || true
      if ! git -C "$root" diff --cached --quiet -- "$plan" 2>/dev/null; then
        git -C "$root" commit -q -m "fixture: the source plan, committed (generation refuses an uncommitted one)" \
          >/dev/null 2>&1 || {
            echo "aid_fixture_seed_plan: could not commit ${plan} — generation will refuse it" >&2
            return 1
          }
      fi
    fi
  fi

  # ── 4. P086 Step 4 (2026-08-24): the PM page. Rendered with the REAL renderer,
  #       because a fixture that fakes the page proves nothing about the path
  #       that produces it.
  #
  #       The obligation itself skips a plan the renderer REFUSES (no `## Goal`,
  #       say) — `aid_plan_summary_renderable` decides, and a plan it rejects
  #       owes no page. This mirrors that branch exactly rather than second-
  #       guessing it, so a fixture built on a minimal plan keeps working and the
  #       gate keeps agreeing with itself.
  local summary_lib="$plugin/scripts/lib/aid-plan-summary.sh"
  local obligation_lib="$plugin/scripts/lib/aid-artifact-obligation.sh"
  # LOUD, not accommodating: a plugin root that holds neither library is a
  # mis-resolved path, not a plugin without a renderer.
  if [[ ! -f "$summary_lib" || ! -f "$obligation_lib" ]]; then
    echo "aid_fixture_seed_plan: no renderer/obligation library under '${plugin}' — AID_PLUGIN_PATH is wrong, and seeding cannot be verified" >&2
    return 2
  fi
  local plan_id; plan_id="$(basename "$name")"; plan_id="${plan_id%%[-.]*}"
  local page="$root/.aid-o/work/evidence/${plan_id}/plan-summary-artifact.html"
  if true; then
    mkdir -p "$(dirname "$page")"
    local rrc=0
    (
      # shellcheck source=/dev/null
      source "$summary_lib" 2>/dev/null || exit 9
      declare -F aid_plan_summary_renderable >/dev/null 2>&1 || exit 9
      # The obligation itself skips a plan the renderer REFUSES — such a plan
      # owes no page. This mirrors that branch rather than second-guessing it,
      # so the fixture and the gate cannot disagree about what is owed.
      aid_plan_summary_renderable "$plan" 2>/dev/null || exit 3
      aid_plan_summary_render "$plan" "$page" >/dev/null 2>&1
    ) || rrc=$?
    case "$rrc" in
      0) ;;
      3) echo "aid_fixture_seed_plan: the renderer declined ${name}; no page seeded because no page is owed" >&2 ;;
      9) echo "aid_fixture_seed_plan: ${summary_lib} has no renderer entry points — the page cannot be seeded and the fixture is not generation-ready" >&2; return 1 ;;
      *) echo "aid_fixture_seed_plan: rendering ${name}'s PM page failed (rc=${rrc})" >&2; return 1 ;;
    esac
  fi

  # CONVERGENT, NOT MTIME-SMART (cross-model review, 2026-08-26). The first cut
  # `touch`ed the page so it would out-date the plan — which is the fixture
  # cheating at the very check it exists to satisfy. The seeding is instead
  # PROVEN by the production obligation itself: 0 (page present and current) or
  # its documented 3 (no page owed) are the only acceptable outcomes.
  #
  # And it is convergent on purpose: seed, then edit the plan, and the fixture
  # is invalid — exactly as it is in production. A caller that edits re-seeds.
  if true; then
    local orc=0
    (
      cd "$root" || exit 2
      # shellcheck source=/dev/null
      source "$obligation_lib" 2>/dev/null || exit 8
      declare -F aid_artifact_obligation_check >/dev/null 2>&1 || exit 8
      aid_artifact_obligation_check "$plan" >/dev/null 2>&1
    ) || orc=$?
    # 8 is "the obligation could not be ASKED". The first cut turned that into
    # exit 0 — a half-seeded fixture reported as ready, which is the one outcome
    # this helper exists to make impossible (cross-model review, 2026-08-26).
    if [[ "$orc" -eq 8 ]]; then
      echo "aid_fixture_seed_plan: ${obligation_lib} could not be used to verify the seeding — refusing rather than assuming it worked" >&2
      return 1
    fi
    if [[ "$orc" -ne 0 && "$orc" -ne 3 ]]; then
      echo "aid_fixture_seed_plan: ${name} is seeded but generation would still refuse it (artifact obligation rc=${orc}) — the fixture is not generation-ready" >&2
      return 1
    fi
  fi

  printf '%s\n' "$plan"
}
