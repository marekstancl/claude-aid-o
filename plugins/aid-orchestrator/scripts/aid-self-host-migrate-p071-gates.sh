#!/usr/bin/env bash
# aid-self-host-migrate-p071-gates.sh — P071 EPIC E-071-1_1 (PM review round 2).
#
# PERSISTENCE MECHANISM for P071's `.aid-o/config/execution.yaml` changes.
#
# Problem this closes: `.aid-o/` is git-ignored by design ("AID workspace —
# not for distribution", .gitignore line 96). P071's Steps 1-3 modified THIS
# project's own local `.aid-o/config/execution.yaml` (a self-host artifact
# that predates /aid-init's generic gate-profile template — see
# `aid-init-execution-yaml.sh`, which does not know about this project's own
# bats_fsm/bats_all/plan_diff/etc gates at all). Without an explicit,
# TRACKED mechanism, a clean checkout, a fresh `/aid-init`, or simply a
# developer who never ran the P071 EPIC would silently be missing these
# fixes — no error, no signal, just a quietly-reverted execution.yaml.
#
# This script is that tracked mechanism. It is idempotent (`apply`) and
# self-checking (`verify`) against the LIVE file content — never against its
# own receipt alone, so a stale/missing receipt can never mask a real gap.
#
# Two subcommands:
#   apply   Ensure `.aid-o/config/execution.yaml` carries all P071 gate
#           migrations. Already-satisfied migrations are left untouched
#           (byte-identical no-op) — same idiom as
#           aid-init-execution-yaml.sh's "PM-confirmed upgrade" checks.
#           Writes a local, gitignored receipt
#           (.aid-o/config/.p071-execution-migration-receipt.json) recording
#           which migrations were applied/already-present, this script's own
#           sha256 (drift detection — the receipt is only meaningful for the
#           script version that wrote it), and the resulting config's sha256.
#   verify  Re-check all migrations directly against the CURRENT
#           execution.yaml content (never trusts the receipt) — exit 0 if
#           all present, exit 1 naming exactly which are missing plus the
#           remediation command. This is what a test (or a CI precondition)
#           calls to catch a silent regression.
#
# Usage:
#   aid-self-host-migrate-p071-gates.sh apply  [--execution-yaml PATH]
#   aid-self-host-migrate-p071-gates.sh verify [--execution-yaml PATH]
#
# Exit codes:
#   0  success (apply: migrations ensured; verify: all present)
#   1  verify: one or more migrations missing (names them)
#   2  usage error / missing execution.yaml / malformed YAML
#   3  required dependency missing (yq)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: aid-self-host-migrate-p071-gates.sh <apply|verify> [--execution-yaml PATH]

  apply   Idempotently ensure execution.yaml carries all P071 gate migrations.
          Writes a local receipt to
          .aid-o/config/.p071-execution-migration-receipt.json (gitignored).
  verify  Check execution.yaml directly (not the receipt) for all P071
          migrations. Exit 0 if all present, exit 1 naming what's missing.

  --execution-yaml PATH   Default: ./.aid-o/config/execution.yaml (relative
                           to the current working directory).

Exit codes:
  0  success
  1  verify: one or more migrations missing
  2  usage error / execution.yaml missing or malformed
  3  required dependency ('yq') missing
EOF
}

CMD="${1:-}"
[[ -n "$CMD" ]] || { usage >&2; exit 2; }
shift || true
case "$CMD" in
  apply|verify) : ;;
  -h|--help) usage; exit 0 ;;
  *) echo "ERROR: aid-self-host-migrate-p071-gates.sh: unknown subcommand '$CMD'" >&2; usage >&2; exit 2 ;;
esac

EXEC_YAML="./.aid-o/config/execution.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --execution-yaml)
      [[ $# -ge 2 ]] || { echo "ERROR: aid-self-host-migrate-p071-gates.sh: --execution-yaml requires a value" >&2; exit 2; }
      EXEC_YAML="$2"
      shift 2
      ;;
    *)
      echo "ERROR: aid-self-host-migrate-p071-gates.sh: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: aid-self-host-migrate-p071-gates.sh: required dependency 'yq' not found on PATH" >&2
  exit 3
fi

if [[ ! -f "$EXEC_YAML" ]]; then
  echo "ERROR: aid-self-host-migrate-p071-gates.sh: execution.yaml not found at '$EXEC_YAML'" >&2
  exit 2
fi
yq -e '.' "$EXEC_YAML" >/dev/null 2>&1 || {
  echo "ERROR: aid-self-host-migrate-p071-gates.sh: '$EXEC_YAML' is not valid YAML" >&2
  exit 2
}

# ── Migration checks (each independently idempotent-checkable) ─────────────
# Every check function echoes nothing and returns 0 (satisfied) or 1 (not).

_m1_plan_diff_timeout() {
  [[ "$(yq -r '.gates.plan_diff.timeout_seconds // ""' "$EXEC_YAML")" == "300" ]]
}

_m2_shell_pipeline_smoke_description() {
  yq -r '.gates.shell_pipeline_smoke.description // ""' "$EXEC_YAML" \
    | grep -qi "full aggregate"
}

_m3_bats_all_split() {
  local cmd
  cmd="$(yq -r '.gates.bats_all.command // ""' "$EXEC_YAML")"
  [[ "$cmd" == *aid-bats-parallel-lane.sh* && "$cmd" == *--pool-only* ]]
}

_m4_bats_boundary_gate() {
  # NOTE: `.required // ""` would be wrong here — jq/yq's `//` operator
  # treats a real `false` value as falsy too, silently replacing a genuine
  # `required: false` with the default. Query the raw value directly instead
  # (a missing key prints the literal string "null", which never equals
  # "false", so this still correctly reports "not satisfied" when absent).
  local cmd required
  cmd="$(yq -r '.gates.bats_boundary.command // ""' "$EXEC_YAML")"
  required="$(yq -r '.gates.bats_boundary.required' "$EXEC_YAML")"
  [[ "$cmd" == *aid-bats-parallel-lane.sh* && "$cmd" == *--dedicated-only* && "$required" == "false" ]]
}

_m5_full_profile_has_boundary() {
  yq -r '.gate_profiles.full.include[]? // ""' "$EXEC_YAML" | grep -qx "bats_boundary"
}

_m6_release_profile_has_boundary() {
  yq -r '.gate_profiles.release.include[]? // ""' "$EXEC_YAML" | grep -qx "bats_boundary"
}

# Migration id -> human label, in a stable order.
MIGRATION_IDS=(m1_plan_diff_timeout m2_shell_pipeline_smoke_description m3_bats_all_split m4_bats_boundary_gate m5_full_profile_has_boundary m6_release_profile_has_boundary)
declare -A MIGRATION_LABELS=(
  [m1_plan_diff_timeout]="gates.plan_diff.timeout_seconds == 300"
  [m2_shell_pipeline_smoke_description]="gates.shell_pipeline_smoke.description mentions 'full aggregate'"
  [m3_bats_all_split]="gates.bats_all.command uses aid-bats-parallel-lane.sh --pool-only"
  [m4_bats_boundary_gate]="gates.bats_boundary exists (--dedicated-only, required:false)"
  [m5_full_profile_has_boundary]="gate_profiles.full.include[] contains bats_boundary"
  [m6_release_profile_has_boundary]="gate_profiles.release.include[] contains bats_boundary"
)

_check() {
  case "$1" in
    m1_plan_diff_timeout) _m1_plan_diff_timeout ;;
    m2_shell_pipeline_smoke_description) _m2_shell_pipeline_smoke_description ;;
    m3_bats_all_split) _m3_bats_all_split ;;
    m4_bats_boundary_gate) _m4_bats_boundary_gate ;;
    m5_full_profile_has_boundary) _m5_full_profile_has_boundary ;;
    m6_release_profile_has_boundary) _m6_release_profile_has_boundary ;;
  esac
}

if [[ "$CMD" == "verify" ]]; then
  MISSING=()
  for id in "${MIGRATION_IDS[@]}"; do
    _check "$id" || MISSING+=("$id")
  done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: aid-self-host-migrate-p071-gates.sh: '$EXEC_YAML' is missing ${#MISSING[@]} P071 gate migration(s):" >&2
    for id in "${MISSING[@]}"; do
      echo "  - ${id}: ${MIGRATION_LABELS[$id]}" >&2
    done
    echo "Run: bash ${SCRIPT_DIR}/aid-self-host-migrate-p071-gates.sh apply --execution-yaml '$EXEC_YAML'" >&2
    exit 1
  fi
  echo "aid-self-host-migrate-p071-gates.sh: verify PASSED — all ${#MIGRATION_IDS[@]} P071 gate migrations present in '$EXEC_YAML'"
  exit 0
fi

# ── apply ────────────────────────────────────────────────────────────────
# Each migration is applied ONLY if not already satisfied — a no-op on an
# already-migrated file is byte-identical (verified by the test suite).
APPLIED=()
ALREADY_PRESENT=()

if ! _m1_plan_diff_timeout; then
  yq -i '
    .gates.plan_diff.timeout_seconds = 300
  ' "$EXEC_YAML"
  APPLIED+=("m1_plan_diff_timeout")
else
  ALREADY_PRESENT+=("m1_plan_diff_timeout")
fi

if ! _m2_shell_pipeline_smoke_description; then
  yq -i '
    .gates.shell_pipeline_smoke.description = "Despite the name, this is NOT a fast/partial smoke check — it runs the FULL aggregate test suite via run-all-tests.sh (timeout_seconds 1900, ~32 min budget). Treat it as equivalent in scope/cost to bats_all, not as a quick sanity check."
  ' "$EXEC_YAML"
  APPLIED+=("m2_shell_pipeline_smoke_description")
else
  ALREADY_PRESENT+=("m2_shell_pipeline_smoke_description")
fi

if ! _m3_bats_all_split; then
  yq -i '
    .gates.bats_all.command = "bash plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh --pool-only"
    | .gates.bats_all.required = true
    | .gates.bats_all.timeout_seconds = 600
    | .gates.bats_all.max_retries = 0
  ' "$EXEC_YAML"
  APPLIED+=("m3_bats_all_split")
else
  ALREADY_PRESENT+=("m3_bats_all_split")
fi

if ! _m4_bats_boundary_gate; then
  yq -i '
    .gates.bats_boundary.command = "bash plugins/aid-orchestrator/scripts/aid-bats-parallel-lane.sh --dedicated-only"
    | .gates.bats_boundary.required = false
    | .gates.bats_boundary.timeout_seconds = 7200
    | .gates.bats_boundary.max_retries = 0
  ' "$EXEC_YAML"
  APPLIED+=("m4_bats_boundary_gate")
else
  ALREADY_PRESENT+=("m4_bats_boundary_gate")
fi

if ! _m5_full_profile_has_boundary; then
  yq -i '
    .gate_profiles.full.include = ((.gate_profiles.full.include // []) + ["bats_boundary"] | unique)
  ' "$EXEC_YAML"
  APPLIED+=("m5_full_profile_has_boundary")
else
  ALREADY_PRESENT+=("m5_full_profile_has_boundary")
fi

if ! _m6_release_profile_has_boundary; then
  yq -i '
    .gate_profiles.release.include = ((.gate_profiles.release.include // []) + ["bats_boundary"] | unique)
  ' "$EXEC_YAML"
  APPLIED+=("m6_release_profile_has_boundary")
else
  ALREADY_PRESENT+=("m6_release_profile_has_boundary")
fi

# ── Receipt (local, gitignored — proves THIS checkout's state; the SCRIPT
# above, not the receipt, is the durable/tracked source of truth) ──────────
RECEIPT_PATH="$(dirname "$EXEC_YAML")/.p071-execution-migration-receipt.json"
SCRIPT_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1)"
CONFIG_SHA256="$(sha256sum "$EXEC_YAML" | cut -d' ' -f1)"
APPLIED_JSON="$(printf '%s\n' "${APPLIED[@]:-}" | jq -R 'select(length>0)' | jq -sc '.')"
ALREADY_PRESENT_JSON="$(printf '%s\n' "${ALREADY_PRESENT[@]:-}" | jq -R 'select(length>0)' | jq -sc '.')"

jq -n \
  --arg applied_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg script_sha256 "sha256:${SCRIPT_SHA256}" \
  --arg config_sha256 "sha256:${CONFIG_SHA256}" \
  --argjson applied_this_run "$APPLIED_JSON" \
  --argjson already_present "$ALREADY_PRESENT_JSON" \
  '{
    schema_version: "1.0.0",
    migration: "P071-execution-yaml-gates",
    applied_at: $applied_at,
    script_sha256: $script_sha256,
    config_sha256: $config_sha256,
    applied_this_run: $applied_this_run,
    already_present: $already_present
  }' > "$RECEIPT_PATH"

echo "aid-self-host-migrate-p071-gates.sh: apply PASSED — ${#APPLIED[@]} migration(s) applied, ${#ALREADY_PRESENT[@]} already present. Receipt: $RECEIPT_PATH"
exit 0
