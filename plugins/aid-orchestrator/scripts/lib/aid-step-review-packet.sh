#!/usr/bin/env bash
# aid-step-review-packet.sh — what goes to a step, fast-mode or whole-plan reviewer
# (P094 Step 6). The plan reviewer's packet is lib/aid-plan-review-packet.sh;
# the two builders share the template, the answer contract and the adapter,
# and differ in what they put in the packet.
#
# aid_step_review_packet_build <root> <checkpoint> <round_dir> <step_check> <plan_json> <step> [<prev_round_dir>]
#   Writes <round_dir>/packet/{diff.patch, dod.md, files.json, step-check.json,
#   manifest.json} and, for a confirmation round, open-findings.json and
#   fix.patch (the diff from the previous round's head to HEAD).
# aid_final_review_inputs_build <state_root> <run_dir> <plan_file> <plan_id>
#   What a whole-plan round (cp7) reads besides the diff, written once per
#   attempt by plan-finalize --stage produce into <run_dir>/cp7/: criteria.md
#   (the plan's acceptance and success criteria) and epic-findings.json (what
#   the step rounds of every run of the plan left open, `review: "steps"`; the
#   EPIC review, CP3, left in 3.0.0 and an old run's EPIC-review directory is
#   not read).
# aid_final_review_packet_build <root> <round_dir> <step_check> <run_dir> [<prev_round_dir>]
#   The cp7 packet: diff.patch, claims.patch (CHANGELOG, README and docs hunks),
#   dod.md (criteria.md), epic-findings.json, plan-diff.json, gates_report.json,
#   files.json, step-check.json, manifest.json, and the brief as zadani.md
#   (zadani-note.txt for a legacy plan) through aid_plan_review_brief_resolve. No plan.json is needed. A range
#   of more than 400 files also gets one diff-<EPIC>.patch per contributing
#   EPIC, named in the prompt; nothing is truncated.
# aid_step_review_prompt_render <role> <round> <round_dir> <checkpoint> <step>
#   Renders defaults/prompts/review-prompt-v1.md for one role of
#   skills/step-review-roles.md through aid-render-prompt.sh, then appends the
#   packet. The diff is appended, never passed as a variable: the renderer
#   refuses a value containing `{{`, and a diff may legitimately contain one.
# aid_step_review_route_open <root> <evidence_dir> <checkpoint> <step> <round_dir> <last>
#   After the last allowed round, routes or carries what stays open (P094
#   Step 7); returns 0 when nothing is open.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.

_AID_SR_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=aid-gate-row.sh
[[ -n "${AID_GATE_ROW_JQ:-}" ]] || source "${_AID_SR_PLUGIN}/scripts/lib/aid-gate-row.sh"   # P097 Step 2 — gate rows read through gate_row_normalize
# shellcheck source=aid-repo-roots.sh
source "${_AID_SR_PLUGIN}/scripts/lib/aid-repo-roots.sh"   # P112 — a foreign repository is reviewed in the plan's worktree
AID_SR_TEMPLATE="${_AID_SR_PLUGIN}/defaults/prompts/review-prompt-v1.md"
AID_SR_ROLES_SKILL="${_AID_SR_PLUGIN}/skills/step-review-roles.md"
# step_name(index) on a plan.json step: the plan's own number from its id
# (step_3_backend → "Step 3 (index 2)"), the index alone when the id has none —
# a reviewer reading "Step 2" would look for the plan's step 2.
_AID_SR_STEP_NAME_JQ='def step_name($i): ([(.id // "") | capture("^step_(?<n>[0-9]+)")] | .[0].n) as $n
  | if $n then "Step \($n) (index \($i))" else "Step \($i)" end;'
# The findings a step round still holds open: its verdict, the confirmation
# round's packet and the roles it asks read this (a form_invalid finding is open
# until answered, like a disputed one).
AID_SR_OPEN_JQ='(.status | IN("open", "disputed", "routed", "carried", "form_invalid")) and (.severity == "blocker" or .severity == "major")'
AID_SR_EVIDENCE_FORMS='`path:line` or `path:first-last` at the reviewed commit (in a whole-plan round also `zadani.md:line`, the brief in the packet), `<sha>:path:line` for a line of a file the diff deleted or moved (the pre-image at that commit), or `absent:path` for a file the step should have produced and did not; one citation that resolves is enough, but cite the exact line (a wrong number wastes the citation); citations only, separated by `;` — a word or a bracketed note after a line number drops the finding, so say what the line shows in `claim`'

aid_step_review_packet_build() {
  local root="$1" cp="$2" dir="$3/packet" sc="$4" plan_json="$5" step="${6:-}" prev="${7:-}"
  [[ -f "$sc" ]] || { echo "prepare: no step check at ${sc}" >&2; return 1; }
  mkdir -p "$dir" || return 1
  cp "$sc" "$dir/step-check.json" || return 1
  local range; range="$(jq -r .range "$sc")"
  if [[ "$range" == worktree ]]; then
    { git -C "$root" diff HEAD; for f in $(git -C "$root" ls-files --others --exclude-standard); do git -C "$root" diff --no-index /dev/null "$f" 2>/dev/null || true; done; } > "$dir/diff.patch"
  else
    git -C "$root" diff "$range" > "$dir/diff.patch" || return 1
  fi
  # The DoD: the step's objective and criteria (cp2), or the task text the
  # step check recorded (cp6).
  if [[ "$cp" == cp6 ]]; then
    { echo "# Task"; echo; jq -r '.dod // "(no task text recorded)"' "$sc"; } > "$dir/dod.md"
    echo '{"outputs": [], "allowed_paths": [], "forbidden_paths": [], "scope_declared": false}' > "$dir/files.json"
  else
    [[ -f "$plan_json" ]] || { echo "prepare: no plan.json at ${plan_json}" >&2; return 1; }
    if [[ "$cp" == cp2 ]]; then
      jq -r --argjson s "$step" "${_AID_SR_STEP_NAME_JQ}"' .steps[$s] | "# \(step_name($s)): \(.objective // "")\n\n## Acceptance criteria\n" + ((.acceptance_criteria // []) | map("- " + .) | join("\n"))' "$plan_json" > "$dir/dod.md"
      # "(tier: tN)" in an output is what the plan declared when it was written;
      # the suite's header is the tier, and step-check.json reports that (P103).
      jq --argjson s "$step" 'def notier: map(gsub(" ?\\(tier: t[0-9]\\)"; "")); .steps[$s] | {outputs: ((.outputs // []) | notier), allowed_paths: (.allowed_paths // []), forbidden_paths: (.forbidden_paths // []), scope_declared: true}' "$plan_json" > "$dir/files.json"
      # the step's measured criteria (P110), when prepare measured it
      local measured; measured="$(dirname "$plan_json")/cp2/step-${step}/plan-diff.json"
      [[ -f "$measured" ]] && cp "$measured" "$dir/plan-diff.json"
    else
      jq -r "${_AID_SR_STEP_NAME_JQ}"' "# EPIC: \(.epic_id // .id // "")\n\n" + ((.objective // .goal // "") | tostring) + "\n\n" + ([.steps | to_entries[] | "## \(.key as $k | .value | step_name($k)): \(.value.objective // "")\n" + ((.value.acceptance_criteria // []) | map("- " + .) | join("\n"))] | join("\n\n"))' "$plan_json" > "$dir/dod.md"
      jq 'def notier: map(gsub(" ?\\(tier: t[0-9]\\)"; "")); {outputs: ([.steps[].outputs[]?] | notier), allowed_paths: [.steps[].allowed_paths[]?], forbidden_paths: [.steps[].forbidden_paths[]?], scope_declared: true}' "$plan_json" > "$dir/files.json"
    fi
    _aid_sr_foreign_step "$dir" "$plan_json" || return 1
  fi
  _aid_sr_packet_finish "$root" "$dir" "$prev"
}

# _aid_sr_foreign_missing <name> <worktree> — the packet is not built over a
# foreign worktree that is gone (never a silent read of the live checkout).
_aid_sr_foreign_missing() {
  echo "prepare: REFUSED (foreign_worktree_missing): the worktree $2 of repo_roots '$1' is gone — the review would read the live checkout instead" >&2
  echo "next: recreate it on its recorded branch (git -C <path> worktree add $2 <branch>), then prepare again" >&2
  return 1
}

# _aid_sr_foreign_step <packet_dir> <plan.json> — P112: a plan with repo_roots.
# The ranges the step check verified (step-check.json other_repos) go into
# foreign-<name>.patch, files.json names the worktree paths, packet.json lists
# every declared repository (touched or not) for the prompt.
_aid_sr_foreign_step() {
  local dir="$1" pj="$2" name path wt br patch out='[]' rng
  jq -e '(.repo_roots // []) | length > 0' "$pj" >/dev/null 2>&1 || return 0
  aid_rr_load "$pj" || return 1
  while IFS=$'\t' read -r name path wt br; do
    [[ -n "$name" ]] || continue
    [[ -d "$wt" ]] || { _aid_sr_foreign_missing "$name" "$wt"; return 1; }
    patch=""
    rng="$(jq -r --arg n "$name" 'first(.other_repos[]? | select(.name == $n) | .range) // ""' "$dir/step-check.json")"
    if [[ -n "$rng" ]]; then
      patch="foreign-${name}.patch"
      git -C "$wt" diff "$rng" > "$dir/$patch" || { echo "prepare: the range ${rng} does not resolve in ${wt}" >&2; return 1; }
    fi
    out="$(jq -c --arg n "$name" --arg p "$path" --arg w "$wt" --arg b "$br" --arg f "$patch" \
      '. + [{name: $n, live: $p, worktree: $w, branch: $b, patch: (if $f == "" then null else $f end)}]' <<< "$out")"
  done <<< "$_AID_RR_CACHE"
  local fj; fj="$(cat "$dir/files.json")"
  # every declared path in the scope → its worktree (outputs are bullets: the text rewrite)
  local k v
  for k in outputs allowed_paths forbidden_paths; do
    v="$(jq -c --arg k "$k" '.[$k] // []' <<< "$fj")"
    v="$(jq -r '.[]' <<< "$v" | while IFS= read -r line; do aid_rr_text "$pj" "$line" || true; done | jq -Rsc 'split("\n") | map(select(length > 0))')"
    fj="$(jq -c --arg k "$k" --argjson v "$v" '.[$k] = $v' <<< "$fj")"
  done
  printf '%s\n' "$fj" > "$dir/files.json"
  jq -n --argjson f "$out" '{foreign: $f}' > "$dir/packet.json"
}

# _aid_sr_foreign_final <packet_dir> <run_dir> — P112: the whole-plan round
# reads each foreign branch from its frozen base to its frozen head (the
# candidate manifest, written at freeze), in the plan's worktree.
_aid_sr_foreign_final() {
  local dir="$1" run="$2" plan root pid man name path wt br base head out='[]' files='[]' f
  [[ -f "${run}/cp7/brief.json" ]] || return 0
  plan="$(jq -r .plan "${run}/cp7/brief.json")"; root="$(jq -r .root "${run}/cp7/brief.json")"
  awk 'NR==1 && !/^---/ {exit} NR>1 && /^---/ {exit} /repo_roots/ {f=1; exit} END {exit !f}' "$plan" 2>/dev/null || return 0
  aid_rr_load "$plan" "" "$(basename "$root")" || return 1
  pid="$(yq --front-matter=extract -r '.id // ""' "$plan" 2>/dev/null)"
  man="${root}/.aid-o/work/plan-state/${pid}/plan-boundary-manifest.json"
  while IFS=$'\t' read -r name path wt br; do
    [[ -n "$name" ]] || continue
    [[ -d "$wt" ]] || { _aid_sr_foreign_missing "$name" "$wt"; return 1; }
    IFS=$'\t' read -r base head < <(jq -r --arg n "$name" 'first(.plan_boundary_manifest.repo_roots[]? | select(.name == $n) | [.base, .head] | @tsv) // ""' "$man" 2>/dev/null)
    [[ -n "${base:-}" && -n "${head:-}" ]] || { echo "prepare: the candidate manifest records no frozen base/head for repo_roots '${name}' (${man}); run plan-finalize --stage freeze" >&2; return 1; }
    git -C "$wt" diff "${base}..${head}" > "$dir/foreign-${name}.patch" || { echo "prepare: ${base}..${head} does not resolve in ${wt}" >&2; return 1; }
    while IFS= read -r f; do [[ -n "$f" ]] && files="$(jq -c --arg p "${wt}/${f}" '. + [$p]' <<< "$files")"; done \
      < <(git -C "$wt" diff --name-only "${base}..${head}")
    out="$(jq -c --arg n "$name" --arg p "$path" --arg w "$wt" --arg b "$br" --arg f "foreign-${name}.patch" \
      --arg c "$(git -C "$wt" rev-list --count "${base}..${head}")" \
      '. + [{name: $n, live: $p, worktree: $w, branch: $b, patch: $f, commits: ($c | tonumber)}]' <<< "$out")"
  done <<< "$_AID_RR_CACHE"
  jq -c --argjson f "$files" '.outputs = $f' "$dir/files.json" > "$dir/files.json.tmp" && mv "$dir/files.json.tmp" "$dir/files.json"
  jq -n --argjson f "$out" '{foreign: $f}' > "$dir/packet.json"
}

# _aid_sr_packet_finish <root> <packet_dir> <prev_round_dir> — what every packet
# ends with: the confirmation round's open findings and fix diff, then the manifest.
_aid_sr_packet_finish() {
  local root="$1" dir="$2" prev="${3:-}" f
  if [[ -n "$prev" && -f "$prev/merged.json" ]]; then
    jq "{findings: [.findings[] | select(${AID_SR_OPEN_JQ})]}" "$prev/merged.json" > "$dir/open-findings.json"
    # A previous round prepared without head_sha: no fix diff can be cut, and
    # the prompt falls back to the whole diff (round.json confirmation_fallback).
    local ph; ph="$(jq -r '.head_sha // ""' "$prev/round.json" 2>/dev/null)"
    if [[ -n "$ph" && "$ph" != null ]]; then
      git -C "$root" diff "${ph}..HEAD" > "$dir/fix.patch" || return 1
    fi
  fi
  (cd "$dir" && for f in *; do
     jq -n --arg f "$f" --arg s "$(sha256sum "$f" | cut -d' ' -f1)" '{file: $f, sha256: $s}'
   done) | jq -s --arg h "$(jq -r .head_sha "$dir/step-check.json")" '{head_sha: $h, files: .}' > "$dir/manifest.json"
}

aid_final_review_inputs_build() {
  local state_root="$1" out="$2/cp7" plan_file="$3" plan_id="$4" epic_dir
  [[ -f "$plan_file" ]] || { echo "produce: plan file not found: ${plan_file}" >&2; return 1; }
  mkdir -p "$out" || return 1
  # Every "**Acceptance Criteria:**" block under its step heading, and the
  # plan-level "## Acceptance Criteria" and "## Success Criteria" sections
  # (the plan template has both).
  awk '
    /^### / { step = $0 }
    /^## /  { in_success = ($0 ~ /^## (Success|Acceptance) Criteria/); in_ac = 0; if (in_success) print "\n" $0; next }
    /^\*\*Acceptance Criteria:\*\*/ { in_ac = 1; print "\n" step; next }
    in_ac && /^\*\*/ { in_ac = 0 }
    in_ac || in_success { print }
  ' "$plan_file" > "$out/criteria.md"
  [[ -s "$out/criteria.md" ]] || { echo "produce: ${plan_file} has no acceptance or success criteria" >&2; return 1; }
  for epic_dir in "${state_root}/.aid-o/work/evidence/E-${plan_id#P}-"*; do
    [[ -d "$epic_dir" ]] || continue
    # What the step rounds of the run's latest run left open reaches the close
    # (the last round of each step, open blockers and majors; P110, the only
    # path since CP3 left in 3.0.0, P114).
    local lrun; lrun="$(ls -dt "$epic_dir"/*/cp2 2>/dev/null | head -n1)"
    { for st in ${lrun:+"$lrun"/step-*}; do
        ls "$st"/round-*/merged.json 2>/dev/null | sort -V | tail -1
      done; } | xargs -r cat | jq -sc --arg e "$(basename "$epic_dir")" \
      '{epic: $e, review: "steps", findings: [.[].findings[]? | select(((.status | IN("open", "disputed", "carried", "routed", "form_invalid")) or (.dispute.pm.answer == "accepted")) and (.severity == "blocker" or .severity == "major"))
           | {severity, status: (if .dispute.pm.answer == "accepted" then "dismissed_by_pm" else .status end), claim, evidence, fix} + (if .rule then {rule} else {} end)]}'
  done | jq -s '{epics: .}' > "$out/epic-findings.json"
  # P110: which brief the whole-plan round reads — resolved again at every
  # prepare (aid_plan_review_brief_resolve), so the packet carries the file as it is.
  jq -n --arg p "$plan_file" --arg r "$state_root" '{plan: $p, root: $r}' > "$out/brief.json"
}

aid_final_review_packet_build() {
  local root="$1" dir="$2/packet" sc="$3" run="$4" prev="${5:-}" f range
  [[ -f "$sc" ]] || { echo "prepare: no step check at ${sc}" >&2; return 1; }
  for f in gates_report.json plan-diff.json cp7/criteria.md cp7/epic-findings.json; do
    [[ -f "${run}/${f}" ]] || { echo "prepare: ${run}/${f} is missing; run plan-finalize --stage produce first" >&2; return 1; }
  done
  mkdir -p "$dir" || return 1
  cp "$sc" "$dir/step-check.json" && cp "${run}/gates_report.json" "${run}/plan-diff.json" "${run}/cp7/epic-findings.json" "$dir/" \
    && cp "${run}/cp7/criteria.md" "$dir/dod.md" || return 1
  echo '{"outputs": [], "allowed_paths": [], "forbidden_paths": [], "scope_declared": false}' > "$dir/files.json"
  range="$(jq -r .range "$sc")"
  git -C "$root" diff "$range" > "$dir/diff.patch" || return 1
  git -C "$root" diff "$range" -- '*CHANGELOG*' '*README*' 'docs/**' '*.md' > "$dir/claims.patch" || return 1
  # P110: the brief, through the CP1 resolver and its refusals
  if [[ -f "${run}/cp7/brief.json" ]]; then
    declare -F aid_plan_review_brief_resolve >/dev/null || source "${_AID_SR_PLUGIN}/scripts/lib/aid-plan-review-packet.sh"
    aid_plan_review_brief_resolve "$(jq -r .root "${run}/cp7/brief.json")" "$(jq -r .plan "${run}/cp7/brief.json")" "$dir" || return 1
  fi
  if (( $(jq '.size.files' "$sc") > 400 )); then
    local epic
    while IFS= read -r epic; do
      git -C "$root" log --format=%H --grep="$epic" "$range" | while IFS= read -r f; do git -C "$root" show "$f"; done > "$dir/diff-${epic}.patch"
    done < <(jq -r '.epics[].epic' "$dir/epic-findings.json")
  fi
  _aid_sr_foreign_final "$dir" "$run" || return 1
  _aid_sr_packet_finish "$root" "$dir" "$prev"
}

# aid_step_review_role_section <role> — the role's section of the roles skill.
aid_step_review_role_section() {
  awk -v h="## Role: $1" '
    $0 == h { on = 1; print; next }
    on && /^## / { exit }
    on { print }
  ' "$AID_SR_ROLES_SKILL"
}

# _aid_sr_patch <file> <title> — a patch inline when one prompt can carry it,
# else its file list and where to read it: a whole-plan or whole-EPIC range can
# be a megabyte (ACTA P024: 1.1 MB), and a prompt that large is never read.
_aid_sr_patch() {
  local f="$1" title="$2" bytes; bytes="$(wc -c < "$f")"
  if (( bytes <= ${AID_REVIEW_INLINE_MAX_BYTES:-150000} )); then
    echo "## ${title} (also on disk: ${f})"
    echo '~~~~~diff'; cat "$f"; echo '~~~~~'   # tildes: a diff of Markdown carries ``` lines of its own
  else
    echo "## ${title}: ${bytes} bytes, too large to inline. READ IT FROM DISK with read-only tools, file by file: ${f}"
    grep '^diff --git' "$f" | sed -E 's|^diff --git a/(.*) b/.*|- \1|'
  fi
}

aid_step_review_prompt_render() {
  local role="$1" round="$2" dir="$3" cp="$4" step="${5:-}" section vars out note=""
  section="$(aid_step_review_role_section "$role")"
  [[ -n "$section" ]] || { echo "prepare: role ${role} has no section in ${AID_SR_ROLES_SKILL}" >&2; return 1; }
  vars="${dir}/vars-${role}.json"; out="${dir}/prompt-${role}.md"
  local what
  case "$cp" in
    cp2) what="the diff of one implementation step (step ${step}) against its acceptance criteria" ;;
    cp6) what="a working-tree change made in fast mode against its task" ;;
    cp7) what="the diff of one whole plan, every EPIC together, against the plan's acceptance criteria" ;;
  esac
  (( round >= 2 )) && note="This is a confirmation round: the packet below carries the findings still open and the author's fix."
  jq -n --arg s "$section" --arg cp "$cp" --arg r "$round" --arg o "${dir}/reviewer-${role}.json" \
        --arg e "$AID_SR_EVIDENCE_FORMS" --arg w "$what" --arg n "$note" \
    '{role_section: $s, checkpoint: $cp, round: $r, output_path: $o, evidence_forms: $e, packet_name: $w, confirmation_note: $n}' > "$vars"
  bash "${_AID_SR_PLUGIN}/scripts/lib/aid-render-prompt.sh" \
    --template "$AID_SR_TEMPLATE" --vars-json "$vars" --output "$out" >/dev/null || {
      echo "prepare: prompt for ${role} did not render" >&2; rm -f "$out"; return 1; }
  {
    echo
    echo "--- PACKET ---"
    echo
    echo "The repository to read is $(jq -r '.head_sha' "${dir}/packet/step-check.json" | cut -c1-12) (HEAD of the checkout you run in; read-only). Evidence is \`path:line\` at that commit."
    echo
    # A confirmation or delta round (P110, IMP-689) reads the fix diff and what
    # stays open, not the whole step again; without a fix.patch it falls back.
    local narrow=0 cp7_mode
    cp7_mode="$(jq -r '.mode // "full"' "${dir}/round.json" 2>/dev/null)"
    [[ -f "${dir}/packet/open-findings.json" && -f "${dir}/packet/fix.patch" && "$cp" != cp7 ]] && narrow=1
    [[ "$cp" == cp7 && "$cp7_mode" == confirmation && -f "${dir}/packet/fix.patch" ]] && narrow=1
    if [[ "$cp" == cp7 && "$cp7_mode" == confirmation ]]; then
      # P117 (15): the previous candidate passed a full round; the fix touched documentation only
      echo "## This is a confirmation round over the whole plan"
      echo
      echo "The previous candidate ($(jq -r '.previous_candidate[:12]' "$(dirname "$(dirname "$dir")")/fix-class.json" 2>/dev/null)) passed a full whole-plan round. Since then the author changed documentation only (fix.patch below; areas it invalidates: $(jq -r '.invalidated_feeds | join(", ")' "$(dirname "$(dirname "$dir")")/fix-class.json" 2>/dev/null))."
      echo "Your job:"
      echo "1. The fix is right: every claim it adds or changes is true of the code at HEAD."
      echo "2. A regression the fix caused indirectly: you can read the WHOLE candidate at HEAD — a claim now contradicting the code elsewhere, a broken reference, an instruction that no longer matches the behaviour. Look for it."
      echo "3. Any finding still listed below: confirm it is fixed everywhere, or report it again."
      echo "Do not re-review code the fix did not change; the full round already did."
      echo
      jq -r '.findings[] | "- [\(.severity)] \(.claim) (evidence: \(.evidence))"' "${dir}/packet/open-findings.json" 2>/dev/null
      _aid_sr_patch "${dir}/packet/fix.patch" "What the author changed (fix.patch)" | sed 's/^## /### /'
      echo
    elif (( narrow )) && [[ "$(jq '.findings | length' "${dir}/packet/open-findings.json")" == 0 ]]; then
      echo "## This is a delta round"
      echo
      echo "The previous round passed and the step moved since. Review only the new commits (fix.patch below) against the Definition of Done; do not review the rest again."
      echo
      _aid_sr_patch "${dir}/packet/fix.patch" "The new commits (fix.patch)" | sed 's/^## /### /'
      echo
    elif [[ -f "${dir}/packet/open-findings.json" ]]; then
      echo "## This is a confirmation round"
      echo
      echo "The author fixed the change after the previous round. Your job now:"
      echo "1. For each finding below, check that its rule holds everywhere in the current tree, not only at the cited line: every path, input form and caller the rule covers. Fixed everywhere: do not report it. Not fixed, or fixed only where it was cited (a variant the fix missed): report it again with the same claim and the same first evidence citation, and append the variant's citation after it."
      if [[ "$cp" == cp7 ]]; then
        # P117 (16): after a failing round, or a fix beyond documentation, the whole plan is reviewed again
        echo "2. This is a FULL round over the new candidate: review the whole plan as below, not only the fix."
      else
        echo "2. Report NEW problems only when the fix (fix.patch below) introduced them. Do not review the rest again."
      fi
      echo
      echo "### Findings still open"
      jq -r '.findings[] | "- [\(.severity)] \(.claim) (evidence: \(.evidence); fix asked: \(.fix)\(if .rule then "; rule: \(.rule)" else "" end))"' "${dir}/packet/open-findings.json"
      echo
      if [[ -f "${dir}/packet/fix.patch" ]]; then
        _aid_sr_patch "${dir}/packet/fix.patch" "What the author changed (fix.patch)" | sed 's/^## /### /'
      else
        echo "The previous round recorded no head commit, so no fix diff could be cut: the whole diff follows below (round.json confirmation_fallback)."
      fi
      echo
    fi
    echo "## Deterministic step check (already reported, do not repeat)"
    jq -r '"- verdict: \(.verdict) (\(.reason))\n- range: \(.range) [\(.range_source)]\n- files in scope: \(.files.in_scope | length); outside the step scope: \(.files.outside_files | join(", ") | if . == "" then "none" else . end); forbidden touched: \(.files.forbidden_touched | join(", ") | if . == "" then "none" else . end)\n- security patterns: \(.security.matched_rules | join(", ") | if . == "" then "none" else . end)\n- handler patterns (behaviour trace required from a generalist blocker/major): \(.handler_patterns | join(", ") | if . == "" then "none" else . end)\n- tests added: \(.tests.added | map("\(.path) [\(.tier)]") | join(", ") | if . == "" then "none" else . end); changed: \(.tests.changed | map(.path) | join(", ") | if . == "" then "none" else . end)\n- size: \(.size.files) file(s), \(.size.lines) line(s)"' "${dir}/packet/step-check.json"
    echo
    echo "## Definition of Done"
    cat "${dir}/packet/dod.md"
    echo
    if [[ "$cp" == cp2 && -f "${dir}/packet/plan-diff.json" ]]; then
      echo "## Measured criteria of this step (aid-plan-diff.sh --step, run at this commit; packet/plan-diff.json)"
      jq -r '.results[] | "- \(.ac_label): \(.verdict) — \(.evidence)" + (if .deferred_to_step then " (measured at plan step \(.deferred_to_step))" else "" end) + (if .deferred then " (deferred by the PM: \(.deferred.reason))" else "" end)' "${dir}/packet/plan-diff.json"
      [[ "$(jq -r '.unmeasured_step // false' "${dir}/packet/plan-diff.json")" == true ]] && echo "- (the step closes no brief point and has no labelled criterion of its own: nothing was run)"
      echo "An absent criterion is a blocker unless the PM deferred it."
      echo
    fi
    if [[ "$cp" == cp7 ]]; then
      echo "## What the step reviews already judged (do not repeat; read ACROSS the steps)"
      jq -r '.epics[] | "- \(.epic): its steps were reviewed one by one — \(.findings | length) finding(s) the step rounds left open" + ((.findings | map("\n  - [\(.severity), \(.status)] \(.claim) (\(.evidence))") | join("")))' "${dir}/packet/epic-findings.json"
      echo
      # P117 (17): the plan's nightly tests, run by the close at this candidate
      local _ptf; _ptf="$(dirname "$(dirname "$dir")")/plan-tests.json"
      if [[ -f "$_ptf" ]] && [[ "$(jq '.tests | length' "$_ptf")" -gt 0 ]]; then
        echo "## The plan's nightly tests, run by the close at $(jq -r '.candidate_sha[:12]' "$_ptf") (${_ptf})"
        jq -r '.tests[] | "- \(.path): \(if .exit == 0 then "pass" elif .exit == null then "NOT RUN — \(.reason)" else "exit \(.exit)" end)\(if .duration_s then " in \(.duration_s) s" else "" end) — \(.command // "")"' "$_ptf"
        echo "This is the evidence for these tests; do not report them as unproven."
        echo
      fi
      echo "## Gates at the candidate (gates_report.json on disk: ${dir}/packet/gates_report.json)"
      jq -r "${AID_GATE_ROW_JQ}"'.gates | gate_rows_normalize | to_entries[] | select((.key|startswith("_")|not) and (.value|type) == "object")
             | "- \(.key): \(.value.status) (\(.value.reason))" + (if .value.waived then " waived" else "" end)
               + (if .value.reused_from then " (reused from \(.value.reused_from))" else "" end)' "${dir}/packet/gates_report.json"
      echo
      # P110: the PM's brief and the isolated close measurement, in the prompt
      # itself — final_criteria answers point by point from these two.
      if [[ -f "${dir}/packet/zadani.md" ]]; then
        echo "## The PM's brief (packet/zadani.md; cite it as zadani.md:<line>)"
        echo '~~~~~markdown'; cat -n "${dir}/packet/zadani.md"; echo '~~~~~'
      elif [[ -f "${dir}/packet/zadani-note.txt" ]]; then
        echo "## The PM's brief: $(cat "${dir}/packet/zadani-note.txt")"
      fi
      echo
      echo "## Measured points at the close (aid-plan-diff.sh --isolated; ${dir}/packet/plan-diff.json)"
      jq -r '"isolation: \(.isolation | tojson)", (.results[]? | "- \(.ac_label): \(.verdict) — \(.evidence)")' "${dir}/packet/plan-diff.json"
      echo
      _aid_sr_patch "${dir}/packet/claims.patch" "claims.patch (CHANGELOG, README and docs hunks of the range)"
      echo
      local part
      for part in "${dir}"/packet/diff-*.patch; do
        [[ -f "$part" ]] && echo "The range is large; one part per EPIC is on disk: ${part}"
      done
    fi
    if [[ -f "${dir}/packet/packet.json" ]] && (( $(jq '.foreign | length' "${dir}/packet/packet.json") > 0 )); then
      echo "## Foreign repositories of this plan (repo_roots)"
      echo
      local fname fwt fbr fpatch flive
      local fcommits
      while IFS=$'\t' read -r fname flive fwt fbr fpatch fcommits; do
        echo "### ${fname}: the plan's work is in the worktree ${fwt} (branch ${fbr})"
        echo "The live checkout at ${flive} is not this plan's work — never read it; read and cite files under ${fwt}."
        if [[ -n "$fpatch" ]]; then
          _aid_sr_patch "${dir}/packet/${fpatch}" "${fname} diff (${fpatch})" | sed 's/^## /#### /'
          [[ "$fcommits" == 0 ]] && echo "(no commits on ${fbr})"
        else
          echo "(this step made no commits there)"
        fi
        echo
      done < <(jq -r '.foreign[] | [.name, .live, .worktree, .branch, (.patch // ""), (.commits // "" | tostring)] | @tsv' "${dir}/packet/packet.json")
    fi
    if (( narrow )); then
      echo "The whole step's diff is on disk (${dir}/packet/diff.patch) for a variant the fix may have missed; it is not repeated here."
    else
      echo "## Declared scope (files.json)"
      jq -r '"outputs:\n" + ((.outputs // []) | map("- " + .) | join("\n")) + "\nallowed_paths: " + ((.allowed_paths // []) | join(", ")) + "\nforbidden_paths: " + ((.forbidden_paths // []) | join(", "))' "${dir}/packet/files.json"
      echo
      _aid_sr_patch "${dir}/packet/diff.patch" "diff.patch"
    fi
  } >> "$out"
}

# _aid_sr_finding_file <evidence> — the file a finding's first evidence names:
# `<sha>:path:line; path:line` → `path`.
_aid_sr_finding_file() {
  local e="${1%%;*}"
  e="$(sed -E 's/^[0-9a-f]{7,40}://' <<< "$e")"
  printf '%s' "${e%%:*}"
}

# _aid_sr_later_step_covers <plan_json> <step> <file> — 0 when a step after
# <step> declares the file in outputs or allowed_paths (the same glob rule the
# FSM's reconciliation applies, lib/aid-ancillary.sh); a covered finding is
# carried to that step, an uncovered one is routed.
_aid_sr_later_step_covers() {
  local plan_json="$1" step="$2" file="$3" pat
  while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    _aid_ancillary_glob_match "$file" "$pat" && return 0
  done < <(jq -r --argjson s "$step" '.steps | to_entries[] | select(.key > $s) | .value
             | ((.allowed_paths // [])[]), ((.outputs // [])[] | capture("`(?<p>[^`]+)`") | .p)' "$plan_json" 2>/dev/null)
  return 1
}

# aid_step_review_route_open <root> <evidence_dir> <checkpoint> <step> <round_dir> <last>
#   After the LAST allowed round (<last> = 1) every blocker or major still open
#   or disputed is accounted for, so nothing a reviewer proved is lost:
#     cp2, a later step of the plan covers the file → aid_obligation_add
#          (release_blocker for a blocker, followup for a major); merged status
#          `carried`
#     cp2 otherwise                                → aid_finding_route to
#          epic:<this EPIC>, keyed by fingerprint (aid_finding_recorded first,
#          so a re-run adds no second entry); merged status `routed`; the FSM's
#          done-advance then blocks until the PM resolves or backlogs it
#     cp6, or an EPIC of no plan                   → nothing to write to: the
#          findings stay `open` in merged.json and the close says so
#     cp7                                          → the findings stay `open`;
#          the plan-final decision reads merged.json and blocks on them
#   Before the last round the next round confirms; nothing is written.
#   A journal write failure returns 1 BEFORE merged.json is touched, so close
#   fails without closed_at and can be run again.
aid_step_review_route_open() {
  local root="$1" evid="$2" cp="$3" step="${4:-}" dir="$5" last="${6:-0}"
  local epic plan_id=""
  epic="$(basename "$(dirname "$evid")")"
  [[ "${epic%%_*}" =~ ^E-([0-9]+) ]] && plan_id="P${BASH_REMATCH[1]}"
  # The journals live in the STATE root of the reviewed checkout (a worktree
  # canonicalises to its primary), never in cwd's.
  export AID_PLAN_STATE_PROJECT_ROOT="${AID_PLAN_STATE_PROJECT_ROOT:-$root}"
  # A finding routed after an earlier last round and confirmed fixed by a
  # PM-overridden later round: its route is resolved, or done-advance would
  # block on a finding nobody owes any more.
  if [[ "$cp" != cp6 && -n "$plan_id" ]]; then
    local fixed_fp jf
    jf="$(_aid_rf_file "$plan_id" 2>/dev/null)" || jf=""
    if [[ -n "$jf" && -s "$jf" ]]; then
      while IFS= read -r fixed_fp; do
        [[ -n "$fixed_fp" ]] || continue
        # still routed: its latest route/resolve is a route (lib/aid-routed-findings.sh)
        jq -e --arg fp "$fixed_fp" -s '[.[] | select((.op == "route" or .op == "resolve") and .fingerprint == $fp)] | last | .op == "route"' "$jf" >/dev/null 2>&1 || continue
        local how="fixed: confirmed by"   # a finding the PM dismissed is "fixed" in status only
        jq -e --arg fp "$fixed_fp" -s 'any(.[].findings[]; .fingerprint == $fp and .dispute.pm.answer == "accepted")' \
          "${dir%/*}"/round-*/merged.json >/dev/null 2>&1 && how="dismissed by the PM (dispute accepted) in"
        aid_finding_resolve "$plan_id" "$fixed_fp" "${how} ${cp}${step:+ step $step} $(basename "$dir") at $(git -C "$root" rev-parse --short HEAD)" || return 1
      done < <(jq -r '.findings[] | select(.status == "fixed") | .fingerprint' "${dir%/*}"/round-*/merged.json 2>/dev/null | sort -u)
    fi
  fi
  local open
  open="$(jq -c '[.findings[] | select((.status | IN("open", "disputed", "form_invalid")) and (.severity == "blocker" or .severity == "major"))]' "${dir}/merged.json")"
  [[ "$(jq 'length' <<< "$open")" -gt 0 ]] || return 0
  (( last )) || return 0
  if [[ "$cp" == cp7 ]]; then
    echo "close: $(jq 'length' <<< "$open") finding(s) stay open in ${dir}/merged.json; plan-finalize --stage decide blocks on them until a fix is confirmed" >&2
    return 0
  fi
  if [[ "$cp" == cp6 || -z "$plan_id" ]]; then
    echo "close: $(jq 'length' <<< "$open") finding(s) stay open in ${dir}/merged.json ($([[ "$cp" == cp6 ]] && echo "fast mode has no plan journal" || echo "${epic} belongs to no plan")); the PM decides on them" >&2
    return 0
  fi
  local n i fp sev ev file status statuses="{}" total_steps
  n="$(jq 'length' <<< "$open")"
  total_steps="$(jq '.steps | length' "${evid}/plan.json" 2>/dev/null || echo "")"
  for (( i = 0; i < n; i++ )); do
    fp="$(jq -r ".[$i].fingerprint" <<< "$open")"; sev="$(jq -r ".[$i].severity" <<< "$open")"; ev="$(jq -r ".[$i].evidence // \"\"" <<< "$open")"
    file="$(_aid_sr_finding_file "$ev")"
    if [[ "$cp" == cp2 && -n "$file" ]] && _aid_sr_later_step_covers "${evid}/plan.json" "$step" "$file"; then
      status=carried
      local ref="${cp} step ${step} round $(basename "$dir") ${fp}" ofile
      ofile="$(_aid_obligation_file "$plan_id" 2>/dev/null)" || return 1
      if ! { [[ -f "$ofile" ]] && grep -qF "$fp" "$ofile"; }; then
        aid_obligation_add "$plan_id" "$([[ "$sev" == blocker ]] && echo release_blocker || echo followup)" \
          "$(jq -r ".[$i].claim" <<< "$open") (${file}; fix: $(jq -r ".[$i].fix" <<< "$open"))" "$ref" 2>/dev/null || return 1
      fi
    else
      status=routed
      if ! aid_finding_recorded "$plan_id" "$fp"; then
        aid_finding_route "$plan_id" "$fp" "$cp" "epic:${epic}" "$epic" "$total_steps" || return 1
      fi
    fi
    statuses="$(jq -c --arg fp "$fp" --arg s "$status" '.[$fp] = $s' <<< "$statuses")"
  done
  jq --argjson st "$statuses" '.findings |= map(if $st[.fingerprint] then .status = $st[.fingerprint] else . end)' \
    "${dir}/merged.json" > "${dir}/merged.json.tmp" && mv "${dir}/merged.json.tmp" "${dir}/merged.json" || return 1
  echo "close: $(jq -r '[to_entries[] | .value] | group_by(.) | map("\(length) \(.[0])") | join(", ")' <<< "$statuses") after the last round (${plan_id}, ${epic})" >&2
}
