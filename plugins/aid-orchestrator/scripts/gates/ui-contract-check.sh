#!/usr/bin/env bash
# ui-contract-check.sh — AID UI Change Contract validator
# E-056-1_3 Step 2 | D7 transport-path hard envelope | D6 standalone gate (no FSM wiring)
#
# Usage:
#   ui-contract-check.sh --type-check <contract-file.yaml>
#   ui-contract-check.sh --envelope-check <contract-file.yaml> [--evidence-dir <dir>]
#   ui-contract-check.sh --help
#
# Exit 0 = valid. Exit 1 = invalid (reason on stderr).
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
ui-contract-check.sh — AID UI Change Contract validator

USAGE
  ui-contract-check.sh --type-check <contract-file.yaml>
      Validate types and required fields in a ui-change-contract YAML file.

  ui-contract-check.sh --envelope-check <contract-file.yaml> [--evidence-dir <dir>]
      Validate the envelope block: path safety, file existence, sha256 hash.
      If --evidence-dir is given, copies baseline PNG to <dir>/ui/<contract_id>-baseline.png.

  ui-contract-check.sh --help
      Show this message.

EXIT CODES
  0   Valid (and copy performed when --evidence-dir given)
  1   Invalid (reason printed to stderr)
EOF
}

err() {
  echo "ERROR: $*" >&2
  exit 1
}

require_yq() {
  command -v yq >/dev/null 2>&1 || err "yq is required but not found in PATH"
}

# yq read helper: returns empty string for null/missing
yq_get() {
  local file="$1" path="$2"
  yq e "${path} // \"\"" "$file" 2>/dev/null
}

# yq read helper: returns raw value (no quoting), empty for null
yq_raw() {
  local file="$1" path="$2"
  yq e "${path}" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Mode: --type-check
# ---------------------------------------------------------------------------
type_check() {
  local contract_file="$1"

  require_yq

  # 1. File exists
  [[ -f "$contract_file" ]] || err "Contract file not found: $contract_file"

  # Validate YAML is parseable
  yq e '.' "$contract_file" >/dev/null 2>&1 || err "File is not valid YAML: $contract_file"

  # 2. contract_id present and non-empty
  local contract_id
  contract_id=$(yq_get "$contract_file" '.contract_id')
  [[ -n "$contract_id" && "$contract_id" != "null" ]] || err "contract_id is required and must be non-empty"

  # 3. version present and semver-like (N.N.N)
  local version
  version=$(yq_get "$contract_file" '.version')
  [[ -n "$version" && "$version" != "null" ]] || err "version is required and must be non-empty"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "version must be semver format (N.N.N), got: $version"

  # 4. If viewport present: must have width and height as integers (not array)
  local viewport_type
  viewport_type=$(yq e '.viewport | tag' "$contract_file" 2>/dev/null || echo "")
  if [[ -n "$viewport_type" && "$viewport_type" != "null" && "$viewport_type" != "!!null" ]]; then
    # 9. Must be a single object, not an array
    if [[ "$viewport_type" == "!!seq" ]]; then
      err "viewport must be a single object (not an array) — one contract per viewport"
    fi
    if [[ "$viewport_type" != "!!map" ]]; then
      err "viewport must be an object, got tag: $viewport_type"
    fi

    local vp_width vp_height
    vp_width=$(yq_get "$contract_file" '.viewport.width')
    vp_height=$(yq_get "$contract_file" '.viewport.height')

    [[ -n "$vp_width" && "$vp_width" != "null" ]] || err "viewport.width is required when viewport is present"
    [[ -n "$vp_height" && "$vp_height" != "null" ]] || err "viewport.height is required when viewport is present"

    [[ "$vp_width" =~ ^[0-9]+$ ]] || err "viewport.width must be an integer, got: $vp_width"
    [[ "$vp_height" =~ ^[0-9]+$ ]] || err "viewport.height must be an integer, got: $vp_height"
  fi

  # 10. target must be present (not empty/null)
  local target_type
  target_type=$(yq e '.target | tag' "$contract_file" 2>/dev/null || echo "")
  if [[ -z "$target_type" || "$target_type" == "null" || "$target_type" == "!!null" ]]; then
    err "target is required and must not be null/empty"
  fi

  # 5. target.id present and non-empty
  local target_id
  target_id=$(yq_get "$contract_file" '.target.id')
  [[ -n "$target_id" && "$target_id" != "null" ]] || err "target.id is required and must be non-empty"

  # 6. target.selector present and non-empty
  local target_selector
  target_selector=$(yq_get "$contract_file" '.target.selector')
  [[ -n "$target_selector" && "$target_selector" != "null" ]] || err "target.selector is required and must be non-empty"

  # 7. If target.presence.state present: must be a valid enum value
  local presence_state
  presence_state=$(yq_get "$contract_file" '.target.presence.state')
  if [[ -n "$presence_state" && "$presence_state" != "null" ]]; then
    case "$presence_state" in
      visible|hidden|exists|removed) ;;
      *) err "target.presence.state must be one of: visible, hidden, exists, removed — got: $presence_state" ;;
    esac
  fi

  # 8. If delta.typed present: must be array with at least 1 element
  local delta_typed_type
  delta_typed_type=$(yq e '.delta.typed | tag' "$contract_file" 2>/dev/null || echo "")
  if [[ -n "$delta_typed_type" && "$delta_typed_type" != "null" && "$delta_typed_type" != "!!null" ]]; then
    if [[ "$delta_typed_type" != "!!seq" ]]; then
      err "delta.typed must be an array, got tag: $delta_typed_type"
    fi
    local delta_typed_count
    delta_typed_count=$(yq e '.delta.typed | length' "$contract_file" 2>/dev/null || echo "0")
    [[ "$delta_typed_count" -ge 1 ]] || err "delta.typed must have at least 1 element when present"
  fi

  echo "type-check PASS: $contract_file"
  exit 0
}

# ---------------------------------------------------------------------------
# Mode: --envelope-check
# ---------------------------------------------------------------------------
envelope_check() {
  local contract_file="$1"
  local evidence_dir="$2"

  require_yq

  # File must exist
  [[ -f "$contract_file" ]] || err "Contract file not found: $contract_file"

  # Validate YAML
  yq e '.' "$contract_file" >/dev/null 2>&1 || err "File is not valid YAML: $contract_file"

  # 5a. Schema-level: validate presence.state enum (reuse from type-check)
  local presence_state
  presence_state=$(yq_get "$contract_file" '.target.presence.state')
  if [[ -n "$presence_state" && "$presence_state" != "null" ]]; then
    case "$presence_state" in
      visible|hidden|exists|removed) ;;
      *) err "target.presence.state schema invalid — must be one of: visible, hidden, exists, removed — got: $presence_state" ;;
    esac
  fi

  # contract_id is needed for evidence copy naming
  local contract_id
  contract_id=$(yq_get "$contract_file" '.contract_id')
  [[ -n "$contract_id" && "$contract_id" != "null" ]] || err "contract_id is required for envelope check"

  # Validate contract_id is safe to use in path
  if [[ ! "$contract_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    err "contract_id must contain only alphanumeric, dash, underscore characters: $contract_id"
  fi

  # 1. envelope.baseline_path must be present
  local baseline_path
  baseline_path=$(yq_get "$contract_file" '.envelope.baseline_path')
  [[ -n "$baseline_path" && "$baseline_path" != "null" ]] || err "envelope.baseline_path is required"

  # 2. Path must be relative: no leading '/' and no '..' component
  if [[ "$baseline_path" == /* ]]; then
    err "envelope.baseline_path must be a relative path (no leading '/') — got: $baseline_path"
  fi
  # Split on / and check each component
  IFS='/' read -ra path_parts <<< "$baseline_path"
  for part in "${path_parts[@]}"; do
    if [[ "$part" == ".." ]]; then
      err "envelope.baseline_path must not contain '..' traversal — got: $baseline_path"
    fi
  done

  # Determine repo root: walk up from this script's location
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # scripts/gates/ → scripts/ → plugins/aid-orchestrator/ → plugins/ → repo root
  local repo_root
  repo_root="$(cd "${script_dir}/../../../.." && pwd)"

  # 3. File must exist at <repo-root>/<baseline_path>
  local abs_baseline="${repo_root}/${baseline_path}"
  [[ -f "$abs_baseline" ]] || err "Baseline file not found at '${abs_baseline}' (repo root: ${repo_root}, path: ${baseline_path})"

  # 4. sha256 must match
  local expected_sha
  expected_sha=$(yq_get "$contract_file" '.envelope.baseline_sha256')
  [[ -n "$expected_sha" && "$expected_sha" != "null" ]] || err "envelope.baseline_sha256 is required"

  local actual_sha
  actual_sha=$(sha256sum "$abs_baseline" | awk '{print $1}')
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    err "SHA-256 mismatch for '${baseline_path}': expected ${expected_sha}, got ${actual_sha}"
  fi

  # 6. Copy to evidence dir if provided
  if [[ -n "$evidence_dir" ]]; then
    local evidence_ui_dir="${evidence_dir}/ui"
    mkdir -p "$evidence_ui_dir"
    local dest="${evidence_ui_dir}/${contract_id}-baseline.png"
    cp "$abs_baseline" "$dest"
    echo "Copied baseline to: $dest"
  fi

  echo "envelope-check PASS: $contract_file"
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

MODE=""
CONTRACT_FILE=""
EVIDENCE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --type-check)
      MODE="type-check"
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --type-check requires a contract file argument" >&2; exit 1; }
      CONTRACT_FILE="$1"
      shift
      ;;
    --envelope-check)
      MODE="envelope-check"
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --envelope-check requires a contract file argument" >&2; exit 1; }
      CONTRACT_FILE="$1"
      shift
      ;;
    --evidence-dir)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --evidence-dir requires a directory argument" >&2; exit 1; }
      EVIDENCE_DIR="$1"
      shift
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

case "$MODE" in
  type-check)
    type_check "$CONTRACT_FILE"
    ;;
  envelope-check)
    envelope_check "$CONTRACT_FILE" "$EVIDENCE_DIR"
    ;;
  *)
    echo "ERROR: No mode specified. Use --type-check or --envelope-check." >&2
    usage
    exit 1
    ;;
esac
