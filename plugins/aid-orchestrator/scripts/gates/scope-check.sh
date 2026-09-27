#!/usr/bin/env bash
# scope-check.sh — Deterministická validace scope EPICu
# Usage: scope-check.sh <allowed_paths_file> <base_commit>
# Exit 0 = scope OK, Exit 1 = scope violation
# Stdout = JSON report

set -euo pipefail
# shellcheck source=../lib/aid-ancillary.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/aid-ancillary.sh"

ALLOWED_PATHS_FILE="${1:?allowed_paths_file required}"
BASE_COMMIT="${2:?base_commit required}"

if [[ ! -f "$ALLOWED_PATHS_FILE" ]]; then
  echo '{"result":"fail","reason":"allowed_paths_file not found","files_changed":[]}'
  exit 1
fi

# Get changed files since base commit
CHANGED_FILES=$(git diff --name-only "$BASE_COMMIT" HEAD 2>/dev/null) || {
  echo '{"result":"fail","reason":"git diff failed — is base_commit valid?","files_changed":[]}'
  exit 1
}

if [[ -z "$CHANGED_FILES" ]]; then
  echo '{"result":"pass","reason":"no files changed","files_changed":[]}'
  exit 0
fi

# Load allowed path patterns (one per line, supports globs via bash)
mapfile -t ALLOWED < "$ALLOWED_PATHS_FILE"

VIOLATIONS=()
while IFS= read -r file; do
  allowed=false
  for pattern in "${ALLOWED[@]}"; do
    # The shared matcher, strict (a bare entry is only itself), so `dir/`
    # means what the step check and the dispatch contract read it as.
    _aid_ancillary_glob_match "$file" "$pattern" strict && { allowed=true; break; }
  done
  $allowed || VIOLATIONS+=("$file")
done <<< "$CHANGED_FILES"

# Build JSON output
FILES_JSON=$(printf '%s\n' "${CHANGED_FILES}" | jq -R . | jq -cs .)
VIOLATIONS_JSON=$(printf '%s\n' "${VIOLATIONS[@]:-}" | jq -R . | jq -cs .)

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "{\"result\":\"fail\",\"reason\":\"${#VIOLATIONS[@]} file(s) outside allowed scope\",\"violations\":${VIOLATIONS_JSON},\"files_changed\":${FILES_JSON}}"
  exit 1
else
  echo "{\"result\":\"pass\",\"reason\":\"all changed files within allowed scope\",\"files_changed\":${FILES_JSON}}"
  exit 0
fi
