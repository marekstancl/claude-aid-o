#!/usr/bin/env bash
# Deterministic finding fingerprint helper for AID protocol v2.
# Usage (subcommand): aid-finding-fingerprint.sh fingerprint <project_id> <artifact_type> <check_id> <target_path> <finding_class>
#         or: aid-finding-fingerprint.sh occurrence_id <run_id> <check_id> <fingerprint>
# Sourceable: source this file and call fingerprint()/occurrence_id() directly.

fingerprint() {
  if [[ $# -lt 5 ]]; then
    echo "Usage: fingerprint <project_id> <artifact_type> <check_id> <target_path> <finding_class>" >&2
    return 1
  fi

  if ! command -v sha256sum &>/dev/null; then
    echo "sha256_required: sha256sum not found in PATH" >&2
    return 1
  fi

  local hex
  hex=$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' "$1" "$2" "$3" "$4" "$5" | sha256sum | cut -d' ' -f1 | cut -c1-64)
  printf 'sha256:%s\n' "$hex"
}

occurrence_id() {
  if [[ $# -lt 3 ]]; then
    echo "Usage: occurrence_id <run_id> <check_id> <fingerprint>" >&2
    return 1
  fi

  local run_id="$1"
  local check_id="$2"
  local fp="$3"
  # Extract 12 hex chars after the "sha256:" prefix
  local short_hex="${fp#sha256:}"
  short_hex="${short_hex:0:12}"
  printf '%s:%s:%s\n' "$run_id" "$check_id" "$short_hex"
}

# Subcommand dispatch
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "$1" in
    fingerprint)   shift; fingerprint "$@" ;;
    occurrence_id) shift; occurrence_id "$@" ;;
    *) echo "Usage: $(basename "$0") fingerprint|occurrence_id ..." >&2; exit 1 ;;
  esac
fi
