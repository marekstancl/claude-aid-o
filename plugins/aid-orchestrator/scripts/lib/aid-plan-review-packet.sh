#!/usr/bin/env bash
# aid-plan-review-packet.sh — what goes to a plan reviewer and what comes back.
#
# Out: the packet every reviewer of a round receives (plan snapshot, the
# deterministic check's report, the project standards) and the rendered prompt.
# In: the reviewer's answer file, checked against
# defaults/schemas/plan-review-finding.schema.json.
#
# The answer check reads the role list and the two patterns (command, evidence)
# from the schema file itself, so the schema is the one source of the contract.
# Sourced by scripts/aid-plan-review-round.sh; tested by
# scripts/tests/bats/test-plan-review-schema.bats and test-plan-review-round.bats.

_AID_PR_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AID_PR_SCHEMA="${_AID_PR_PLUGIN}/defaults/schemas/plan-review-finding.schema.json"

# aid_plan_review_unfence <in> <out> — a reviewer that wraps its JSON in a
# markdown fence has still answered; the fence lines are dropped.
aid_plan_review_unfence() {
  sed -e 's/^```json$//' -e 's/^```$//' "$1" > "$2"
}

# aid_plan_review_answer_error <answer.json>
#   Prints the first rule the answer breaks and returns 1; prints nothing and
#   returns 0 for a valid answer.
aid_plan_review_answer_error() {
  local file="$1" err
  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "not valid JSON"; return 1
  fi
  err="$(jq -r --slurpfile s "$AID_PR_SCHEMA" '
    ($s[0]) as $schema
    | ($schema.properties.role.enum) as $roles
    | ($schema["$defs"].finding.properties) as $f
    | ($schema.properties | keys) as $top_keys
    | ($schema["$defs"].finding.required) as $fkeys
    | def finding_error:
        if type != "object" then "finding is not an object" else
        . as $x
        | ($x.id // "?") as $id
        | [$fkeys[] as $k | select($x | has($k) | not) | $k] as $missing
        | if ($missing | length) > 0 then "\($id): missing \($missing | join(", "))"
          elif ((keys - $fkeys) | length) > 0 then "\($id): unknown key \((keys - $fkeys) | join(", "))"
          elif (.step | (type == "null" or (type == "number" and . == floor)) | not) then "\($id): step must be an integer or null"
          elif (.severity | IN($f.severity.enum[]) | not) then "\($id): severity must be blocker, major or minor"
          elif ([.id, .claim, .fix] | map(type == "string" and length > 0) | all | not) then "\($id): id, claim and fix must be non-empty strings"
          elif ((.command | type) != "string" or (.command | test($f.command.pattern) | not)) then "\($id): command is not a read-only command (\(.command))"
          elif ((.evidence | type) != "string" or (.evidence | test($f.evidence.pattern) | not)) then "\($id): evidence must be path:line (\(.evidence))"
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
