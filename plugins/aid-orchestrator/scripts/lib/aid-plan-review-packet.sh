#!/usr/bin/env bash
# aid-plan-review-packet.sh — what goes to a plan reviewer and what comes back.
#
# Out: the packet every reviewer of a round receives (plan snapshot, the
# deterministic check's report, the project standards) and the rendered prompt.
# In: the reviewer's answer file, checked against
# defaults/schemas/review-finding.schema.json (the answer contract every
# checkpoint shares since P094) in two halves: the answer's shape (collect),
# and each finding's proof (the adjudicator).
#
# Both halves read the plan-review role list ($defs.roles_cp1) and the two
# patterns (command, evidence) from the schema file itself, so the schema is
# the one source of the contract. The prompt is rendered from the shared
# template defaults/prompts/review-prompt-v1.md with the cp1 variable values.
# Sourced by scripts/aid-review-round.sh and aid-review-adjudicate.sh; tested by
# scripts/tests/bats/test-plan-review-schema.bats, test-review-finding-schema.bats and
# test-plan-review-round.bats.

_AID_PR_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AID_PR_SCHEMA="${_AID_PR_PLUGIN}/defaults/schemas/review-finding.schema.json"
AID_PR_TEMPLATE="${_AID_PR_PLUGIN}/defaults/prompts/review-prompt-v1.md"
AID_PR_ROLES_SKILL="${_AID_PR_PLUGIN}/skills/plan-review-roles.md"
# The evidence forms a plan reviewer may cite; the step checkpoints pass their own.
AID_PR_EVIDENCE_FORMS='`path:line` inside the repository, `plan.md:line` for the plan itself (the line numbers of the plan in the packet below), or `absent:path` for a file the plan presumes and the repository lacks; one citation that resolves is enough'

# shellcheck source=aid-standards-map.sh
source "${_AID_PR_PLUGIN}/scripts/lib/aid-standards-map.sh"

# aid_plan_review_packet_build <plan> <project_root> <plan_check_json> <round_dir>
#   Writes <round_dir>/packet/{plan.md, plan-check.json, standards.md,
#   manifest.json}. Refuses (return 1) when the script report was made for other
#   plan bytes: reviewers must review what the deterministic check saw.
aid_plan_review_packet_build() {
  local plan="$1" root="$2" check="$3" dir="$4/packet" sha checked rc=0
  sha="$(sha256sum "$plan" | cut -d' ' -f1)"
  checked="$(jq -r '.plan_sha256 // ""' "$check" 2>/dev/null)"
  if [[ "$checked" != "$sha" ]]; then
    echo "prepare: plan-check.json does not match plan (sha256 ${checked:0:12} vs ${sha:0:12}); rerun aid-plan-check.sh --json ${check}" >&2
    return 1
  fi
  mkdir -p "$dir" || return 1
  cp "$plan" "$dir/plan.md" && cp "$check" "$dir/plan-check.json" || return 1

  local derived
  derived="$(aid_standards_derive "$plan" "$root" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) { echo "# Standards bound by the plan's declared paths (area tag, standard ids)"; echo; printf '%s\n' "${derived:-none}"; } > "$dir/standards.md" ;;
    1) echo "no standards map in this project" > "$dir/standards.md" ;;
    *) echo "a standards map is configured but could not be read" > "$dir/standards.md" ;;
  esac

  (cd "$dir" && for f in plan.md plan-check.json standards.md; do
     jq -n --arg f "$f" --arg s "$(sha256sum "$f" | cut -d' ' -f1)" '{file: $f, sha256: $s}'
   done) | jq -s --arg sha "$sha" '{plan_sha256: $sha, files: .}' > "$dir/manifest.json"
}

# aid_plan_review_role_section <role> — the role's section of the roles skill,
# from its `## Role:` heading to the next `## ` heading.
aid_plan_review_role_section() {
  awk -v h="## Role: $1" '
    $0 == h { on = 1; print; next }
    on && /^## / { exit }
    on { print }
  ' "$AID_PR_ROLES_SKILL"
}

# aid_plan_review_prompt_render <role> <round> <round_dir>
#   Renders the template for one role through aid-render-prompt.sh, then appends
#   the packet. The plan is appended, never passed as a variable: the renderer
#   refuses a value containing `{{`, and a plan may legitimately contain one.
aid_plan_review_prompt_render() {
  local role="$1" round="$2" dir="$3" section vars out
  section="$(aid_plan_review_role_section "$role")"
  [[ -n "$section" ]] || { echo "prepare: role ${role} has no section in ${AID_PR_ROLES_SKILL}" >&2; return 1; }
  vars="${dir}/vars-${role}.json"; out="${dir}/prompt-${role}.md"
  local note=""
  (( round >= 2 )) && note="This is a confirmation round: the packet below carries the findings still open and the author's diff."
  jq -n --arg s "$section" --arg r "$round" --arg o "${dir}/reviewer-${role}.json" \
        --arg e "$AID_PR_EVIDENCE_FORMS" --arg n "$note" \
    '{role_section: $s, checkpoint: "cp1", round: $r, output_path: $o, evidence_forms: $e,
      packet_name: "an implementation plan, reviewed BEFORE any code exists", confirmation_note: $n}' > "$vars"
  bash "${_AID_PR_PLUGIN}/scripts/lib/aid-render-prompt.sh" \
    --template "$AID_PR_TEMPLATE" --vars-json "$vars" --output "$out" >/dev/null || {
      echo "prepare: prompt for ${role} did not render" >&2; rm -f "$out"; return 1; }
  {
    echo
    echo "--- PACKET ---"
    echo
    local prev="${dir%/round-*}/round-$((round - 1))"
    if (( round >= 2 )) && [[ -f "${prev}/merged.json" ]]; then
      echo "## This is a confirmation round"
      echo
      echo "The author fixed the plan after round $((round - 1)). Your job now:"
      echo "1. For each finding below, check the current plan: if it is fixed, do not report it; if it is not, report it again (same claim)."
      echo "2. Report NEW problems only when the changed lines (the diff below) introduced them. Do not review the rest of the plan again."
      echo
      echo "### Findings still open after round $((round - 1))"
      jq -r '.findings[] | select(.status != "fixed" and (.severity == "blocker" or .severity == "major"))
             | "- [\(.severity)] step \(.step // "plan"): \(.claim) (evidence: \(.evidence); fix asked: \(.fix))"' "${prev}/merged.json"
      echo
      echo "### What the author changed (diff of plan.md, round $((round - 1)) → round ${round})"
      echo '```diff'
      diff -u "${prev}/packet/plan.md" "${dir}/packet/plan.md" | tail -n +3
      echo '```'
      echo
    fi
    echo "## Deterministic plan check: warnings (already reported, do not repeat)"
    jq -r '.warnings[]? | "- \(.id) \(.location): \(.message)"' "${dir}/packet/plan-check.json"
    echo
    echo "## Standards"
    cat "${dir}/packet/standards.md"
    echo
    echo "## plan.md (also on disk: ${dir}/packet/plan.md; cite it as plan.md:<line>)"
    awk '{ printf "%5d  %s\n", NR, $0 }' "${dir}/packet/plan.md"
  } >> "$out"
}

# aid_plan_review_unfence <in> <out> — a reviewer that wraps its JSON in a
# markdown fence has still answered; the fence lines are dropped.
aid_plan_review_unfence() {
  sed -e 's/^```json$//' -e 's/^```$//' "$1" > "$2"
}

# aid_plan_review_answer_error <answer.json> [<checkpoint>]
#   The SHAPE of an answer: an object with a known role (the roles of the
#   checkpoint: cp1 or absent → $defs.roles_cp1, cp2/cp3/cp6 → $defs.roles_step),
#   a findings array (or a no_findings_reason) and findings that carry id, step,
#   severity, claim and fix. Prints the first rule the answer breaks and returns 1, or returns 0.
#   Whether each finding has a read-only command and a path:line evidence is
#   judged per finding by the adjudicator (aid_plan_review_proof_jq), so one unproven finding
#   rejects that finding, not the reviewer's whole answer.
aid_plan_review_answer_error() {
  local file="$1" cp="${2:-cp1}" err
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "not valid JSON"; return 1
  fi
  err="$(jq -r --slurpfile s "$AID_PR_SCHEMA" --arg cp "$cp" '
    ($s[0]) as $schema
    | (if $cp == "cp1" then $schema["$defs"].roles_cp1.enum else $schema["$defs"].roles_step.enum end) as $roles
    | ($schema["$defs"].finding.properties) as $f
    | ($schema.properties | keys) as $top_keys
    | ($f | keys) as $fkeys
    | ["id", "step", "severity", "claim", "fix"] as $shape_keys
    | def finding_error:
        if type != "object" then "finding is not an object" else
        . as $x
        | ($x.id // "?") as $id
        | [$shape_keys[] as $k | select($x | has($k) | not) | $k] as $missing
        | if ($missing | length) > 0 then "\($id): missing \($missing | join(", "))"
          elif ((keys - $fkeys) | length) > 0 then "\($id): unknown key \((keys - $fkeys) | join(", "))"
          elif (.step | (type == "null" or (type == "number" and . == floor)) | not) then "\($id): step must be an integer or null"
          elif (.severity | IN($f.severity.enum[]) | not) then "\($id): severity must be blocker, major or minor"
          elif ([.id, .claim, .fix] | map(type == "string" and test("\\S")) | all | not) then "\($id): id, claim and fix must be non-empty strings"
          elif ([.command, .evidence] | map(. == null or type == "string") | all | not) then "\($id): command and evidence must be strings"
          else empty end end;
      if type != "object" then "answer is not a JSON object"
      elif ((keys - $top_keys) | length) > 0 then "unknown key \((keys - $top_keys) | join(", "))"
      elif (.role | IN($roles[]) | not) then "role must be one of \($roles | join(", "))"
      elif (.findings | type) != "array" then "findings must be an array"
      elif (.findings | length) == 0 and ((.no_findings_reason // "") == "") then "no_findings_reason is required when findings is empty"
      else first(.findings[] | finding_error) // empty end
  ' "$file" 2>&1)" || { echo "answer check failed: ${err}"; return 1; }
  [[ -z "$err" ]] && return 0
  echo "$err"; return 1
}

# aid_plan_review_proof_jq — a jq definition, `proof_error`, applied to one
# finding with the schema slurped as $s: "missing_command", "missing_evidence"
# or empty. The two patterns are read from the schema, never restated here.
aid_plan_review_proof_jq() {
  cat <<'JQ'
def proof_error:
  ($s[0]["$defs"].finding.properties) as $f
  | if ((.command // "") | test($f.command.pattern) | not) then "missing_command"
    elif ((.evidence // "") | test($f.evidence.pattern) | not) then "missing_evidence"
    else empty end;
JQ
}
