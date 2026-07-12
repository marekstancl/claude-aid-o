#!/usr/bin/env bash
# aid-select-tests.sh — P061 EPIC 3 Step 9 — Targeted test selector + runner.
#
# Reads changed paths (git diff against a base ref, or an explicit paths
# file), maps each to its corresponding test file(s) per the fixed Initial
# mapping (.aid-o/plans/P061-gate-profiles-test-cost-reduction.md Step 9),
# and RUNS the union of selected tests as a real gate command. This is NOT a
# "print a suggested command" tool — it executes the selected tests and this
# script's own exit status reflects their real pass/fail result.
#
# Usage:
#   aid-select-tests.sh --base <base_commit> [--evidence-file <path>]
#   aid-select-tests.sh --paths-file <file>  [--evidence-file <path>]
#
# Exactly one of --base / --paths-file is required.
#   --base <ref>          Changed paths computed via `git diff --name-only
#                          <ref>..HEAD`. Intended for gate-command dispatch:
#                          `aid-select-tests.sh --base {base_commit}` (see
#                          aid-run-gates.sh's placeholder-substitution list).
#   --paths-file <file>   Changed paths read verbatim, one per line, from an
#                          explicit file — a test-friendly alternative input
#                          mode. Mirrors the AID_CHANGED_PATHS convention
#                          aid-run-gates.sh already uses for its own
#                          "changed paths" input (see its coverage/relevance
#                          section: a file path, one entry per line).
#
# Classification per changed path:
#   (a) Mapped   — matches an Initial-mapping production path/prefix below;
#                  its corresponding test file(s) are added to the selection.
#   (b) Docs/non-production — a `.md` file, or a path outside the production
#                  surface (plugins/aid-orchestrator/{scripts,defaults}/ —
#                  lib/ subtrees not explicitly mapped, e.g.
#                  lib/brainstorm-server, fall in here too; only
#                  lib/ui-fidelity/** has an Initial-mapping entry) — no test
#                  impact, recorded in `reasoning` and skipped.
#   (c) Unknown production path — inside the production surface but not
#                  covered by the Initial mapping. This is a deliberate FAIL
#                  per plan decision D-selector-1 (unverifiable maps to fail
#                  via non-zero exit + a readable reason), never a silent
#                  skip.
#
# The union of tests selected from (a) across all changed paths is executed
# (bats files via `bats`, .sh harnesses via `bash`) and the aggregate
# pass/fail becomes part of this script's own exit status.
#
# Output: JSON summary `{selected_tests, reasoning, exit_status}` printed to
# stdout, and — if --evidence-file is given — also written there (mkdir -p
# for the parent directory).
#
# Exit codes:
#   0  — pass: every selected test passed, OR the change is docs-only /
#        outside the production surface (selected_tests is empty by design)
#   1  — fail: at least one selected test failed
#   3  — fail (unverifiable): a changed path fell inside the production
#        surface but outside the Initial mapping (D-selector-1). Recovery:
#        upgrade to a standard/full gate profile instead of this selector,
#        or extend the Initial mapping if the new path genuinely has no
#        dedicated test yet.
#   10 — input validation error (bad CLI usage, unresolvable --base ref,
#        missing/unreadable --paths-file)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_VERSION="${PLUGIN_VERSION:-v2.56.0}"

# Repo-root-relative prefix all Initial-mapping entries live under. Changed
# paths from `git diff` are already repo-root-relative (matches the
# allowed_paths / plan.json path convention used throughout this plugin).
PLUGIN_PREFIX="plugins/aid-orchestrator"

# Absolute path to this repo's plugins/aid-orchestrator/ directory (SCRIPT_DIR
# is .../plugins/aid-orchestrator/scripts, one level below it). Used to turn
# a mapped, PLUGIN_PREFIX-relative test path back into an absolute path for
# execution, without depending on the caller's CWD.
#
# AID_SELECT_TESTS_PLUGIN_ROOT is a test-only isolation seam (same convention
# as AID_GATE_BASELINE_FILE / AID_CHANGED_PATHS elsewhere in this plugin): it
# lets a bats fixture point test EXECUTION at fast stub files under a mktemp
# root, while the CLASSIFICATION logic (map_path_to_tests below) still maps
# real production paths to their real repo-relative test-file locations —
# only where those files are read from at run time changes. Unset in
# production; the real gate-command invocation never sets it.
PLUGIN_ROOT="${AID_SELECT_TESTS_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

usage() {
  cat <<EOF
Usage:
  aid-select-tests.sh --base <base_commit> [--evidence-file <path>]
  aid-select-tests.sh --paths-file <file>  [--evidence-file <path>]

Options:
  --base <ref>           Compute changed paths via 'git diff --name-only <ref>..HEAD'.
  --paths-file <file>    Read changed paths, one per line, from this file.
  --evidence-file <path> Also write the JSON summary here (parent dir created).
EOF
}

# ─── CLI parsing ────────────────────────────────────────────────────────────
BASE_REF=""
PATHS_FILE=""
EVIDENCE_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_REF="$2"; shift 2 ;;
    --paths-file) PATHS_FILE="$2"; shift 2 ;;
    --evidence-file) EVIDENCE_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 10 ;;
  esac
done

if [[ -n "$BASE_REF" && -n "$PATHS_FILE" ]]; then
  echo "ERROR: --base and --paths-file are mutually exclusive." >&2
  usage
  exit 10
fi
if [[ -z "$BASE_REF" && -z "$PATHS_FILE" ]]; then
  echo "ERROR: one of --base or --paths-file is required." >&2
  usage
  exit 10
fi

# ─── Resolve changed paths ──────────────────────────────────────────────────
CHANGED_PATHS=()
if [[ -n "$PATHS_FILE" ]]; then
  if [[ ! -f "$PATHS_FILE" ]]; then
    echo "ERROR: --paths-file not found: $PATHS_FILE" >&2
    exit 10
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    CHANGED_PATHS+=("$p")
  done < "$PATHS_FILE"
else
  diff_output=""
  if ! diff_output=$(git diff --name-only "$BASE_REF"..HEAD 2>&1); then
    echo "ERROR: git diff failed — is --base a valid ref? (${BASE_REF})" >&2
    echo "  ${diff_output}" >&2
    exit 10
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    CHANGED_PATHS+=("$p")
  done <<< "$diff_output"
fi

# ─── Initial mapping (fixed — see plan Step 9) ──────────────────────────────
# map_path_to_tests <changed_path>
#   Prints zero or more "<runner>\t<test_path>" lines (runner: bats|bash) for
#   an exact or prefix match. Prints nothing for no match. Never fails.
map_path_to_tests() {
  local p="$1"
  case "$p" in
    "${PLUGIN_PREFIX}/scripts/aid-run-gates.sh")
      printf 'bats\t%s/scripts/tests/bats/test-aid-run-gates.bats\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/scripts/aid-plan-diff.sh")
      printf 'bash\t%s/scripts/tests/test-plan-diff.sh\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/scripts/aid-release-policy.sh")
      # test-release-policy.bats is the suite that directly exercises
      # aid-release-policy.sh (the C4 release aggregator). The sibling
      # test-release-policy-surface-check.bats covers a DIFFERENT script
      # (release-policy-surface-check.sh — a manual bootstrap precedent for
      # this very selector, see its header comment) and is not selected here.
      printf 'bats\t%s/scripts/tests/bats/test-release-policy.bats\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/scripts/aid-fsm.sh")
      printf 'bats\t%s/scripts/tests/bats/test-aid-fsm.bats\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/scripts/aid-prefilter.sh")
      printf 'bats\t%s/scripts/tests/bats/test-aid-prefilter.bats\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/scripts/aid-evidence-verify.sh")
      printf 'bash\t%s/scripts/tests/test-evidence-verify.sh\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/defaults/schemas/"*)
      printf 'bash\t%s/scripts/tests/test-protocol-validate.sh\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/defaults/policies/delivery-gate.yaml")
      printf 'bash\t%s/scripts/tests/test-delivery-gate.sh\n' "$PLUGIN_PREFIX"
      ;;
    "${PLUGIN_PREFIX}/lib/ui-fidelity/"*)
      # Both suites reference lib/ui-fidelity/ directly (the only two in the
      # repo that do — verified by grep at authoring time) and exercise the
      # existing_ui FSM guard chain that consumes lib/ui-fidelity output.
      printf 'bash\t%s/scripts/tests/test-ui-fidelity-e2e.sh\n' "$PLUGIN_PREFIX"
      printf 'bash\t%s/scripts/tests/test-fsm-ui-fidelity.sh\n' "$PLUGIN_PREFIX"
      ;;
    *)
      return 0
      ;;
  esac
}

# is_production_surface <path> — true iff path lives under one of this
# plugin's Initial-mapping production roots: scripts/ or defaults/ (per plan
# Step 9's own docs-only definition — "files outside
# plugins/aid-orchestrator/scripts/ and defaults/"). `lib/` is deliberately
# NOT a blanket production root here: only lib/ui-fidelity/** is covered by
# the Initial mapping (matched earlier in map_path_to_tests, before this
# function is ever consulted); other lib/ subtrees (e.g. lib/brainstorm-server)
# have no Initial-mapping test yet and fall through to the docs/non-production
# no-op path rather than a false-positive D-selector-1 fail — narrowing that
# gap is future mapping work, not something this classifier should guess at.
# Anything else (skills/, commands/, agents/, docs, README, CHANGELOG,
# top-level .md, …) is also treated as docs/non-production.
is_production_surface() {
  local p="$1"
  case "$p" in
    "${PLUGIN_PREFIX}/scripts/"*|"${PLUGIN_PREFIX}/defaults/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── Classify every changed path ────────────────────────────────────────────
# selected_tests_lines: dedup-ordered "<runner>\t<test_path>" entries.
declare -a selected_tests_lines=()
declare -a reasoning=()
unverifiable=false

if [[ ${#CHANGED_PATHS[@]} -eq 0 ]]; then
  reasoning+=("no changed paths detected — nothing to select")
fi

for cp in "${CHANGED_PATHS[@]}"; do
  mapped="$(map_path_to_tests "$cp")"
  if [[ -n "$mapped" ]]; then
    while IFS=$'\t' read -r runner test_path; do
      [[ -z "$runner" ]] && continue
      already=false
      for existing in "${selected_tests_lines[@]}"; do
        [[ "$existing" == "${runner}"$'\t'"${test_path}" ]] && { already=true; break; }
      done
      if ! $already; then
        selected_tests_lines+=("${runner}"$'\t'"${test_path}")
      fi
      reasoning+=("mapped: ${cp} -> ${test_path}")
    done <<< "$mapped"
    continue
  fi

  if [[ "$cp" == *.md ]]; then
    reasoning+=("docs-only: ${cp} (.md file, no test impact)")
    continue
  fi

  if ! is_production_surface "$cp"; then
    reasoning+=("outside production surface: ${cp} (not under scripts/ or defaults/, and not an Initial-mapping lib/ path) — no test impact")
    continue
  fi

  # Inside the production surface, not covered by the Initial mapping.
  unverifiable=true
  reasoning+=("unverifiable: unknown production path ${cp} — upgrade to standard/full profile")
done

# ─── Run the selected tests (real gate command — not a suggestion) ─────────
run_failed=false
declare -a test_results=()
for entry in "${selected_tests_lines[@]}"; do
  IFS=$'\t' read -r runner test_path <<< "$entry"
  abs_test_path="${PLUGIN_ROOT}/${test_path#"${PLUGIN_PREFIX}"/}"

  if [[ ! -f "$abs_test_path" ]]; then
    run_failed=true
    reasoning+=("run-error: test file not found for ${test_path}")
    test_results+=("$(jq -nc --arg t "$test_path" --arg r "$runner" '{test:$t, runner:$r, result:"error", detail:"file not found"}')")
    continue
  fi

  case "$runner" in
    bats)
      if ! command -v bats >/dev/null 2>&1; then
        run_failed=true
        reasoning+=("run-error: bats not installed — cannot execute ${test_path}")
        test_results+=("$(jq -nc --arg t "$test_path" '{test:$t, runner:"bats", result:"error", detail:"bats not installed"}')")
        continue
      fi
      # 3>&- closes bats-core's own internal fd-3 control channel before
      # exec — without it, a nested `bats` invocation started from inside
      # another bats run (e.g. this script's own test suite, which stubs a
      # mapped test as a bats file) inherits the OUTER harness's fd 3 and
      # corrupts its TAP output/test count (observed: it silently added a
      # phantom test to the outer run). Harmless when not nested.
      if bats "$abs_test_path" 3>&- >/dev/null 2>&1; then
        test_results+=("$(jq -nc --arg t "$test_path" '{test:$t, runner:"bats", result:"pass"}')")
      else
        run_failed=true
        test_results+=("$(jq -nc --arg t "$test_path" '{test:$t, runner:"bats", result:"fail"}')")
      fi
      ;;
    bash)
      if bash "$abs_test_path" >/dev/null 2>&1; then
        test_results+=("$(jq -nc --arg t "$test_path" '{test:$t, runner:"bash", result:"pass"}')")
      else
        run_failed=true
        test_results+=("$(jq -nc --arg t "$test_path" '{test:$t, runner:"bash", result:"fail"}')")
      fi
      ;;
    *)
      run_failed=true
      reasoning+=("run-error: unknown runner '${runner}' for ${test_path}")
      ;;
  esac
done

# ─── Exit status decision ───────────────────────────────────────────────────
exit_status=0
if $unverifiable; then
  exit_status=3
elif $run_failed; then
  exit_status=1
fi

# ─── JSON summary ────────────────────────────────────────────────────────────
selected_paths_json="[]"
if [[ ${#selected_tests_lines[@]} -gt 0 ]]; then
  paths_only=()
  for entry in "${selected_tests_lines[@]}"; do
    IFS=$'\t' read -r _ test_path <<< "$entry"
    paths_only+=("$test_path")
  done
  selected_paths_json=$(printf '%s\n' "${paths_only[@]}" | jq -R . | jq -s '.')
fi

reasoning_json="[]"
if [[ ${#reasoning[@]} -gt 0 ]]; then
  reasoning_json=$(printf '%s\n' "${reasoning[@]}" | jq -R . | jq -s '.')
fi

test_results_json="[]"
if [[ ${#test_results[@]} -gt 0 ]]; then
  test_results_json=$(printf '%s\n' "${test_results[@]}" | jq -s '.')
fi

summary=$(jq -n \
  --arg gb "aid-select-tests.sh@${PLUGIN_VERSION}" \
  --arg ga "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson sel "$selected_paths_json" \
  --argjson reasons "$reasoning_json" \
  --argjson results "$test_results_json" \
  --argjson exit_status "$exit_status" \
  '{
    "_generated_by": $gb,
    "_generated_at": $ga,
    "selected_tests": $sel,
    "reasoning": $reasons,
    "test_results": $results,
    "exit_status": $exit_status
  }')

echo "$summary"

if [[ -n "$EVIDENCE_FILE" ]]; then
  mkdir -p "$(dirname "$EVIDENCE_FILE")"
  echo "$summary" > "$EVIDENCE_FILE"
fi

exit "$exit_status"
