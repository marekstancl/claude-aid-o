#!/usr/bin/env bash
# aid-step-review-packet.sh — what goes to a step, EPIC or fast-mode reviewer
# (P094 Step 6). The plan reviewer's packet is lib/aid-plan-review-packet.sh;
# the two builders share the template, the answer contract and the adapter,
# and differ in what they put in the packet.
#
# aid_step_review_packet_build <root> <checkpoint> <round_dir> <step_check> <plan_json> <step> [<prev_round_dir>]
#   Writes <round_dir>/packet/{diff.patch, dod.md, files.json, step-check.json,
#   manifest.json} and, for a confirmation round, open-findings.json and
#   fix.patch (the diff from the previous round's head to HEAD).
# aid_step_review_prompt_render <role> <round> <round_dir> <checkpoint> <step>
#   Renders defaults/prompts/review-prompt-v1.md for one role of
#   skills/step-review-roles.md through aid-render-prompt.sh, then appends the
#   packet. The diff is appended, never passed as a variable: the renderer
#   refuses a value containing `{{`, and a diff may legitimately contain one.
# aid_step_review_route_open <round_dir> <round>
#   After the last allowed round, routes or carries what stays open (P094
#   Step 7 fills this in); returns 0 when nothing is open.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.

_AID_SR_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AID_SR_TEMPLATE="${_AID_SR_PLUGIN}/defaults/prompts/review-prompt-v1.md"
AID_SR_ROLES_SKILL="${_AID_SR_PLUGIN}/skills/step-review-roles.md"
AID_SR_EVIDENCE_FORMS='`path:line` at the reviewed commit, or `<sha>:path:line` for a line of a file the diff deleted or moved (the pre-image at that commit)'

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
  # The DoD: the step's objective and criteria (cp2), every step's (cp3), or
  # the task text the step check recorded (cp6).
  if [[ "$cp" == cp6 ]]; then
    { echo "# Task"; echo; jq -r '.dod // "(no task text recorded)"' "$sc"; } > "$dir/dod.md"
    echo '{"outputs": [], "allowed_paths": [], "forbidden_paths": [], "scope_declared": false}' > "$dir/files.json"
  else
    [[ -f "$plan_json" ]] || { echo "prepare: no plan.json at ${plan_json}" >&2; return 1; }
    if [[ "$cp" == cp2 ]]; then
      jq -r --argjson s "$step" '.steps[$s] | "# Step \($s): \(.objective // "")\n\n## Acceptance criteria\n" + ((.acceptance_criteria // []) | map("- " + .) | join("\n"))' "$plan_json" > "$dir/dod.md"
      jq --argjson s "$step" '.steps[$s] | {outputs: (.outputs // []), allowed_paths: (.allowed_paths // []), forbidden_paths: (.forbidden_paths // []), scope_declared: true}' "$plan_json" > "$dir/files.json"
    else
      jq -r '"# EPIC: \(.epic_id // .id // "")\n\n" + ((.objective // .goal // "") | tostring) + "\n\n" + ([.steps | to_entries[] | "## Step \(.key): \(.value.objective // "")\n" + ((.value.acceptance_criteria // []) | map("- " + .) | join("\n"))] | join("\n\n"))' "$plan_json" > "$dir/dod.md"
      jq '{outputs: [.steps[].outputs[]?], allowed_paths: [.steps[].allowed_paths[]?], forbidden_paths: [.steps[].forbidden_paths[]?], scope_declared: true}' "$plan_json" > "$dir/files.json"
    fi
  fi
  if [[ -n "$prev" && -f "$prev/merged.json" ]]; then
    jq '{findings: [.findings[] | select((.status == "open" or .status == "disputed") and (.severity == "blocker" or .severity == "major"))]}' "$prev/merged.json" > "$dir/open-findings.json"
    git -C "$root" diff "$(jq -r .head_sha "$prev/round.json")..HEAD" > "$dir/fix.patch" || return 1
  fi
  (cd "$dir" && for f in *; do
     jq -n --arg f "$f" --arg s "$(sha256sum "$f" | cut -d' ' -f1)" '{file: $f, sha256: $s}'
   done) | jq -s --arg h "$(jq -r .head_sha "$sc")" '{head_sha: $h, files: .}' > "$dir/manifest.json"
}

# aid_step_review_role_section <role> — the role's section of the roles skill.
aid_step_review_role_section() {
  awk -v h="## Role: $1" '
    $0 == h { on = 1; print; next }
    on && /^## / { exit }
    on { print }
  ' "$AID_SR_ROLES_SKILL"
}

aid_step_review_prompt_render() {
  local role="$1" round="$2" dir="$3" cp="$4" step="${5:-}" section vars out note=""
  section="$(aid_step_review_role_section "$role")"
  [[ -n "$section" ]] || { echo "prepare: role ${role} has no section in ${AID_SR_ROLES_SKILL}" >&2; return 1; }
  vars="${dir}/vars-${role}.json"; out="${dir}/prompt-${role}.md"
  local what
  case "$cp" in
    cp2) what="the diff of one implementation step (step ${step}) against its acceptance criteria" ;;
    cp3) what="the diff of one whole EPIC against its acceptance criteria" ;;
    cp6) what="a working-tree change made in fast mode against its task" ;;
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
    if [[ -f "${dir}/packet/open-findings.json" ]]; then
      echo "## This is a confirmation round"
      echo
      echo "The author fixed the change after the previous round. Your job now:"
      echo "1. For each finding below, check the current tree: if it is fixed, do not report it; if it is not, report it again (same claim)."
      echo "2. Report NEW problems only when the fix (fix.patch below) introduced them. Do not review the rest again."
      echo
      echo "### Findings still open"
      jq -r '.findings[] | "- [\(.severity)] \(.claim) (evidence: \(.evidence); fix asked: \(.fix))"' "${dir}/packet/open-findings.json"
      echo
      echo "### What the author changed (fix.patch)"
      echo '```diff'; cat "${dir}/packet/fix.patch"; echo '```'
      echo
    fi
    echo "## Deterministic step check (already reported, do not repeat)"
    jq -r '"- verdict: \(.verdict) (\(.reason))\n- range: \(.range) [\(.range_source)]\n- files in scope: \(.files.in_scope | length); outside the step scope: \(.files.outside_files | join(", ") | if . == "" then "none" else . end); forbidden touched: \(.files.forbidden_touched | join(", ") | if . == "" then "none" else . end)\n- security patterns: \(.security.matched_rules | join(", ") | if . == "" then "none" else . end)\n- handler patterns (behaviour trace required from a generalist blocker/major): \(.handler_patterns | join(", ") | if . == "" then "none" else . end)\n- tests added: \(.tests.added | map("\(.path) [\(.tier)]") | join(", ") | if . == "" then "none" else . end); changed: \(.tests.changed | map(.path) | join(", ") | if . == "" then "none" else . end)\n- size: \(.size.files) file(s), \(.size.lines) line(s)"' "${dir}/packet/step-check.json"
    echo
    echo "## Definition of Done"
    cat "${dir}/packet/dod.md"
    echo
    echo "## Declared scope (files.json)"
    jq -r '"outputs:\n" + ((.outputs // []) | map("- " + .) | join("\n")) + "\nallowed_paths: " + ((.allowed_paths // []) | join(", ")) + "\nforbidden_paths: " + ((.forbidden_paths // []) | join(", "))' "${dir}/packet/files.json"
    echo
    echo "## diff.patch (also on disk: ${dir}/packet/diff.patch)"
    echo '```diff'; cat "${dir}/packet/diff.patch"; echo '```'
  } >> "$out"
}

# The routing of findings that stay open after the last round is P094 Step 7;
# until then a round closes with its findings recorded as open in merged.json.
aid_step_review_route_open() { return 0; }
