#!/usr/bin/env bash
# release-policy-surface-check.sh — P061 D8 bootstrap surface rule.
#
# WHY: test-release-policy.bats is a ~4-5 min real-fixture integration suite (even after the
# 2026-07-11 test-cost fix). Running it as a blanket EPIC-boundary proof is wasted time when the
# EPIC's diff never touches release-policy surface at all. This is a manual bootstrap convention
# — a small, explicit, easily-auditable check — NOT the full aid-select-tests.sh selector (that
# is P061 EPIC 3's job). Once EPIC 3 lands, this logic should be folded into that tool rather than
# maintained twice; until then, use this script by hand at EPIC-boundary test-selection time.
#
# Usage:
#   release-policy-surface-check.sh <changed-path> [<changed-path> ...]
#   git diff --name-only <base>..HEAD | xargs -r release-policy-surface-check.sh
#
# Exit 0 + prints "relevant" if any changed path matches release-policy surface, OR if called
# with zero paths (fail-safe default: when in doubt, run the suite).
# Exit 1 + prints "not-relevant" if no changed path matches.
#
# Surface (any match → relevant):
#   plugins/aid-orchestrator/scripts/aid-release-policy.sh
#   plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats
#   plugins/aid-orchestrator/scripts/aid-evidence-verify.sh
#   plugins/aid-orchestrator/defaults/schemas/release*           (glob prefix on basename)
#   plugins/aid-orchestrator/defaults/schemas/aid-protocol-v2.schema.json
#   plugins/aid-orchestrator/scripts/tests/fixtures/release-policy/   (directory prefix)
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "relevant (no changed paths given — fail-safe default: run the suite)"
  exit 0
fi

is_release_policy_surface() {
  local f="$1"
  case "$f" in
    plugins/aid-orchestrator/scripts/aid-release-policy.sh) return 0 ;;
    plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats) return 0 ;;
    plugins/aid-orchestrator/scripts/aid-evidence-verify.sh) return 0 ;;
    plugins/aid-orchestrator/defaults/schemas/release*) return 0 ;;
    plugins/aid-orchestrator/defaults/schemas/aid-protocol-v2.schema.json) return 0 ;;
    plugins/aid-orchestrator/scripts/tests/fixtures/release-policy/*) return 0 ;;
    *) return 1 ;;
  esac
}

for f in "$@"; do
  if is_release_policy_surface "$f"; then
    echo "relevant ($f matches release-policy surface)"
    exit 0
  fi
done

echo "not-relevant"
exit 1
