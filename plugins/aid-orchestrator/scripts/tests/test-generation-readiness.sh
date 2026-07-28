#!/usr/bin/env bash
# Focused adversarial tests for source-plan readiness.  These are intentionally
# small: they prove the pre-generation contract without invoking the full suite.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
READY="$ROOT/plugins/aid-orchestrator/scripts/aid-generation-readiness.sh"
GEN="$ROOT/plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh"
T="$ROOT/plugins/aid-orchestrator/defaults/templates/epic.md"
F="$ROOT/plugins/aid-orchestrator/scripts/tests/fixtures/multi-phase-plan.md"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
bad(){ echo "FAIL: $1 — $2"; fail=$((fail+1)); }
expect_pass(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label" "unexpected rejection"; fi; }
expect_fail(){ local label="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$label" "unexpected acceptance"; else ok "$label"; fi; }

# Valid source graph, including normal cross-EPIC backward dependencies.
expect_pass "valid multi-phase plan is ready" bash "$READY" "$F" --total 3

# One declared source of truth supports line-wrapped dependencies.
cp "$F" "$tmp/multiline.md"
sed -i 's/- Depends on: Step 3 (backend implementation)/- Depends on: Step 3,\n  Step 4 (backend implementation)/' "$tmp/multiline.md"
expect_pass "multi-line dependency form is accepted" bash "$READY" "$tmp/multiline.md" --total 3

cp "$F" "$tmp/missing.md"
sed -i 's/Depends on: Step 1 (architect contracts)/Depends on: Step 99/' "$tmp/missing.md"
expect_fail "missing dependency blocks before generation" bash "$READY" "$tmp/missing.md" --total 3

cp "$F" "$tmp/self.md"
sed -i 's/Depends on: Step 1 (architect contracts)/Depends on: Step 2/' "$tmp/self.md"
expect_fail "self dependency blocks before generation" bash "$READY" "$tmp/self.md" --total 3

cp "$F" "$tmp/forward.md"
sed -i 's/Depends on: Step 1 (architect contracts)/Depends on: Step 3/' "$tmp/forward.md"
expect_fail "forward dependency blocks before generation" bash "$READY" "$tmp/forward.md" --total 3

cp "$F" "$tmp/prose-prefix.md"
sed -i 's/Depends on: Step 1 (architect contracts)/Depends on: use Step 1 somehow/' "$tmp/prose-prefix.md"
expect_fail "prose before a dependency reference blocks instead of being guessed" bash "$READY" "$tmp/prose-prefix.md" --total 3

# A comma-separated Files list is not a legal multi-path declaration. It must
# fail instead of silently dropping its second path.
cp "$F" "$tmp/two-paths.md"
sed -i '0,/Create: `docs\/adr\/ADR-001-api-design.md`/s//Create: `docs\/adr\/ADR-001-api-design.md`, `docs\/adr\/ADR-002.md`/' "$tmp/two-paths.md"
expect_fail "comma-separated Files paths never silently lose the second path" bash "$READY" "$tmp/two-paths.md" --total 3

# The permitted ` + ` form must preserve BOTH paths in the generated EPIC.
cp "$F" "$tmp/plus-paths.md"
sed -i '0,/Create: `docs\/adr\/ADR-001-api-design.md`/s//Create: `docs\/adr\/ADR-001-api-design.md` + `docs\/adr\/ADR-002.md`/' "$tmp/plus-paths.md"
mkdir -p "$tmp/out"; printf 'counter: 0\n' > "$tmp/counter.yaml"
generated="$(bash "$GEN" --plan "$tmp/plus-paths.md" --phase 1 --total 3 --epic-template "$T" --output-dir "$tmp/out" --counter-yaml "$tmp/counter.yaml" 2>/dev/null)"
if [[ -f "$generated" ]] && grep -q '`docs/adr/ADR-001-api-design.md`' "$generated" && grep -q '`docs/adr/ADR-002.md`' "$generated"; then
  ok "explicit + Files paths both survive EPIC generation"
else
  bad "explicit + Files paths both survive EPIC generation" "one path was lost"
fi

echo "Results: $pass passed, $fail failed"
(( fail == 0 ))
