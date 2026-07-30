#!/usr/bin/env bash
# test-enforcement-registry-test-audit.sh — P066 Step 19.
#
# Verifies the 3 enforcement rows this plan registers
# (test_audit_static_command_allowlist, test_audit_catalog_approval_boundary,
# test_audit_never_auto_invoked): each has the full required field set (not
# merely a subset), and each row's `source` citation resolves to real code —
# the referenced file exists, and every function name named in parentheses
# actually appears in it. A row whose source can't be resolved is exactly
# the P026 failure mode (a detector that looks wired but isn't) this
# registry exists to prevent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGISTRY="${PLUGIN_DIR}/defaults/enforcement-registry.yaml"
BASELINE_FIXTURE="${SCRIPT_DIR}/fixtures/enforcement-registry-baseline-pre-p066-e3.json"

REQUIRED_IDS=(
  test_audit_static_command_allowlist
  test_audit_catalog_approval_boundary
  test_audit_never_auto_invoked
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
  row_json="$(jq -c --arg id "$id" '.enforcements[]? // empty | select(.id == $id)' <<<"$registry_json" 2>/dev/null)"
  if [[ -z "$row_json" ]]; then
    # Registry top-level key may not be "enforcements" — fall back to a
    # flat top-level array search.
    row_json="$(jq -c --arg id "$id" '.[] | arrays? // empty' <<<"$registry_json" 2>/dev/null)"
  fi
  if [[ -z "$row_json" ]]; then
    # Search every top-level key that holds an array for a matching id.
    row_json="$(jq -c --arg id "$id" '[.[] | select(type == "array") | .[] | select(.id == $id)] | .[0] // empty' <<<"$registry_json" 2>/dev/null)"
  fi
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

  # Codex review: a source citing MULTIPLE files (e.g. "a.sh; b.sh (fn)")
  # previously only resolved the first whitespace-delimited token — split on
  # ';' first so every cited file gets checked, not just the first.
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

    # Extract every function/identifier named inside parentheses (comma or
    # semicolon separated) and confirm each appears in the source file.
    paren_content="$(sed -n 's/.*(\(.*\)).*/\1/p' <<<"$clause")"
    if [[ -n "$paren_content" ]]; then
      IFS=',' read -r -a names <<<"$paren_content"
      for raw_name in "${names[@]}"; do
        name="$(sed -E 's/^\s+//; s/\s+$//' <<<"$raw_name")"
        [[ -z "$name" ]] && continue
        # Only check bare identifier-shaped tokens (skip free-text notes).
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

echo "TEST: no pre-existing row (per the checked-in pre-Step-19 baseline) was modified or removed"
# Codex review: counting `- id:` lines only proved the registry didn't
# SHRINK below a floor — it never proved that any SPECIFIC prior row
# survived unchanged (a delete-one/add-two edit would still pass). Compare
# every baseline row's full identity-defining field set against the live
# registry instead; new rows (this step's 3 additions, or any future ones)
# are unaffected since the baseline only lists what existed before this step.
if [[ ! -f "$BASELINE_FIXTURE" ]]; then
  fail_msg "baseline fixture missing: $BASELINE_FIXTURE"
else
  baseline_count="$(jq 'length' "$BASELINE_FIXTURE")"
  live_rows_file="$(mktemp)"
  jq -c '[.enforcements[] | {id, type, source, description, instruction, severity, surface, status, verdict, test}] | sort_by(.id)' <<<"$registry_json" > "$live_rows_file"
  mismatch_ids="$(jq -r -n --slurpfile baseline "$BASELINE_FIXTURE" --slurpfile live "$live_rows_file" '
    ($live[0] | map({(.id): .}) | add) as $live_by_id |
    [$baseline[0][] | select($live_by_id[.id] != .) | .id] | .[]
  ')" || fail_msg "internal error: jq comparison against baseline fixture failed"
  rm -f "$live_rows_file"
  if [[ -n "$mismatch_ids" ]]; then
    while IFS= read -r bad_id; do
      [[ -z "$bad_id" ]] && continue
      fail_msg "pre-existing row '$bad_id' is missing or was modified relative to the pre-Step-19 baseline"
    done <<<"$mismatch_ids"
  else
    pass_msg "all $baseline_count pre-existing rows are present and byte-identical to the pre-Step-19 baseline"
  fi
fi

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
