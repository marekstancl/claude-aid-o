#!/usr/bin/env bash
# aid-tier: t2
# test-plan-review-acceptance.sh — the whole plan review flow on a real failed
# plan, replayed from recorded reviewer answers (no model call), checked
# against targets written before the live run (fixtures/plan-review/targets.json).
# Cross-component (plan check, round script, adjudicator, gate) and it clones
# ACTA, hence t2. The live run itself is recorded in docs/plans/P093-acceptance-run.md.
# Origin: P093 Step 12 (plan review rebuild).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AID_PLUGIN_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FX="${SCRIPT_DIR}/fixtures/plan-review"
ROUND="${AID_PLUGIN_PATH}/scripts/aid-review-round.sh"   # P094: the one engine, --plan for CP1
ACTA="${AID_ACCEPTANCE_ACTA:-/opt/eco/projects/acta}"
ACTA_COMMIT="9b68f91c98a0"
pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

if ! git -C "$ACTA" cat-file -e "${ACTA_COMMIT}^{commit}" 2>/dev/null; then
  echo "SKIP: ACTA at ${ACTA_COMMIT} is not on this host — the recorded evidence cites its files"
  exit 0
fi
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
git clone -q "$ACTA" "$WORK/p" && git -C "$WORK/p" checkout -q "$ACTA_COMMIT" || { echo "FAIL: cannot clone ACTA"; exit 1; }
cd "$WORK/p" || exit 1
mkdir -p .aid-o/plans .aid-o/config/policies
yq '.review_checkpoints.plan_review.reviewers[1] = {"role":"generalist_b","provider":"claude","model":"opus"}' \
  "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > .aid-o/config/policies/review-checkpoints.yaml
PLAN=.aid-o/plans/P998-acceptance-acta.md
CP1=.aid-o/work/evidence/P998/cp1

_check() { bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" "$PLAN" --json .aid-o/work/evidence/P998/plan-check.json --quiet >/dev/null 2>&1; }
# _round <n> — prepare, drop in the recorded answers, collect, close with the recorded tokens
_round() {
  local n="$1" rec="$FX/recorded/round-$1"
  bash "$ROUND" prepare --plan "$PLAN" --round "$n" >/dev/null 2>&1 || return 1
  cp "$rec"/reviewer-*.json "$CP1/round-$n/"
  bash "$ROUND" collect --plan "$PLAN" --round "$n" >/dev/null 2>&1 || return 1
  bash "$ROUND" close --plan "$PLAN" --round "$n" --tokens $(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$rec/tokens.json") >/dev/null 2>&1
}

echo "TEST: the recorded flow replays to a gate PASS"
cp "$FX/acta-p025.md" "$PLAN"; _check
_round 1 && ok "round 1 replayed" || bad "round 1 did not replay"
cp "$FX/recorded/plan-round-2.md" "$PLAN"
bash "$ROUND" fix-check --plan "$PLAN" --round 1 >/dev/null 2>&1 && ok "the round-1 fix passes fix-check" || bad "fix-check refused the recorded fix"
_check
_round 2 && ok "round 2 replayed" || bad "round 2 did not replay"
cp "$FX/recorded/plan-final.md" "$PLAN"
bash "$ROUND" finalize --plan "$PLAN" >/dev/null 2>&1 && ok "finalize accepts the last edit" || bad "finalize refused the last edit"
bash "$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh" --plan "$PLAN" >/dev/null 2>&1 && ok "the gate passes" || bad "the gate refused"

echo "TEST: the targets written before the run"
T="$FX/targets.json"
rounds="$(jq length "$CP1/rounds.json")"
(( rounds <= $(jq .max_rounds "$T") )) && ok "${rounds} rounds within max_rounds" || bad "${rounds} rounds exceed max_rounds"
for n in $(seq 1 "$rounds"); do
  # USD through the one price source (defaults/prices.yaml, aid_review_usd_blended per role).
  usd="$(jq -r '[.reviewers[] | .usd] | if any(.[]; type != "number") then "\"unknown\"" else (add | tostring) end' "$CP1/round-$n/measurement.json")"
  if [[ "$usd" != '"unknown"' ]] && awk -v u="$usd" -v m="$(jq .max_usd_per_round "$T")" 'BEGIN { exit !(u < m) }'; then
    ok "round ${n}: ${usd} USD under the ceiling"
  else
    bad "round ${n}: ${usd} USD is unknown or over the ceiling"
  fi
  missing=""
  for f in $(jq -r '.archived_files_per_round[]' "$T"); do [[ -f "$CP1/round-$n/$f" ]] || missing+=" $f"; done
  [[ -z "$missing" ]] && ok "round ${n}: every archive file present" || bad "round ${n}: missing${missing}"
  jq -e '[.findings[] | select((.command // "") == "" or (.evidence // "") == "")] | length == 0' "$CP1/round-$n/merged.json" >/dev/null \
    && ok "round ${n}: every surviving finding carries a command and an evidence" \
    || bad "round ${n}: a surviving finding lacks proof"
done

echo "Results: ${pass}/$((pass + fail)) passed, ${fail} failed"
(( fail == 0 ))
