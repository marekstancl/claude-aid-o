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
#   2026-09-18  the plan must have a closed plan-review round        (P093 S7)
#
# Every one of those was a correct precondition and a correct refusal. The
# defect was never the rule — it was that fifteen fixtures each carried their
# own private idea of "a plan is now ready to generate from".
#
# So there is one idea, here. The next precondition is one edit in this file.
#
# WHAT IT DELIBERATELY DOES **NOT** DO: switch anything off. There is no seam
# that disables the gate for tests. A fixture that satisfies the real
# precondition proves the real path still works; a fixture that skips it proves
# only that skipping works, and would have hidden all three breakages above
# rather than reporting them.
#
# Usage (bats via test-helpers.bash, or a flat .sh harness that sources it):
#   aid_fixture_seed_plan <project_root> <plan_source> [plan_basename]
#   aid_fixture_seed_plan_review <project_root> <plan>   (the round alone, for a
#     suite that places its plan itself)
#   aid_fixture_seed_plan_decided <project_root> <plan_id>   (a plan whose close
#     has been decided ready: what plan-merge-to-main and plan-close read)
#   aid_fixture_seed_critic_check <project_root> <plan> [<plan_sha>]   (P109: the
#     passed critic check a plan needs before its review round and at the gate)
#   aid_fixture_write_brief <project_root> <plan>   (P109: the brief a strict plan
#     must name, generated from the plan's OWN criteria; aid_fixture_seed_plan
#     calls it for every lifecycle_strict plan that names none)
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

  # ── 2b. P109 Step 2 (2026-10-09): a lifecycle_strict plan names its brief, or
  #        the lint refuses it. Generated from the plan's own criteria.
  if grep -qE '^lifecycle_strict:[[:space:]]*true' "$plan" && ! grep -qE '^zadani:' "$plan"; then
    aid_fixture_write_brief "$root" "$plan" >/dev/null || return 1
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
      local brief="${plan%/*}/$(basename "$name" | sed -E 's/^(P[0-9]+).*/\1/')-zadani.md"
      [[ -f "$brief" ]] && git -C "$root" add -- "$brief" >/dev/null 2>&1
      if ! git -C "$root" diff --cached --quiet -- "$plan" "$brief" 2>/dev/null; then
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

  # ── 5. P093 Step 7 (2026-09-18): the CP1 gate needs a closed plan-review round
  #       (and since P109 Step 3, a passed critic check — seeded inside it).
  aid_fixture_seed_plan_review "$root" "$plan" || return 1

  printf '%s\n' "$plan"
}

# aid_fixture_seed_critic_check <project_root> <plan> [<plan_sha>]
#
# A passed plan-moment critic check for <plan> (or for <plan_sha> when given):
# critic.md with its two levels and one item, the author's response answering
# it, and check.json in the shape aid_critic_check writes — what
# aid_critic_verdict reads. Running the real critic is a model call; its shape
# check has its own suite (test-critic.bats).
aid_fixture_seed_critic_check() {
  local root="${1:?aid_fixture_seed_critic_check: project root required}"
  local plan="${2:?aid_fixture_seed_critic_check: plan required}" sha="${3:-}" id dir
  id="$(awk -F': *' 'NR > 1 && /^---$/ {exit} /^id:/ {gsub(/["\x27]/, "", $2); print $2; exit}' "$plan")"
  [[ -n "$id" ]] || { echo "aid_fixture_seed_critic_check: ${plan} has no frontmatter id" >&2; return 2; }
  [[ -n "$sha" ]] || sha="$(sha256sum "$plan" | cut -d' ' -f1)"
  dir="$root/.aid-o/work/evidence/${id}/critic/plan"
  mkdir -p "$dir"
  printf '### Úroveň 1\n\n**1. fixture: one item.** It holds.\n\n### Úroveň 2\n\nnic\n' > "$dir/critic.md"
  printf '| # | výtka | verdikt | kde |\n|---|---|---|---|\n| 1 | fixture item | PŘIJATO | `plan.md` checked |\n' > "$dir/critic-response.md"
  jq -n --arg p "$sha" --arg r "$(sha256sum "$dir/critic-response.md" | cut -d' ' -f1)" \
        --arg a "$(sha256sum "$dir/critic.md" | cut -d' ' -f1)" \
    '{moment:"plan", plan_sha256:$p, answer_sha256:$a, response_sha256:$r, level1_items:1, response_rows:1, passed:true, reason:""}' > "$dir/check.json"
}

# aid_fixture_write_brief <project_root> <plan>
#
# The brief a lifecycle_strict plan must name (P109 Step 2), built FROM THE
# PLAN'S OWN criteria so the plan carries it verbatim by construction:
#   - the points are the plan's leading run AC1..ACk of criteria with a block
#     under ## Acceptance Criteria; a plan with no AC1 at all gets one fixture
#     point appended (a section of its own, the parser reads every such section)
#   - sections 1-5 hold one fixture sentence each, the stakes paragraph included
#   - every step without **Zavírá:** gets one naming every point, at its end
#   - ## Architecture / ## Data Model / ## API Design get **Odvozeno z:** AC1
#   - the plan's frontmatter gains zadani:, zadani_verze: 1, zadani_sha256:
# Echoes the brief's path. Refuses a plan whose AC1 has no block: the author of
# that fixture decides what the point is, not this helper.
aid_fixture_write_brief() {
  local root="${1:?aid_fixture_write_brief: project root required}"
  local plan="${2:?aid_fixture_write_brief: plan required}"
  local plugin="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  local id brief rec label n=0 points="" ids="" sha tmp
  id="$(awk -F': *' 'NR > 1 && /^---$/ {exit} /^id:/ {gsub(/["\x27]/, "", $2); print $2; exit}' "$plan")"
  [[ "$id" =~ ^P[0-9]+$ ]] || { echo "aid_fixture_write_brief: ${plan} has no frontmatter id P<n>" >&2; return 2; }
  brief="$root/.aid-o/plans/${id}-zadani.md"
  mkdir -p "$root/.aid-o/plans"
  # shellcheck source=/dev/null
  source "$plugin/scripts/lib/aid-verification-pattern.sh"
  # shellcheck source=/dev/null
  source "$plugin/scripts/lib/aid-scoping.sh"
  while IFS= read -r rec; do
    label="${rec%%$'\x1f'*}"
    [[ "$label" == "AC$((n + 1))" ]] || break
    [[ "$(cut -d$'\x1f' -f3 <<< "$rec")" != no_verification ]] || {
      [[ "$n" -eq 0 ]] && { echo "aid_fixture_write_brief: ${plan}: AC1 has no verification_pattern block — give it one" >&2; return 2; }
      break; }
    n=$((n + 1))
  done < <(_aid_vp_parse_ac "$plan" "Acceptance Criteria")
  if [[ "$n" -eq 0 ]]; then
    # before the first `## ` section, so a caller appending to the plan's last
    # step after this still appends to that step
    tmp="$(mktemp)"
    awk 'BEGIN { sec = "## Acceptance Criteria\n\n- [ ] AC1: the fixture plan does what its steps say\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: \"true\"\n    expected_exit: 0\n  ```\n" }
      !done && /^## / { print sec; done = 1 } { print } END { if (!done) printf "\n%s", sec }' "$plan" > "$tmp" && mv "$tmp" "$plan"
    n=1
  fi
  # the points: the plan's own lines and blocks, copied byte for byte
  points="$(awk -v k="$n" '
    /^## Acceptance Criteria/ { f = 1; next } /^## / { f = 0 }
    f && /^- / { keep = 0
      if ($0 ~ /^- \[[ x]\] AC[0-9]+:/) { lab = substr($0, 7); sub(/:.*/, "", lab); keep = (substr(lab, 3) + 0 <= k) } }
    f && keep' "$plan")"
  ids="$(seq -f 'AC%g' 1 "$n" | paste -sd, - | sed 's/,/, /g')"
  {
    printf -- '---\nzadani: %s\nverze: 1\ndatum: 2026-10-09\nautor: fixture\n---\n\n# %s - fixture brief\n\n' "$id" "$id"
    printf '## 1. Co PM chce\n\n> „the fixture plan, as written“\n\n**Co je v sázce:** nothing — a test fixture.\n\n'
    printf '## 2. Změřený výchozí stav\n\n- a fixture project\n\n## 3. Co udělat\n\n**(1)** what the plan says.\n\n'
    printf '## 4. Kde co je\n\n| Co | Kde |\n|---|---|\n| the plan | `%s` |\n\n## 5. Pravidla práce\n\n- none beyond the plugin'"'"'s\n\n' "${plan##*/}"
    printf '## 6. Hotovo, když\n\n%s\n' "$points"
  } > "$brief"
  # every step closes the points; design sections name them
  tmp="$(mktemp)"
  # **Zavírá:** goes right after **AID Role:** (a one-line field), or at the
  # step's end when the step has no role line
  awk -v ids="$ids" '
    function close_step() { if (instep && !has) print "\n**Zavírá:** " ids "\n"; instep = 0; has = 0 }
    /^```/ { fence = !fence }
    !fence && /^### Step / { close_step(); instep = 1 }
    !fence && /^## / { close_step()
      if ($0 ~ /^## (Architecture|Data Model|API Design)([^[:alnum:]]|$)/) { print; print ""; print "**Odvozeno z:** AC1"; skipodv = 1; next } }
    skipodv && /^\*\*Odvozeno z:\*\*/ { skipodv = 0; next }
    skipodv && NF { skipodv = 0 }
    instep && /^\*\*Zavírá:\*\*/ { has = 1 }
    instep && !has && /^\*\*AID Role:?\*\*/ { print; print ""; print "**Zavírá:** " ids; has = 1; next }
    { print }
    END { close_step() }' "$plan" > "$tmp"
  sha="$(sha256sum "$brief" | cut -d' ' -f1)"
  awk -v z=".aid-o/plans/${id}-zadani.md" -v s="$sha" '
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" { print "zadani: " z; print "zadani_verze: 1"; print "zadani_sha256: " s; fm = 0 }
    fm && /^zadani(_verze|_sha256)?:/ { next }
    { print }' "$tmp" > "$plan"
  rm -f "$tmp"
  printf '%s\n' "$brief"
}

# aid_fixture_seed_plan_review <project_root> <plan>
#
# One plan-review round that found nothing, produced by the REAL round script
# (plan check, prepare, six empty answers, collect, close) and PROVEN by the real
# gate, which must then pass. Convergent like the rest of this file: edit the
# plan afterwards and the gate refuses it again, exactly as in production.
aid_fixture_seed_plan_review() {
  local root="${1:?aid_fixture_seed_plan_review: project root required}"
  local plan="${2:?aid_fixture_seed_plan_review: plan required}"
  local plugin="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  local round_sh="$plugin/scripts/aid-review-round.sh" id dir role
  id="$(awk -F': *' 'NR > 1 && /^---$/ {exit} /^id:/ {gsub(/["\x27]/, "", $2); print $2; exit}' "$plan")"
  [[ -n "$id" ]] || { echo "aid_fixture_seed_plan_review: ${plan} has no frontmatter id" >&2; return 2; }
  dir="$root/.aid-o/work/evidence/${id}/cp1"
  # A re-seed replaces the fixture's own earlier round; nothing else lives here.
  rm -rf "$dir"
  # P109 Step 3: no round is prepared without a passed critic check.
  aid_fixture_seed_critic_check "$root" "$plan" || return 1
  bash "$plugin/scripts/aid-plan-check.sh" "$plan" --project-root "$root" \
    --json "$root/.aid-o/work/evidence/${id}/plan-check.json" --quiet >/dev/null 2>&1 || true
  bash "$round_sh" prepare --plan "$plan" --round 1 --project-root "$root" >/dev/null 2>&1 || {
    echo "aid_fixture_seed_plan_review: prepare failed for ${plan}" >&2; return 1; }
  for role in $(jq -r '.reviewers_expected[]' "$dir/round-1/round.json"); do
    jq -n --arg r "$role" '{role: $r, findings: [], no_findings_reason: "fixture: nothing to review"}' \
      > "$dir/round-1/reviewer-${role}.json"
  done
  bash "$round_sh" collect --plan "$plan" --round 1 --project-root "$root" >/dev/null 2>&1 \
    && bash "$round_sh" close --plan "$plan" --round 1 --project-root "$root" \
         --tokens $(jq -r '.reviewers_expected[] | "\(.)=unknown"' "$dir/round-1/round.json") >/dev/null 2>&1 || {
    echo "aid_fixture_seed_plan_review: collect/close failed for ${plan}" >&2; return 1; }
  bash "$plugin/scripts/aid-cp1-gate.sh" --plan "$plan" --project-root "$root" >/dev/null 2>&1 || {
    echo "aid_fixture_seed_plan_review: the seeded round does not pass aid-cp1-gate.sh — the fixture is not generation-ready" >&2
    return 1; }
}

# aid_fixture_seed_plan_decided <project_root> <plan_id>
#
# Leaves a FROZEN plan in the state `plan-finalize --stage decide` leaves it in
# when the answer is yes, without paying for the gates and the round: the
# version-2 inventory as REAL files with their REAL sha256, the receipt sealed
# by the production sealer, and the manifest pointers. The stages themselves are
# covered end to end by test-plan-final-decide.bats; the merge and close suites
# start from here. The caller has sourced lib/aid-plan-manifest.sh (it froze the
# plan through it) and exported AID_PLAN_MANIFEST_PROJECT_ROOT.
aid_fixture_seed_plan_decided() {
  local root="${1:?aid_fixture_seed_plan_decided: project root required}" plan_id="${2:?plan id required}"
  local plugin="${AID_PLUGIN_PATH:?AID_PLUGIN_PATH must name the plugin}" m f outputs='{}'
  m="${root}/.aid-o/work/plan-state/${plan_id}/plan-boundary-manifest.json"
  local cand run_id base thead frozen_at dir
  cand="$(jq -r '.plan_boundary_manifest.candidate_sha' "$m")"; run_id="$(jq -r '.plan_boundary_manifest.plan_final_run_id' "$m")"
  base="$(jq -r '.plan_boundary_manifest.plan_base_commit' "$m")"; thead="$(jq -r '.plan_boundary_manifest.target_branch_head_at_candidate_freeze' "$m")"
  frozen_at="$(jq -r '.plan_boundary_manifest.candidate_frozen_at' "$m")"
  dir="${root}/$(jq -r '.plan_boundary_manifest.plan_final_evidence_dir' "$m")"
  [[ "$cand" =~ ^[0-9a-f]{40}$ ]] || { echo "aid_fixture_seed_plan_decided: ${plan_id} has no frozen candidate" >&2; return 2; }
  mkdir -p "$dir/cp7"

  jq -n '{overall: "pass", gates: []}' > "${dir}/gates_report.json"
  jq -n --arg h "$cand" '{verdict: "pass", head_sha: $h, rounds: []}' > "${dir}/cp7/rounds.json"
  jq -n --arg b "$base" --arg h "$cand" \
    '{base_commit: $b, head_commit: $h, overall_verdict: "pass", results: [], summary: {present_count: 0, absent_count: 0}}' > "${dir}/plan-diff.json"
  jq -n --arg c "$cand" '{schema_version: "aid-2.0", artifact_type: "release_decision",
    release_decision: {release_ready: true, blockers: [], candidate_sha: $c}}' > "${dir}/release-decision.json"
  # The inventory is read from the production list, so a change there is one edit.
  while IFS= read -r f; do
    [[ -f "${dir}/${f}" ]] || jq -n --arg h "$cand" '{schema_version: "aid-2.0", revision: {head_sha: $h}}' > "${dir}/${f}"
    outputs="$(jq -c --arg k "$f" --arg v "sha256:$(sha256sum "${dir}/${f}" | cut -d' ' -f1)" '. + {($k): $v}' <<< "$outputs")"
  done < <(bash -c 'source "$1"; _pfsm_review_required_outputs' _ "${plugin}/scripts/aid-plan-fsm.sh")

  local sealed ref receipt_hash
  sealed="$(bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "$8" "$9"' _ "${plugin}/scripts/aid-plan-fsm.sh" \
    "$root" "$plan_id" "$base" "$cand" "$(git -C "$root" rev-parse main)" "$frozen_at" "$run_id" "$outputs")" || return 1
  IFS='|' read -r ref _ receipt_hash <<< "$sealed"
  [[ -n "$ref" && -n "$receipt_hash" ]] || { echo "aid_fixture_seed_plan_decided: the receipt was not sealed" >&2; return 1; }

  plan_manifest_update "$plan_id" "
      .plan_boundary_manifest.plan_final_inputs = {plan_diff_sha256: \"sha256:$(sha256sum "${dir}/plan-diff.json" | cut -d' ' -f1)\", candidate_sha: \"${cand}\", run_id: \"${run_id}\", plan_diff_verdict: \"present\"}
    | .plan_boundary_manifest.plan_final_review = {candidate_sha: \"${cand}\", review_range: \"${base}..${cand}\", run_id: \"${run_id}\", outputs: ${outputs}}
    | .plan_boundary_manifest.plan_final_evidence_ref = \"${ref}\"
    | .plan_boundary_manifest.plan_final_evidence_receipt_sha256 = \"${receipt_hash}\"
    | .plan_boundary_manifest.plan_final_c4 = {run_id: \"${run_id}\", candidate_sha: \"${cand}\", target_head_sha: \"${thead}\", enforcement: \"blocking\", release_ready: true, blockers: 0}" >/dev/null
}
