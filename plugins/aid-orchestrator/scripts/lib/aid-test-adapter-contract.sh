#!/usr/bin/env bash
# aid-test-adapter-contract.sh — P066 Step 2/3.
#
# Shared interface every test-portfolio adapter (Bats, package-script,
# declared-command — Steps 2-3) implements against. Sourced, never executed
# directly. NO top-level `set -e`/`set -euo pipefail` (matches
# aid-gate-runtime-baseline.sh/aid-gate-profile.sh convention): callers source
# this under their OWN `set -euo pipefail` shell, and an unguarded non-zero
# return here must never kill the caller's shell.
#
# Every function here is a pure helper: no network, no test execution, no
# writes outside stdout. Discovery adapters (aid-test-adapter-*.sh) call these
# to build schema-valid run_unit JSON objects; they never hand-roll the JSON
# shape themselves, so a schema field never drifts between adapters.

# adapter_supports_list_mode <runner> — echoes "true"/"false".
# Bats 1.8.2 (the version this repo has installed) has no --list flag — only
# -c/--count and -f/--filter — so static @test parsing is the supported path,
# never a "fallback". A future Bats version verified to expose a real
# enumerate interface may flip this, version-gated, never assumed present.
adapter_supports_list_mode() {
  local runner="$1"
  case "$runner" in
    bats) echo "false" ;;
    *) echo "false" ;;
  esac
}

# adapter_supports_filter <runner> — echoes "true"/"false".
adapter_supports_filter() {
  local runner="$1"
  case "$runner" in
    bats) echo "true" ;;
    *) echo "false" ;;
  esac
}

# adapter_validate_audit_id <audit_id> — the ONE canonical, fail-closed
# audit_id format shared by every script that builds a filesystem path from
# it (aid-test-audit-state.sh, aid-test-audit-dispatch.sh, ...). Only
# `[A-Za-z0-9_-]`, non-empty — this already excludes `/`, `..`, and
# whitespace, so a validated audit_id can never escape
# `.aid-o/work/test-audits/<audit_id>/` via path traversal. PM-confirmed
# blocker: `--audit-id '../escape'` previously passed straight through into
# a manifest's artifact_path.
adapter_validate_audit_id() {
  local id="$1"
  [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]]
}

# adapter_json_escape <text> — minimal, pure-bash JSON string escaping
# (backslash, double-quote, newline, tab). PM feedback (performance): avoids
# a jq subprocess spawn (jq's own process-startup cost dominates wall-clock
# time at portfolio scale) for the extremely common case of wrapping ONE
# already-known-shape string (a relative file path) into a JSON string
# literal. Deliberately narrow — NOT a general-purpose JSON encoder (no
# control-character range beyond \n/\t, no unicode escaping): safe for the
# file paths and @test names this contract actually handles, never used for
# arbitrary/untrusted content.
adapter_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# adapter_slug <text> — lowercase, non-alnum runs collapsed to a single "-",
# leading/trailing "-" trimmed. Used for test_case_id, never for run_unit_id
# (which is a pure function of {runner, file path} only). A title made
# entirely of punctuation/non-ASCII characters (e.g. `@test "!!!"`) would
# otherwise slug to an empty string, violating the catalog schema's
# minLength:1 on test_case_id — falls back to a content hash in that case.
adapter_slug() {
  local text="$1" slug
  slug="$(printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$slug" ]]; then
    slug="tc-$(printf '%s' "$text" | sha256sum | cut -c1-12)"
  fi
  printf '%s' "$slug"
}

# adapter_run_unit_json <run_unit_id> <runner> <command_json> <test_cases_json>
#   [source_paths_json] [confidence]
#   Emits one schema-valid run_units[] entry (test-catalog.schema.json) to
#   stdout, with safe closed-enum defaults for every field a Wave-0 scanner
#   cannot yet know (parallel.status: unknown, recommendation: keep,
#   isolation left at "unknown"/empty). Later steps (Step 4's lock-usage
#   grep, Step 11's specialist findings) refine these fields — this helper
#   never invents a non-default value on their behalf.
#
#   <command_json> and <test_cases_json> must be valid JSON (object / array
#   literals respectively) — callers build these with jq themselves.
adapter_run_unit_json() {
  local run_unit_id="$1" runner="$2" command_json="$3" test_cases_json="$4"
  local source_paths_json="${5:-[]}" confidence="${6:-low}" provenance_json="${7:-null}"

  local fingerprint
  fingerprint="$(adapter_command_fingerprint "$run_unit_id" "$command_json")" || return 1

  jq -n \
    --arg run_unit_id "$run_unit_id" \
    --arg runner "$runner" \
    --argjson source_paths "$source_paths_json" \
    --arg confidence "$confidence" \
    --argjson command "$command_json" \
    --arg fingerprint "$fingerprint" \
    --argjson test_cases "$test_cases_json" \
    --argjson provenance "$provenance_json" \
    '{
      run_unit_id: $run_unit_id,
      runner: $runner,
      source_paths: $source_paths,
      production_surfaces: $source_paths,
      test_level: "suite",
      risk_tags: [],
      profiles: ["default"],
      behavior_claims: [],
      confidence: $confidence,
      command: $command,
      runtime: { fingerprint: $fingerprint },
      parallel: { status: "unknown", exclusive_resources: [], max_workers: null, internal_parallelism: false },
      isolation: { temp_workspace: "unknown", fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: "static_parse" },
      recommendation: "keep",
      test_cases: $test_cases
    }
    + (if $provenance == null then {} else {provenance: $provenance} end)'
}

# adapter_check_run_unit_id_collisions <run_units_json>
#   Echoes a newline-separated list of run_unit_ids that appear more than
#   once in the array (empty output = no collision). Two adapters claiming
#   the same stable run_unit_id is a hard scanner failure (Step 4) — this
#   helper is the shared detection primitive, never a per-adapter reimpl.
adapter_check_run_unit_id_collisions() {
  local units_json="$1"
  jq -r '[.[].run_unit_id] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$units_json"
}

# adapter_command_fingerprint <run_unit_id> <canonical_command_json>
#   Echoes gate_baseline_fingerprint(run_unit_id, canonical_command_json).
#   PM feedback (E1 re-review, performance): this used to re-canonicalize
#   (`jq -cS`) on every call — a full extra jq subprocess spawn per
#   run_unit, which dominates wall-clock time in this environment (jq's own
#   process-startup cost, ~30ms+, far outweighs its actual work). The
#   CONTRACT is now that <canonical_command_json> is ALREADY `jq -cS`
#   (compact, sorted-object-keys) form — every adapter builds its command
#   object with `jq -ncS` from the start (see aid-test-adapter-bats.sh),
#   so the value stored IS the canonical form, never re-derived. Never
#   argv-joined-with-spaces, which cannot distinguish ["a","b c"] from
#   ["a b","c"]. Reuses the real, existing gate_baseline_fingerprint function
#   (lib/aid-gate-runtime-baseline.sh:251) — no reimplemented hashing scheme.
adapter_command_fingerprint() {
  local run_unit_id="$1" canonical_command_json="$2"
  gate_baseline_fingerprint "$run_unit_id" "$canonical_command_json"
}

# ─── Linear (NDJSON-buffered) array accumulation ────────────────────────────
# PM feedback (E1 re-review): repeated `jq -c --argjson u "$unit" '. + [$u]'
# re-parses AND re-serializes the WHOLE growing array on every single append
# — O(n) work per item, O(n^2) total across a file/portfolio scan. Every
# adapter's discovery loop instead appends each new unit as its own line to
# an NDJSON buffer (each append is O(1) in the array's current size) and
# calls adapter_ndjson_finish exactly ONCE at the end to produce the final
# JSON array — O(n) total.

# adapter_ndjson_start — echoes a fresh temp file path to buffer into.
adapter_ndjson_start() { mktemp; }

# adapter_ndjson_append <ndjson_file> <json_value>
adapter_ndjson_append() {
  local ndjson_file="$1" json_value="$2"
  printf '%s\n' "$json_value" >> "$ndjson_file"
}

# adapter_ndjson_finish <ndjson_file> — emits the final JSON array (one jq
# slurp pass, O(n) total, never O(n^2)) and removes the temp buffer.
adapter_ndjson_finish() {
  local ndjson_file="$1"
  if [[ ! -s "$ndjson_file" ]]; then
    rm -f "$ndjson_file" 2>/dev/null
    echo "[]"
    return 0
  fi
  jq -cs '.' "$ndjson_file"
  rm -f "$ndjson_file" 2>/dev/null
}

# adapter_shebang_runner <file> — echoes `bats`, `shell`, or `none`.
#
# THE single classification rule, shared by the bats and shell-suite adapters
# so they cannot disagree about who owns a file. A file classified `bats` here
# is run with `bats`; `shell` with `bash`; `none` is not a suite.
#
# It parses the interpreter rather than substring-matching, because a
# substring rule claims `#!/bin/batsman`, `#!/bin/sh bats` and
# `#!/bin/bash # bats` as Bats suites — all three would then be executed with
# the wrong runner.
#
# NOTE on run-all-tests.sh:140, which still uses the looser
# `head -1 | grep -q bats`: for every file in this repository both rules agree
# (asserted by the shell-suite adapter's test suite). The looser rule is not
# copied here, because copying a rule known to misfire is how the misfire
# becomes load-bearing.
adapter_shebang_runner() {
  local file="$1" line interp arg1
  line="$(head -1 "$file" 2>/dev/null || true)"
  case "$line" in '#!'*) ;; *) echo "none"; return ;; esac

  # Strip `#!` and split on whitespace; ignore anything after a `#` comment.
  line="${line#\#!}"
  line="${line%%#*}"
  # shellcheck disable=SC2086
  set -- $line
  interp="${1:-}"; arg1="${2:-}"

  case "${interp##*/}" in
    env)
      # `env [-S] [VAR=val ...] <interpreter>` — take the first token that is
      # not a flag and not an assignment.
      shift || true
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -*|*=*) shift ;;
          *) arg1="$1"; break ;;
        esac
      done
      case "${arg1##*/}" in
        bats) echo "bats"; return ;;
        bash|sh|dash|zsh|ksh) echo "shell"; return ;;
        *) echo "none"; return ;;
      esac
      ;;
    bats) echo "bats"; return ;;
    bash|sh|dash|zsh|ksh) echo "shell"; return ;;
    *) echo "none"; return ;;
  esac
}

# adapter_validate_schema <schema_path> <instance_json>
#   Exit 0 valid, 1 invalid. FAILS CLOSED (never a silent skip-as-valid) when
#   python3+jsonschema is unavailable — matching aid-plan-fsm.sh's own
#   established precedent (aid_lifecycle_schema_validate: "validator
#   unavailable ... refusing to act on an unvalidated artifact") and this
#   plan's own aid-test-audit-config.sh fix. A caller with a real, present
#   document is trusting this check to actually gate downstream behavior —
#   treating "can't check" as "assume valid" would defeat that trust.
adapter_validate_schema() {
  local schema_path="$1" instance_json="$2"
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
    echo "adapter_validate_schema: validator unavailable (python3 + jsonschema required for $(basename "$schema_path")) — refusing to act on an unvalidated artifact" >&2
    return 1
  fi
  local instance_file
  instance_file="$(mktemp)"
  printf '%s' "$instance_json" > "$instance_file"
  python3 - "$schema_path" "$instance_file" <<'PY'
import sys, json
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.load(open(sys.argv[2]))
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(inst)) else 0)
PY
  local rc=$?
  rm -f "$instance_file" 2>/dev/null
  return $rc
}
