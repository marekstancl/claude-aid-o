#!/usr/bin/env bats
# aid-tier: t2
# test-auto-recovery-policy.bats — P076 EPIC 2, Step 11.
#
# The shipped AUTO-mode recovery policy is a POLICY, not code: nothing reads it
# at this commit. That makes it exactly the artefact AID's first principle warns
# about — "a detector without enforcement is decoration"
# (docs/plans/AID-v3-principles.md §1). This suite is the enforcement that keeps
# it honest until the ladder runtime lands:
#
#   1.  the shipped policy validates against its own shipped schema
#   2.  ANTI-DECORATION — every `emitter` anchor named in the policy greps to a
#       real code site in this repository, at the file it claims
#   3.  the emitter line numbers are still in the right neighbourhood (advisory
#       drift signal — the anchor is what case 2 actually binds)
#   4.  DRIFT — every `existing_loops` budget is RE-READ from the file it cites
#       and compared to the declared value (no number is written twice here)
#   5.  the three budgets the P076 plan names by value are the values found
#   6.  UNCLASSIFIED has no allowed action at all, and no emitter
#   7.  every allowed action across all classes is one of the six vocabulary
#       names, and every vocabulary name is reachable by the schema enum
#   8.  an unknown action name is a SCHEMA ERROR, never a silent no-op
#   9.  the honesty axes, checked against the REPOSITORY rather than against
#       the policy's own say-so: whether the ladder is wired is DERIVED from a
#       real loader function existing in code, and the policy's `status`,
#       `implemented` and per-class `live` claims must all agree with that
#  10.  aid-run.md no longer points the tier rule at nonexistent permissions
#       keys, and the only permissions key it names is one that really exists
#  11.  the supersede claim about the July stop-taxonomy doc is carried by the
#       SHIPPED policy (always checked — this case cannot skip)
#  12.  and, where the untracked July doc is reachable, its markers really do
#       sit in those sections and nowhere else
#
# WHY 11 AND 12 ARE SEPARATE — a skip is green, and green must never mean
# "checked nothing". `docs/` is gitignored in this repository, so the July doc
# is untracked: absent from the commit, from a clone, from CI and from a plan
# worktree. The earlier single case skipped there and still reported success,
# so AC 3 was unenforced everywhere except the author's own machine. The
# checkable part therefore MOVED onto an artefact that ships — `supersedes` in
# auto-recovery.yaml — which case 11 asserts unconditionally and fails closed.
# Case 12 is the doc-side cross-check; it fails (does not skip) whenever the
# document COULD be there, and where it genuinely cannot be it says in plain
# words that it did not run.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  POLICY="$PLUGIN_ROOT/defaults/policies/auto-recovery.yaml"
  export POLICY
  SCHEMA="$PLUGIN_ROOT/defaults/schemas/auto-recovery.schema.json"
  export SCHEMA
  AID_RUN_MD="$PLUGIN_ROOT/commands/aid-run.md"
  export AID_RUN_MD

  WORK="$(mktemp -d)"
  export WORK
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

_have_jsonschema() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' >/dev/null 2>&1
}

# validate_json <schema> <instance> — prints every error, rc 1 iff any.
validate_json() {
  python3 - "$1" "$2" <<'PY'
import json, sys
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
errs = sorted(Draft202012Validator(schema).iter_errors(inst), key=lambda e: list(e.path))
for e in errs:
    print(f"{list(e.path)}: {e.message}")
sys.exit(1 if errs else 0)
PY
}

# policy_json — the shipped YAML as JSON, derived (never a hand-written copy).
policy_json() {
  yq -o=json '.' "$POLICY" > "$WORK/policy.json"
  echo "$WORK/policy.json"
}

# main_tree — the working tree that owns the git COMMON dir. A plan worktree
# does not carry gitignored paths like docs/, the main tree does.
main_tree() {
  local common
  common="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] || return 1
  dirname "$common"
}

# resolve_doc <repo-relative-path> — absolute path of an untracked document,
# here or in the main tree. rc 1 when it is nowhere; the CALLER decides whether
# that is a skip or a failure (case 12 fails whenever it could have been there).
resolve_doc() {
  local name="$1" main
  if [[ -f "$REPO_ROOT/$name" ]]; then echo "$REPO_ROOT/$name"; return 0; fi
  main="$(main_tree)" || return 1
  [[ -f "$main/$name" ]] || return 1
  echo "$main/$name"
}

# ladder_wired_from_code — is the ladder wired? Answered from the REPOSITORY,
# never from the policy. The policy names a loader path and the shell function
# that loader defines; this returns `yes` only when that function is really
# defined, in that file, in a file that really reads this policy. A policy edit
# alone cannot make it true: to claim `wired` you must write the loader. A test
# file cannot stand in for it either (the schema's loader_path pattern refuses
# scripts/tests/, and this refuses it a second time).
ladder_wired_from_code() {
  local json="$1" path anchor abs
  path="$(jq -r '.loader_contract.loader_path // ""' "$json")"
  anchor="$(jq -r '.loader_contract.loader_anchor // ""' "$json")"
  [[ -n "$path" && -n "$anchor" ]]                || { echo no; return 0; }
  [[ "$path" == plugins/aid-orchestrator/scripts/* ]] || { echo no; return 0; }
  [[ "$path" != */tests/* ]]                      || { echo no; return 0; }
  abs="$REPO_ROOT/$path"
  [[ -f "$abs" ]]                                 || { echo no; return 0; }
  grep -qE "^[[:space:]]*(function[[:space:]]+)?${anchor}[[:space:]]*\(\)[[:space:]]*\{?" "$abs" \
                                                  || { echo no; return 0; }
  grep -qF 'auto-recovery.yaml' "$abs"            || { echo no; return 0; }
  echo yes
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: the shipped policy validates against the shipped schema" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  run validate_json "$SCHEMA" "$(policy_json)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "case 2: ANTI-DECORATION — every emitter anchor greps to a real code site" {
  local json; json="$(policy_json)"
  local n; n="$(jq '[.stop_classes[].emitter[]] | length' "$json")"
  # Six classes carry emitters; UNCLASSIFIED has none by construction.
  [ "$n" -ge 6 ]

  local failures="" checked=0
  while IFS=$'\t' read -r cls file anchor; do
    [[ -z "$cls" ]] && continue
    checked=$(( checked + 1 ))
    local abs="$REPO_ROOT/$file"
    if [[ ! -f "$abs" ]]; then
      failures+=$'\n'"  ${cls}: emitter file does not exist: ${file}"
      continue
    fi
    if ! grep -qF -- "$anchor" "$abs"; then
      failures+=$'\n'"  ${cls}: anchor NOT FOUND in ${file}: ${anchor}"
    fi
  done < <(jq -r '.stop_classes | to_entries[] | .key as $k
                  | .value.emitter[] | [$k, .file, .anchor] | @tsv' "$json")

  [ "$checked" -ge 6 ]
  [[ -z "$failures" ]] || { echo "emitters that do not name live code:$failures"; false; }
}

@test "case 3: emitter line numbers still point near their anchor" {
  local json; json="$(policy_json)"
  local drift=""
  while IFS=$'\t' read -r cls file line anchor; do
    [[ -z "$cls" ]] && continue
    local abs="$REPO_ROOT/$file" found
    found="$(grep -nF -- "$anchor" "$abs" | head -1 | cut -d: -f1)"
    [[ -n "$found" ]] || { drift+=$'\n'"  ${cls}: anchor missing entirely (case 2 owns that)"; continue; }
    local delta=$(( found > line ? found - line : line - found ))
    (( delta <= 5 )) || drift+=$'\n'"  ${cls}: ${file} declares line ${line}, anchor is at ${found}"
  done < <(jq -r '.stop_classes | to_entries[] | .key as $k
                  | .value.emitter[] | [$k, .file, .line, .anchor] | @tsv' "$json")
  [[ -z "$drift" ]] || { echo "emitter line drift:$drift"; false; }
}

@test "case 4: DRIFT — every existing_loops budget matches the live value in its cited file" {
  local json; json="$(policy_json)"
  local n; n="$(jq '.existing_loops | length' "$json")"
  [ "$n" -ge 5 ]

  local failures="" checked=0
  while IFS=$'\t' read -r id kind key value file line; do
    [[ -z "$id" ]] && continue
    checked=$(( checked + 1 ))
    local abs="$REPO_ROOT/$file" live=""
    if [[ ! -f "$abs" ]]; then
      failures+=$'\n'"  ${id}: budget_file does not exist: ${file}"
      continue
    fi
    case "$kind" in
      policy_key)
        # Re-read the key from the YAML itself, not from the cited line.
        live="$(yq -r ".${key} // \"\"" "$abs" 2>/dev/null || true)"
        [[ "$live" == "null" ]] && live=""
        ;;
      shell_constant)
        live="$(grep -Eo "^${key}=[0-9]+" "$abs" | head -1 | cut -d= -f2)"
        ;;
      shell_default)
        # `yq ".gates.\"${gate_name}\".max_retries // 1"` — the default after `//`.
        live="$(grep -Eo '\.max_retries // [0-9]+' "$abs" | head -1 | grep -Eo '[0-9]+$')"
        ;;
      instruction)
        # The number is stated in prose on the cited line: "max 3 cycles per check".
        live="$(sed -n "${line}p" "$abs" | grep -Eo 'max ([0-9]+) cycles per check' | grep -Eo '[0-9]+')"
        ;;
      *)
        failures+=$'\n'"  ${id}: unknown budget_kind ${kind}"
        continue
        ;;
    esac
    if [[ -z "$live" ]]; then
      failures+=$'\n'"  ${id}: could not re-read ${key} out of ${file} (kind ${kind}) — the citation is stale"
    elif [[ "$live" != "$value" ]]; then
      failures+=$'\n'"  ${id}: policy declares ${value}, ${file} says ${live} (key ${key})"
    fi
  done < <(jq -r '.existing_loops[] | [.id, .budget_kind, .budget_key, .budget_value, .budget_file, .budget_line] | @tsv' "$json")

  [ "$checked" -ge 5 ]
  [[ -z "$failures" ]] || { echo "ownership-table drift:$failures"; false; }
}

@test "case 5: the three budgets the plan names by value are the values found live" {
  # These are read out of the SOURCE files, never out of the policy — the
  # policy's own agreement with them is case 4's job. This case pins the three
  # numbers the P076 plan states in prose (C3 4, ledger 5, gate fix 3), so a
  # change to any of them surfaces as a decision rather than as silence.
  local c3 ledger gatefix
  c3="$(yq -r '.c3_fix_loop.max_rechecks' "$PLUGIN_ROOT/defaults/policies/c3-audit-policy.yaml")"
  ledger="$(grep -Eo '^MAX_ATTEMPTS=[0-9]+' "$PLUGIN_ROOT/scripts/lib/aid-cp1-ledger.sh" | head -1 | cut -d= -f2)"
  gatefix="$(grep -Eo 'max ([0-9]+) cycles per check' "$PLUGIN_ROOT/skills/pipeline.md" | head -1 | grep -Eo '[0-9]+')"
  [ "$c3" = "4" ]     || { echo "c3_fix_loop.max_rechecks is now '$c3', plan says 4"; false; }
  [ "$ledger" = "5" ] || { echo "aid-cp1-ledger.sh MAX_ATTEMPTS is now '$ledger', plan says 5"; false; }
  [ "$gatefix" = "3" ]|| { echo "pipeline.md gate fix loop is now '$gatefix', plan says 3"; false; }
}

@test "case 6: UNCLASSIFIED has no allowed action and no emitter — it adjudicates" {
  local json; json="$(policy_json)"
  [ "$(jq '.stop_classes.UNCLASSIFIED.allowed_actions | length' "$json")" -eq 0 ]
  [ "$(jq '.stop_classes.UNCLASSIFIED.emitter | length' "$json")" -eq 0 ]
  [ "$(jq -r '.stop_classes.UNCLASSIFIED.terminus[0]' "$json")" = "adjudicate" ]
  # And every class ends the same way — the terminus is not shortenable.
  local bad
  bad="$(jq -r '.stop_classes | to_entries[]
                | select((.value.terminus | join(">")) != "adjudicate>escalation>pm_force")
                | .key' "$json")"
  [[ -z "$bad" ]] || { echo "classes with a non-standard terminus: $bad"; false; }
}

@test "case 7: allowed actions and the vocabulary are the same closed set of six" {
  local json; json="$(policy_json)"
  [ "$(jq '.action_vocabulary | length' "$json")" -eq 6 ]
  # every used action is defined
  local undefined
  undefined="$(jq -r '[.stop_classes[].allowed_actions[]] - (.action_vocabulary | keys) | .[]' "$json")"
  [[ -z "$undefined" ]] || { echo "actions used but not defined: $undefined"; false; }
  # every defined action has a schema enum slot (a vocabulary entry the schema
  # would reject is unreachable, i.e. decoration)
  local enum_missing
  enum_missing="$(python3 - "$SCHEMA" "$json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
policy = json.load(open(sys.argv[2]))
enum = set(schema["$defs"]["allowed_actions"]["items"]["enum"])
print(" ".join(sorted(set(policy["action_vocabulary"]) - enum)))
PY
)"
  [[ -z "$enum_missing" ]] || { echo "vocabulary entries the schema enum cannot express: $enum_missing"; false; }
}

@test "case 8: an unknown action name is a SCHEMA ERROR, never a silent no-op" {
  _have_jsonschema || skip "python3 + jsonschema unavailable"
  local json; json="$(policy_json)"
  jq '.stop_classes.GATE_TIMEOUT.allowed_actions += ["force_merge"]' "$json" > "$WORK/bad.json"
  run validate_json "$SCHEMA" "$WORK/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"force_merge"* ]] || { echo "$output"; false; }
}

@test "case 9: the wired/not-wired answer comes from CODE, and every claim must match it" {
  local json; json="$(policy_json)"

  # Both axes are present and constrained on every class.
  local missing
  missing="$(jq -r '.stop_classes | to_entries[]
                    | select((.value.detector | type) != "string"
                             or (.value.ladder_entry | type) != "string"
                             or (.value.ladder_entry_status | type) != "string")
                    | .key' "$json")"
  [[ -z "$missing" ]] || { echo "classes missing an honesty axis: $missing"; false; }

  # THE DERIVED ANSWER. Read out of the repository, not out of the policy.
  local derived expect_status expect_impl
  derived="$(ladder_wired_from_code "$json")"
  if [[ "$derived" == "yes" ]]; then expect_status="wired"; expect_impl="true"
  else                               expect_status="not_wired"; expect_impl="false"; fi

  # 1. The declared status must agree with code — in BOTH directions. Claiming
  #    `wired` without a loader is red; shipping a loader and still saying
  #    `not_wired` is red too.
  local declared; declared="$(jq -r '.ladder_runtime.status' "$json")"
  [[ "$declared" == "$expect_status" ]] || {
    echo "ladder_runtime.status says '${declared}', the repository says '${expect_status}'"
    echo "  loader_path:   $(jq -r '.loader_contract.loader_path // "(unset)"' "$json")"
    echo "  loader_anchor: $(jq -r '.loader_contract.loader_anchor // "(unset)"' "$json")"
    echo "  (the loader function must be DEFINED in that file, and that file must read auto-recovery.yaml)"
    false; }

  # 2. Same for the loader contract's own flag.
  local impl; impl="$(jq -r '.loader_contract.implemented' "$json")"
  [[ "$impl" == "$expect_impl" ]] || {
    echo "loader_contract.implemented says '${impl}', the repository says '${expect_impl}'"; false; }

  # 3. UNCONDITIONAL — this no longer hides behind the policy's own status.
  #    No class may claim a live ladder entry while no ladder writer exists.
  if [[ "$derived" != "yes" ]]; then
    local lying
    lying="$(jq -r '.stop_classes | to_entries[]
                    | select(.value.ladder_entry_status == "live") | .key' "$json")"
    [[ -z "$lying" ]] || {
      echo "no ladder loader exists in this repository, but these classes claim a live entry: $lying"
      false; }
  fi
}

@test "case 10: aid-run.md no longer points at nonexistent permissions keys" {
  # The exact dead reference this step replaced.
  run grep -n "default decision from \`config/permissions.yaml\`" "$AID_RUN_MD"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  # And the other invented key names.
  run grep -nE "auto-approve rules|permissions\.yaml.*\bmode\b, " "$AID_RUN_MD"
  [ "$status" -ne 0 ] || { echo "$output"; false; }

  # The tier rule now names the real defaults authority, and that file ships.
  grep -q "auto-recovery.yaml" "$AID_RUN_MD"
  [ -f "$POLICY" ]

  # `autonomous_mode` is the ONE permissions key aid-run.md still names, and it
  # is a key something really reads.
  grep -q "autonomous_mode" "$AID_RUN_MD"
  grep -q "autonomous_mode" "$PLUGIN_ROOT/scripts/aid-release-policy.sh"
}

@test "case 11: the supersede claim ships in the policy — this case cannot skip" {
  local json; json="$(policy_json)"

  # The record for the July doc exists in the shipped, diff-reviewable artefact.
  local doc="docs/plans/2026-07-21-IMP-auto-mode-stop-taxonomy-and-recovery-policy.md"
  local n
  n="$(jq --arg d "$doc" '[.supersedes[] | select(.document == $d)] | length' "$json")"
  [ "$n" -eq 1 ] || { echo "expected exactly one supersedes record for ${doc}, found ${n}"; false; }

  # The three sections P076 replaced or partially delivered, pinned HERE so the
  # doc-side case cannot be satisfied by editing the policy to match a drifted
  # document.
  local expected="## What Codex may decide without PM
## Stop classes for the adjudicator
## Deferred: heavy mechanical recovery framework"
  local declared
  declared="$(jq -r --arg d "$doc" '.supersedes[] | select(.document == $d) | .sections[]' "$json")"
  [[ "$(echo "$declared" | sort)" == "$(echo "$expected" | sort)" ]] || {
    echo "supersedes.sections:"; echo "$declared"; echo "expected:"; echo "$expected"; false; }

  # `tracked` is checked against GIT, not believed. Saying an untracked
  # document is tracked (or forgetting to update this when it becomes tracked)
  # is red either way.
  local git_tracked="false"
  git -C "$REPO_ROOT" ls-files --error-unmatch -- "$doc" >/dev/null 2>&1 && git_tracked="true"
  local claimed
  claimed="$(jq -r --arg d "$doc" '.supersedes[] | select(.document == $d) | .tracked' "$json")"
  [[ "$claimed" == "$git_tracked" ]] || {
    echo "supersedes.tracked says '${claimed}', git says '${git_tracked}' for ${doc}"; false; }

  # An untracked supersede must state why — silence about a claim that does not
  # ship is the exact failure this record exists to prevent.
  if [[ "$git_tracked" == "false" ]]; then
    local reason
    reason="$(jq -r --arg d "$doc" '.supersedes[] | select(.document == $d) | .tracked_reason // ""' "$json")"
    [[ -n "$reason" ]] || { echo "untracked supersede with no tracked_reason"; false; }
  fi
}

@test "case 12: [MAY NOT RUN — untracked doc] markers sit ONLY in the superseded sections" {
  local json; json="$(policy_json)"
  local doc="docs/plans/2026-07-21-IMP-auto-mode-stop-taxonomy-and-recovery-policy.md"
  local marker
  marker="$(jq -r --arg d "$doc" '.supersedes[] | select(.document == $d) | .marker_pattern' "$json")"
  local expected
  expected="$(jq -r --arg d "$doc" '.supersedes[] | select(.document == $d) | .sections[]' "$json")"

  local path
  if ! path="$(resolve_doc "$doc")"; then
    # FAIL CLOSED wherever the document could have been here. Only a tree that
    # cannot host it at all — a clone, CI, a plan worktree — is allowed to not
    # run this, and it says so in words no summary line can soften.
    local main hostable=""
    main="$(main_tree || true)"
    [[ -d "$REPO_ROOT/$(dirname "$doc")" ]] && hostable="$REPO_ROOT/$(dirname "$doc")"
    [[ -z "$hostable" && -n "$main" && -d "$main/$(dirname "$doc")" ]] && hostable="$main/$(dirname "$doc")"
    if [[ -n "$hostable" ]]; then
      echo "${hostable} exists, so this tree CAN hold the superseded document — but ${doc} is not there."
      echo "A tree that can host the document must have it: refusing to pass without checking."
      false
    fi
    skip "DID NOT RUN, NOTHING WAS CHECKED HERE: ${doc} is untracked (docs/ is gitignored) and absent from this tree. AC3's doc-side half is unverifiable here; the half that ships is case 11."
  fi

  # Walk the doc, attributing every marker line to the ## section it is in.
  local marked
  marked="$(awk -v m="$marker" '
    /^## / { section = $0 }
    index($0, m) && /^> \*\*/ { if (section != "" && !(section in seen)) { seen[section]=1; print section } }
  ' "$path")"

  [[ "$(echo "$marked" | sort)" == "$(echo "$expected" | sort)" ]] || {
    echo "sections carrying a ${marker} supersede marker:"; echo "$marked"
    echo "expected:"; echo "$expected"; false; }

  # And the untouched sections really are untouched: no mention anywhere
  # outside those sections, marker or not.
  local strays
  strays="$(awk -v want="$expected" -v m="$marker" '
    BEGIN { n = split(want, a, "\n"); for (i=1; i<=n; i++) ok[a[i]] = 1 }
    /^## / { section = $0 }
    index($0, m) { if (!(section in ok)) print FNR ": " section " :: " $0 }
  ' "$path")"
  [[ -z "$strays" ]] || { echo "${marker} mentions in untouched sections:"; echo "$strays"; false; }
}
