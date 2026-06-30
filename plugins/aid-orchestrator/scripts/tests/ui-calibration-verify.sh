#!/usr/bin/env bash
# ui-calibration-verify.sh — Validates calibration evidence completeness and D real-surface assertions
#
# Usage:
#   bash ui-calibration-verify.sh <record_json_path> [<evidence_root>]
#
# Where evidence_root is the directory containing ui-cal/ (e.g. the run evidence dir).
# Defaults to two levels up from the record file (record is at ui-cal/ui-calibration-record.json).
#
# Exit 0 = all checks pass
# Exit 1 = one or more failures (details printed to stderr)

set -euo pipefail

RECORD="${1:-}"
if [[ -z "$RECORD" ]]; then
  echo "Usage: bash ui-calibration-verify.sh <record_json_path> [<evidence_root>]" >&2
  exit 1
fi

# evidence_root is the parent of ui-cal/ — so paths like "ui-cal/cases/A/baseline.png" resolve
EVIDENCE_ROOT="${2:-$(realpath "$(dirname "$RECORD")/../..")}"

FAILURES=0
fail() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

# 1. Record exists and is valid JSON
[[ -f "$RECORD" ]] || { echo "FAIL: record not found: $RECORD" >&2; exit 1; }
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$RECORD" 2>/dev/null || { echo "FAIL: record is not valid JSON: $RECORD" >&2; exit 1; }

# 2. result == "pass"
RESULT=$(python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print(r['calibration']['result'])" "$RECORD" 2>/dev/null || echo "error")
[[ "$RESULT" == "pass" ]] || fail "calibration.result is '$RESULT', expected 'pass'"

# 3. Exactly 5 cases: A, B, C, D-desktop, D-mobile
CASE_COUNT=$(python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print(len(r['calibration']['cases']))" "$RECORD" 2>/dev/null || echo "0")
[[ "$CASE_COUNT" -eq 5 ]] || fail "expected 5 cases, got $CASE_COUNT"

EXPECTED_CASES=("A" "B" "C" "D-desktop" "D-mobile")
for expected_id in "${EXPECTED_CASES[@]}"; do
  FOUND=$(python3 -c "
import json, sys
r = json.load(open(sys.argv[1]))
cases = r['calibration']['cases']
match = [c['case_id'] for c in cases if c['case_id'] == sys.argv[2]]
print(match[0] if match else '')
" "$RECORD" "$expected_id" 2>/dev/null || echo "")
  [[ "$FOUND" == "$expected_id" ]] || fail "case '$expected_id' not found in record"
done

# 4. Per-case: first_run=fail, rerun=pass, first_run_reason non-empty, artifacts present, D real_surface
VERIFY_FAILURES=$(RECORD_PATH="$RECORD" EVIDENCE_ROOT_PATH="$EVIDENCE_ROOT" python3 - <<'PYEOF'
import json, sys, os
from pathlib import Path

record_path = os.environ['RECORD_PATH']
evidence_root = Path(os.environ['EVIDENCE_ROOT_PATH'])
failures = []

def is_valid_png(path):
    """Check that file starts with PNG signature."""
    try:
        with open(path, 'rb') as f:
            sig = f.read(8)
            return sig == b'\x89PNG\r\n\x1a\n'
    except Exception:
        return False

def is_valid_json(path):
    try:
        json.load(open(path))
        return True
    except Exception:
        return False

REQUIRED_ARTIFACTS = [
    'baseline_png', 'regressed_png', 'rerun_png',
    'baseline_computed', 'regressed_computed', 'rerun_computed',
    'first_run_verdict', 'rerun_verdict',
]

record = json.load(open(record_path))

for case in record['calibration']['cases']:
    cid = case['case_id']

    # first_run must be fail
    if case.get('first_run') != 'fail':
        failures.append(f"[{cid}] first_run={case.get('first_run')!r}, expected 'fail'")

    # rerun must be pass
    if case.get('rerun') != 'pass':
        failures.append(f"[{cid}] rerun={case.get('rerun')!r}, expected 'pass'")

    # first_run_reason must be non-empty
    reason = case.get('first_run_reason', '').strip()
    if not reason:
        failures.append(f"[{cid}] first_run_reason is empty")

    # artifacts field must exist
    artifacts = case.get('artifacts')
    if not artifacts:
        failures.append(f"[{cid}] artifacts field missing from record")
        continue

    for art_key in REQUIRED_ARTIFACTS:
        art_path_rel = artifacts.get(art_key)
        if not art_path_rel:
            failures.append(f"[{cid}] artifacts.{art_key} is missing from record")
            continue
        art_path = evidence_root / art_path_rel
        if not art_path.exists():
            failures.append(f"[{cid}] artifact not found on disk: {art_path_rel}")
            continue

        # Validate PNG files
        if art_key.endswith('_png'):
            if not is_valid_png(art_path):
                failures.append(f"[{cid}] {art_key} is not a valid PNG: {art_path_rel}")
        # Validate JSON files
        elif art_key.endswith('_computed') or art_key.endswith('_verdict'):
            if not is_valid_json(art_path):
                failures.append(f"[{cid}] {art_key} is not valid JSON: {art_path_rel}")

    # Cross-check verdict files vs record values
    first_verdict_rel = artifacts.get('first_run_verdict', '')
    if first_verdict_rel:
        first_verdict_path = evidence_root / first_verdict_rel
        if first_verdict_path.exists() and is_valid_json(first_verdict_path):
            verdict_data = json.load(open(first_verdict_path))
            actual_verdict = verdict_data.get('verdict', '')
            if actual_verdict != case.get('first_run'):
                failures.append(f"[{cid}] first-run-verdict.json says verdict={actual_verdict!r} but record says first_run={case.get('first_run')!r}")

    rerun_verdict_rel = artifacts.get('rerun_verdict', '')
    if rerun_verdict_rel:
        rerun_verdict_path = evidence_root / rerun_verdict_rel
        if rerun_verdict_path.exists() and is_valid_json(rerun_verdict_path):
            verdict_data = json.load(open(rerun_verdict_path))
            actual_verdict = verdict_data.get('verdict', '')
            if actual_verdict != case.get('rerun'):
                failures.append(f"[{cid}] rerun-verdict.json says verdict={actual_verdict!r} but record says rerun={case.get('rerun')!r}")

    # D cases: real_surface assertions
    if cid in ('D-desktop', 'D-mobile'):
        real_surface = case.get('real_surface')
        if not real_surface:
            failures.append(f"[{cid}] real_surface field missing — cannot prove real ScreenG was captured")
        else:
            url = real_surface.get('url', '')
            if url.startswith('hermetic://'):
                failures.append(f"[{cid}] real_surface.url is hermetic:// — this is a hermetic fallback, not real ScreenG")
            if not (url.startswith('http://localhost:') or url.startswith('http://10.')):
                failures.append(f"[{cid}] real_surface.url={url!r} doesn't look like a local dev server")

            selector = real_surface.get('selector', '')
            if 'Co potřebuju vědět' not in selector and 'aria-label' not in selector:
                failures.append(f"[{cid}] real_surface.selector={selector!r} doesn't look like ScreenG selector")

            text = real_surface.get('captured_text_content', '')
            if 'Co potřebuju vědět' not in text:
                failures.append(f"[{cid}] real_surface.captured_text_content doesn't contain 'Co potřebuju vědět' — may not be real ScreenG")
            if 'DETERMINISTIC' in text:
                failures.append(f"[{cid}] real_surface.captured_text_content contains 'DETERMINISTIC' — this is a hermetic capture, not real ScreenG")

            # Viewport assertions
            expected_viewport = {
                'D-desktop': {'width': 1280, 'height': 720},
                'D-mobile': {'width': 375, 'height': 812},
            }
            expected = expected_viewport.get(cid, {})
            actual_vp = real_surface.get('viewport', {})
            if actual_vp.get('width') != expected.get('width') or actual_vp.get('height') != expected.get('height'):
                failures.append(f"[{cid}] real_surface.viewport={actual_vp} doesn't match expected {expected}")

            # Also check baseline-computed.json directly
            baseline_key = artifacts.get('baseline_computed', '')
            if baseline_key:
                baseline_path = evidence_root / baseline_key
                if baseline_path.exists():
                    baseline_data = json.load(open(baseline_path))
                    bc_url = baseline_data.get('url', '')
                    if bc_url.startswith('hermetic://'):
                        failures.append(f"[{cid}] baseline-computed.json has url={bc_url!r} — hermetic URL in real capture data")
                    bc_text = baseline_data.get('text_content', '')
                    if 'DETERMINISTIC' in bc_text:
                        failures.append(f"[{cid}] baseline-computed.json text_content contains 'DETERMINISTIC'")

if failures:
    for msg in failures:
        print(msg, file=sys.stderr)
    sys.exit(1)
else:
    print(f"All {len(record['calibration']['cases'])} cases verified.")
    sys.exit(0)
PYEOF
)
PY_EXIT=$?

if [[ $PY_EXIT -ne 0 ]]; then
  FAILURES=$((FAILURES + 1))
fi

if [[ $FAILURES -gt 0 ]]; then
  echo "ui-calibration-verify: $FAILURES top-level check(s) failed" >&2
  exit 1
fi

echo "ui-calibration-verify: PASS"
exit 0
