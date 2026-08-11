#!/usr/bin/env bash
# aid-tier: t2
# test-control-boundary.sh — assert the plan-boundary claims mechanically.
# P068 Step 9 (E-068-2_2 Step 3).
#
# The plan-boundary work makes one narrow claim: it changes WHEN the specialist
# stack and the release run, not WHETHER any existing enforcement still
# enforces. Prose cannot carry that claim — three greps in a review comment
# cannot either. This check pins it against a checked-in baseline so that
# raising an enforcement, dropping a registry row, or quietly promoting a
# planned row to active all fail loudly and have to be argued for.
#
# Exit 0 = every claim holds. Exit 1 = at least one does not, and the output
# names it. The `test-` prefix matters: run-all-tests.sh discovers only
# `test-*.sh`, so a differently-named file would never run as a standing guard —
# a detector nothing runs is decoration.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASELINE="${SCRIPT_DIR}/fixtures/control-boundary-baseline.yaml"
REGISTRY="${PLUGIN_ROOT}/defaults/enforcement-registry.yaml"

fails=0
checks=0
pass() { printf 'PASS  %s\n' "$1"; checks=$((checks + 1)); }
fail() { printf 'FAIL  %s\n' "$1" >&2; fails=$((fails + 1)); checks=$((checks + 1)); }

command -v yq >/dev/null 2>&1 || { echo "SKIP: yq is required for test-control-boundary.sh" >&2; exit 0; }
[[ -f "$BASELINE" ]] || { echo "FAIL: baseline not found at $BASELINE" >&2; exit 1; }
[[ -f "$REGISTRY" ]] || { echo "FAIL: enforcement registry not found at $REGISTRY" >&2; exit 1; }

# ── 1. No enforcement level moved ───────────────────────────────────────────
# An `observe` policy that became `blocking` may well be an improvement, but it
# is never a side effect: it changes what fails a run for every consumer.
while IFS= read -r relpath; do
  [[ -n "$relpath" ]] || continue
  abs="${PLUGIN_ROOT}/${relpath}"
  if [[ ! -f "$abs" ]]; then
    fail "policy file named in the baseline no longer exists: ${relpath}"
    continue
  fi
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    want="$(yq -r ".policies.\"${relpath}\".\"${key}\"" "$BASELINE" 2>/dev/null)"
    got="$(yq -r ".${key} // \"<absent>\"" "$abs" 2>/dev/null)"
    if [[ "$got" == "$want" ]]; then
      pass "${relpath}: ${key} is still '${want}'"
    else
      fail "${relpath}: ${key} moved from '${want}' to '${got}' — the plan boundary changes WHEN reviews run, never whether an existing enforcement enforces. If this is intended, amend the baseline in the same commit and say why."
    fi
  done < <(yq -r ".policies.\"${relpath}\" | keys | .[]" "$BASELINE" 2>/dev/null)
done < <(yq -r '.policies | keys | .[]' "$BASELINE" 2>/dev/null)

# ── 2. Every required registry row exists, exactly once, with its verdict ────
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  want="$(yq -r ".required_enforcement_rows.\"${id}\"" "$BASELINE" 2>/dev/null)"
  n="$(yq -o=json '.enforcements' "$REGISTRY" 2>/dev/null | jq --arg i "$id" '[.[]|select(.id==$i)]|length' 2>/dev/null || echo 0)"
  if [[ "$n" == "0" ]]; then
    fail "registry row '${id}' is missing — the enforcement it records has no registry entry, which is how a capability becomes undiscoverable"
    continue
  fi
  if [[ "$n" != "1" ]]; then
    fail "registry row '${id}' appears ${n} times — a duplicated id makes every later query ambiguous"
    continue
  fi
  got="$(yq -o=json '.enforcements' "$REGISTRY" | jq -r --arg i "$id" '.[]|select(.id==$i)|.verdict')"
  if [[ "$got" == "$want" ]]; then
    pass "registry row '${id}' present once with verdict ${want}"
  else
    fail "registry row '${id}' has verdict '${got}', baseline expects '${want}'"
  fi
done < <(yq -r '.required_enforcement_rows | keys | .[]' "$BASELINE" 2>/dev/null)

# ── 3. Planned rows stay planned ────────────────────────────────────────────
# A planned row that becomes `active` claims an enforcement that no code backs.
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  want="$(yq -r ".required_planned_rows.\"${id}\"" "$BASELINE" 2>/dev/null)"
  got="$(yq -o=json '.enforcements' "$REGISTRY" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status' 2>/dev/null)"
  if [[ -z "$got" || "$got" == "null" ]]; then
    fail "planned registry row '${id}' is missing — the gap it records would then be invisible"
  elif [[ "$got" == "$want" ]]; then
    pass "planned row '${id}' is still '${want}' (its reader does not exist yet)"
  else
    fail "planned row '${id}' became '${got}' — a row may only become active when code actually enforces it"
  fi
done < <(yq -r '.required_planned_rows | keys | .[]' "$BASELINE" 2>/dev/null)

# ── 4. The registry total is derived, not hand-written ──────────────────────
declared="$(yq -r '.totals.enforcements' "$REGISTRY" 2>/dev/null)"
actual="$(yq -r '.enforcements | length' "$REGISTRY" 2>/dev/null)"
if [[ "$declared" == "$actual" ]]; then
  pass "registry total ${declared} matches the row count"
else
  fail "registry declares ${declared} enforcements but carries ${actual} rows — the header must be recomputed with \`yq '.enforcements|length'\`, never hand-incremented"
fi

echo "---"
# P072 Step 9 — canonical line for the aggregate collector, counting the real
# assertions this suite made rather than a suite-granularity 1/1.
if [[ "$checks" -eq 0 ]]; then checks=1; fi
echo "Results: $(( checks - fails ))/${checks} passed, ${fails} failed"
if [[ "$fails" -eq 0 ]]; then
  echo "test-control-boundary: OK"
  exit 0
fi
echo "test-control-boundary: ${fails} failure(s)" >&2
exit 1
