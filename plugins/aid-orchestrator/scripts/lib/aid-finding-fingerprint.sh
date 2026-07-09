#!/usr/bin/env bash
# Deterministic finding fingerprint helper for AID protocol v2.
# Usage (subcommand): aid-finding-fingerprint.sh fingerprint <project_id> <artifact_type> <check_id> <target_path> <finding_class>
#         or: aid-finding-fingerprint.sh fingerprint_audit_report <project_id> <artifact_type> <occurrence_id> <severity> <area> <finding> <recommendation>
#         or: aid-finding-fingerprint.sh occurrence_id <run_id> <check_id> <fingerprint>
# Sourceable: source this file and call fingerprint()/fingerprint_audit_report()/occurrence_id() directly.

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

# fingerprint_audit_report — canonical fingerprint for C3 (audit_report) findings.
#
# audit_report findings are LLM-derived adversarial-review discoveries, not
# deterministic check-against-target results — they have no check_id/target_path/
# finding_class (those fields aren't in audit-report.schema.json and never were;
# C3.5's minimal finding shape is fingerprint/occurrence_id/severity/action_owner
# plus the free-form area/finding/recommendation fields the auditor actually
# writes). The universal fingerprint() formula above doesn't apply here — using it
# against empty check_id/target_path/finding_class would make the fingerprint
# depend only on project_id+artifact_type+occurrence_id+severity, which does NOT
# bind to the finding's actual content (area/finding/recommendation) and would
# let those fields be silently tampered without invalidating the fingerprint.
#
# This formula binds to occurrence_id + severity + area + finding + recommendation
# instead, so any of these being altered from what the auditor originally emitted
# produces a different hash. area/finding/recommendation are not schema-required
# (a C3 finding could theoretically omit them) — the explicit "" fallback below is
# used only when a field is genuinely absent, and that absence is still part of
# the hashed content (unlike skipping the check entirely), so a finding that goes
# from having real area/finding/recommendation text to having it stripped out
# still changes the fingerprint and gets caught as tampering.
fingerprint_audit_report() {
  if [[ $# -lt 7 ]]; then
    echo "Usage: fingerprint_audit_report <project_id> <artifact_type> <occurrence_id> <severity> <area> <finding> <recommendation>" >&2
    return 1
  fi

  if ! command -v sha256sum &>/dev/null; then
    echo "sha256_required: sha256sum not found in PATH" >&2
    return 1
  fi

  local hex
  hex=$(printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7" | sha256sum | cut -d' ' -f1 | cut -c1-64)
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
    fingerprint)             shift; fingerprint "$@" ;;
    fingerprint_audit_report) shift; fingerprint_audit_report "$@" ;;
    occurrence_id)           shift; occurrence_id "$@" ;;
    *) echo "Usage: $(basename "$0") fingerprint|fingerprint_audit_report|occurrence_id ..." >&2; exit 1 ;;
  esac
fi
