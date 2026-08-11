#!/usr/bin/env bats
# aid-tier: t2
# test-ui-calibration-verify.bats — Prevents false-green ui_calibration_result gate
#
# Verifies that ui-calibration-verify.sh correctly rejects records that are structurally
# incomplete or contain hermetic/false-green evidence, even when result=pass.

VERIFIER=""
TMP=""

setup() {
  TMP=$(mktemp -d)
  VERIFIER="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/ui-calibration-verify.sh"

  mkdir -p "$TMP/ui-cal/cases"/{A,B,C,D-desktop,D-mobile}

  # Create valid PNG files (real PNG header: 0x89 PNG \r\n 0x1a \n)
  for case_id in A B C D-desktop D-mobile; do
    for png in baseline.png regressed.png rerun.png; do
      printf '\x89PNG\r\n\x1a\n' > "$TMP/ui-cal/cases/$case_id/$png"
    done
    for json_file in baseline-computed.json regressed-computed.json rerun-computed.json; do
      printf '{"url":"http://localhost:3911/","selector":"section[aria-label=\\"Co pot\\u0159ebuju v\\u011bd\\u011bt\\"]","text_content":"Co pot\\u0159ebuju v\\u011bd\\u011bt","viewport":{"width":1280,"height":720},"bbox":{},"computed_styles":{},"captured_at":"2026-06-30T12:00:00Z","target_id":"screeng-root"}' \
        > "$TMP/ui-cal/cases/$case_id/$json_file"
    done
    printf '{"verdict":"fail","checks":{}}' > "$TMP/ui-cal/cases/$case_id/first-run-verdict.json"
    printf '{"verdict":"pass","checks":{}}' > "$TMP/ui-cal/cases/$case_id/rerun-verdict.json"
  done
}

teardown() {
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Helper: write a valid record.json with all 5 cases
# ---------------------------------------------------------------------------
write_valid_record() {
  python3 - "$TMP" <<'PYEOF'
import json, sys, os
root = sys.argv[1]

def make_case(cid, is_d=False):
    case = {
        "case_id": cid,
        "description": f"Case {cid}",
        "first_run": "fail",
        "first_run_reason": "test_reason",
        "rerun": "pass",
        "evidence_dir": f"ui-cal/cases/{cid}",
        "artifacts": {
            "baseline_png":       f"ui-cal/cases/{cid}/baseline.png",
            "regressed_png":      f"ui-cal/cases/{cid}/regressed.png",
            "rerun_png":          f"ui-cal/cases/{cid}/rerun.png",
            "baseline_computed":  f"ui-cal/cases/{cid}/baseline-computed.json",
            "regressed_computed": f"ui-cal/cases/{cid}/regressed-computed.json",
            "rerun_computed":     f"ui-cal/cases/{cid}/rerun-computed.json",
            "first_run_verdict":  f"ui-cal/cases/{cid}/first-run-verdict.json",
            "rerun_verdict":      f"ui-cal/cases/{cid}/rerun-verdict.json",
        },
    }
    if is_d:
        vp = {"width": 1280, "height": 720} if cid == "D-desktop" else {"width": 375, "height": 812}
        case["real_surface"] = {
            "app": "aid-gui",
            "route": "/",
            "component": "ScreenG",
            "selector": "section[aria-label=\"Co potřebuju vědět\"]",
            "url": "http://localhost:3911/",
            "viewport": vp,
            "assertions": {},
            "captured_text_content": "Co potřebuju vědět",
            "captured_bbox": {},
        }
    return case

record = {
    "calibration": {
        "schema_version": "1.1.0",
        "run_at": "2026-06-30T12:00:00Z",
        "cases": [
            make_case("A"),
            make_case("B"),
            make_case("C"),
            make_case("D-desktop", is_d=True),
            make_case("D-mobile", is_d=True),
        ],
        "result": "pass",
        "pm_signoff": {"confirmed_by": None, "confirmed_at": None, "notes": None}
    }
}
os.makedirs(f"{root}/ui-cal", exist_ok=True)
with open(f"{root}/ui-cal/ui-calibration-record.json", "w") as f:
    json.dump(record, f, indent=2)
PYEOF
}

# ---------------------------------------------------------------------------
# PASS case
# ---------------------------------------------------------------------------

@test "valid complete record: verifier passes" {
  write_valid_record
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FAIL cases — false-green prevention
# ---------------------------------------------------------------------------

@test "result=pass but baseline.png missing: verifier fails" {
  write_valid_record
  rm "$TMP/ui-cal/cases/A/baseline.png"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "baseline.png" ]]
}

@test "result=pass but baseline-computed.json missing: verifier fails" {
  write_valid_record
  rm "$TMP/ui-cal/cases/C/baseline-computed.json"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "result=pass but artifacts field missing from record: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
del r['calibration']['cases'][0]['artifacts']
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "D case with hermetic:// URL: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
for c in r['calibration']['cases']:
    if c['case_id'] == 'D-desktop':
        c['real_surface']['url'] = 'hermetic://screeng-mock'
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "hermetic" ]]
}

@test "D case with DETERMINISTIC in text_content: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
for c in r['calibration']['cases']:
    if c['case_id'] == 'D-mobile':
        c['real_surface']['captured_text_content'] = 'DETERMINISTIC'
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "DETERMINISTIC" ]]
}

@test "D case missing real_surface: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
for c in r['calibration']['cases']:
    if c['case_id'] == 'D-desktop':
        del c['real_surface']
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "real_surface" ]]
}

@test "first-run-verdict.json says pass but record says first_run=fail: verifier fails" {
  write_valid_record
  printf '{"verdict":"pass","checks":{}}' > "$TMP/ui-cal/cases/B/first-run-verdict.json"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "rerun-verdict.json says fail but record says rerun=pass: verifier fails" {
  write_valid_record
  printf '{"verdict":"fail","checks":{}}' > "$TMP/ui-cal/cases/A/rerun-verdict.json"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "baseline.png is not a valid PNG (plain text): verifier fails" {
  write_valid_record
  echo "not a png" > "$TMP/ui-cal/cases/A/baseline.png"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "baseline-computed.json is not valid JSON: verifier fails" {
  write_valid_record
  echo "not json" > "$TMP/ui-cal/cases/A/baseline-computed.json"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "D case with wrong viewport dimensions: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
for c in r['calibration']['cases']:
    if c['case_id'] == 'D-desktop':
        c['real_surface']['viewport'] = {'width': 800, 'height': 600}
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" =~ "viewport" ]]
}

@test "D case with hermetic selector: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
for c in r['calibration']['cases']:
    if c['case_id'] == 'D-desktop':
        c['real_surface']['selector'] = '[data-testid=\"hermetic-box\"]'
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "calibration result=fail in record: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
r['calibration']['result'] = 'fail'
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}

@test "record with fewer than 5 cases: verifier fails" {
  write_valid_record
  python3 -c "
import json
r = json.load(open('$TMP/ui-cal/ui-calibration-record.json'))
r['calibration']['cases'] = r['calibration']['cases'][:3]
json.dump(r, open('$TMP/ui-cal/ui-calibration-record.json', 'w'), indent=2)
"
  run bash "$VERIFIER" "$TMP/ui-cal/ui-calibration-record.json" "$TMP" 2>&1
  [ "$status" -eq 1 ]
}
