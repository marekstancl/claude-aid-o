#!/usr/bin/env bash
# test-enforcement-registry-scheduler.sh — P069 Step 16.
#
# Verifies the 3 enforcement rows this plan registers
# (scheduler_unknown_parallelism_sequential,
# scheduler_rollout_requires_divergence_evidence,
# scheduler_no_second_job_supervisor): each has the full required field
# set, and each row's `source` citation resolves to real code — the
# referenced file exists, and every function/identifier named in
# parentheses actually appears in it. A row whose source can't be
# resolved is exactly the P026 failure mode (a detector that looks wired
# but isn't) this registry exists to prevent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${PLUGIN_DIR}/defaults/enforcement-registry.yaml"

REQUIRED_IDS=(
  scheduler_unknown_parallelism_sequential
  scheduler_rollout_requires_divergence_evidence
  scheduler_no_second_job_supervisor
)
REQUIRED_FIELDS=(id type source description instruction severity surface status verdict test)

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

registry_json="$(yq -o=json '.' "$REGISTRY" 2>/dev/null)" || {
  echo "  FAIL: $REGISTRY did not parse as YAML"
  echo "Results: 0/1 passed, 1 failed"
  exit 1
}

for id in "${REQUIRED_IDS[@]}"; do
  echo "TEST: row '$id' exists with the full required field set"
  row_json="$(jq -c --arg id "$id" '.enforcements[]? | select(.id == $id)' <<<"$registry_json" 2>/dev/null)"
  if [[ -z "$row_json" || "$row_json" == "null" ]]; then
    fail_msg "row '$id' not found in $REGISTRY"
    continue
  fi
  pass_msg "row '$id' found"

  missing_fields=""
  for field in "${REQUIRED_FIELDS[@]}"; do
    val="$(jq -r --arg f "$field" '.[$f] // empty' <<<"$row_json")"
    [[ -n "$val" ]] || missing_fields="${missing_fields}${missing_fields:+, }${field}"
  done
  if [[ -n "$missing_fields" ]]; then
    fail_msg "row '$id' missing required field(s): $missing_fields"
  else
    pass_msg "row '$id' has all required fields"
  fi

  echo "TEST: row '$id' source citation resolves to real code"
  source_str="$(jq -r '.source' <<<"$row_json")"

  # A source citing MULTIPLE files (e.g. "a.sh (fn); b.sh (fn2)") must have
  # EVERY cited file checked, not just the first — split on ';' first.
  IFS=';' read -r -a clauses <<<"$source_str"
  for clause in "${clauses[@]}"; do
    clause="$(sed -E 's/^\s+//; s/\s+$//' <<<"$clause")"
    [[ -z "$clause" ]] && continue
    source_file="${clause%% *}"
    resolved_path="${PLUGIN_DIR}/${source_file}"
    if [[ ! -f "$resolved_path" ]]; then
      fail_msg "row '$id' source file does not exist: $resolved_path"
      continue
    fi
    pass_msg "row '$id' source file exists: $source_file"

    # Extract every function/identifier named inside parentheses (comma-
    # separated) and confirm each bare-identifier-shaped token appears in
    # the source file. Free-text notes (containing spaces/quotes/etc.) are
    # skipped, matching the established convention.
    paren_content="$(sed -n 's/.*(\(.*\)).*/\1/p' <<<"$clause")"
    if [[ -n "$paren_content" ]]; then
      IFS=',' read -r -a names <<<"$paren_content"
      for raw_name in "${names[@]}"; do
        name="$(sed -E 's/^\s+//; s/\s+$//' <<<"$raw_name")"
        [[ -z "$name" ]] && continue
        if [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          if grep -qF "$name" "$resolved_path"; then
            pass_msg "row '$id' function/identifier '$name' found in $source_file"
          else
            fail_msg "row '$id' function/identifier '$name' NOT found in $source_file — source citation does not resolve"
          fi
        fi
      done
    fi
  done
done

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
