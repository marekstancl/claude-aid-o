#!/bin/bash
# Refresh the COMMITTED minimal conformance fixture + oracle (E-047-4_7 REOPEN).
#
# The fixture is HAND-AUTHORED and SANITIZED — it is NOT a copy of real project
# data (the round-4 snapshot copied 17 MB of real plans and leaked a plaintext
# credential, which is why this was rebuilt). This script:
#   1. regenerates tests/fixtures/mini/ deterministically from the generator,
#   2. fails hard if the generated tree contains anything secret-shaped,
#   3. regenerates tests/fixtures/mini-oracle.json via aid-diagnostic.sh.
#
# Usage:  bash packages/aid-server/scripts/refresh-fixtures.sh

set -euo pipefail

PKG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PKG_ROOT/../.." && pwd)"
GENERATOR="$PKG_ROOT/tests/fixtures/build-mini-fixture.mjs"
FIXTURE_DIR="$PKG_ROOT/tests/fixtures/mini"
ORACLE_FILE="$PKG_ROOT/tests/fixtures/mini-oracle.json"
EVIDENCE_ROOT="$FIXTURE_DIR/demo/.aid-o/work/evidence"
DIAGNOSTIC_SCRIPT="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-diagnostic.sh"

[ -f "$GENERATOR" ] || { echo "Error: generator not found at $GENERATOR" >&2; exit 1; }
[ -f "$DIAGNOSTIC_SCRIPT" ] || { echo "Error: aid-diagnostic.sh not found at $DIAGNOSTIC_SCRIPT" >&2; exit 1; }

echo "1/3 Generating minimal fixture..."
node "$GENERATOR"

echo "2/3 Secret-scanning the generated fixture (must be clean)..."
# Deny-list of secret-shaped tokens. A match is a HARD failure — the fixture must
# never carry credentials/tokens/keys (PM #4 regression guard).
if grep -rInE -i \
  'password[[:space:]]*[:=]|passwd|secret[[:space:]]*[:=]|api[_-]?key|authorization:[[:space:]]*bearer|-----BEGIN[[:space:]]+[A-Z ]*PRIVATE KEY|xox[baprs]-|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' \
  "$FIXTURE_DIR"; then
  echo "" >&2
  echo "ERROR: secret-shaped content found in the fixture above. Refusing to write." >&2
  echo "The fixture must be fully sanitized — remove the offending values." >&2
  exit 1
fi
echo "   clean."

echo "3/3 Regenerating oracle via aid-diagnostic.sh..."
bash "$DIAGNOSTIC_SCRIPT" --evidence-root "$EVIDENCE_ROOT" --output json > "$ORACLE_FILE"

echo ""
echo "Done."
echo "  fixture: $FIXTURE_DIR  ($(find "$FIXTURE_DIR" -type f | wc -l | tr -d ' ') files)"
echo "  oracle : $ORACLE_FILE  ($(grep -c '"run_id"' "$ORACLE_FILE" | tr -d ' ') runs)"
echo ""
echo "Commit both. The blocking conformance test reads them and FAILS if missing."
