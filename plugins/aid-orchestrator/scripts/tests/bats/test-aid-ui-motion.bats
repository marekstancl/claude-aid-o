#!/usr/bin/env bats
# aid-tier: t2
# P108 motion — aid-ui-tool.sh motion observes a page's motion at runtime (lib/ui-fidelity/
# aid-ui-motion.mjs) over the fixture motion-site: an intro overlay shown on the first load only,
# a hero fade-up, a reveal below the fold on scroll, an infinite spin below, hover/focus
# transitions on the button, a leave animation on the link and an arrive animation on the
# second page. The record follows motion-record.schema.json.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FX="$BATS_TEST_DIRNAME/../fixtures/aid-ui/motion-site"
  T="$BATS_TEST_TMPDIR"; OUT="$T/motion.json"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FX" >/dev/null 2>&1 &
  SRV=$!
  for _ in $(seq 1 30); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/index.html" && break; sleep 0.2; done
}
teardown() { kill "$SRV" 2>/dev/null || true; }

kf() { jq -r --arg n "$1" ".keyframes[] | select(.name == \$n) | $2" "$OUT"; }

@test "motion: every planted motion is seen in its scenario, where and frequency; the page transition both ways; the record passes its schema" {
  run bash "$SC/aid-ui-tool.sh" motion "http://127.0.0.1:$PORT/index.html" "$OUT" --settle-ms 4000
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(kf leave '.where | join(",")')" == overlay ]
  [ "$(kf leave '.frequency')" == first_load_only ]
  [ "$(kf leave '.intro')" == true ]
  [ "$(kf pop '.where | join(",")')" == hero ]
  [ "$(kf spin '.where | join(",")')" == below ]
  [ "$(kf spin '.iteration')" == infinite ]
  [ "$(kf spin '.frequency')" == every_load ]
  [ "$(kf fadeup '.scenarios | join(",")')" == "load,scroll" ]
  [[ "$(kf fadeup '.where | join(",")')" == *below* ]]
  jq -e '[.transitions[] | select(.scenario == "hover") | .property] | sort == ["background-color", "color"]' "$OUT" >/dev/null
  jq -e '[.transitions[] | select(.scenario == "focus")] | length == 2' "$OUT" >/dev/null
  jq -e '.page.observed and (.page.leave | any(startswith("keyframes:fadeout@body"))) and (.page.arrive | any(startswith("keyframes:arrive@body"))) and (.page.arrived_at | endswith("druha.html"))' "$OUT" >/dev/null
  jq -e '.coverage.stylesheets == 1 and .coverage.errors == [] and (.sha256 | length) == 64' "$OUT" >/dev/null
  python3 - "$SC/../skills/ui-design/references/motion-record.schema.json" "$OUT" <<'PY'
import json, sys
from jsonschema.validators import Draft202012Validator
s = json.load(open(sys.argv[1])); r = json.load(open(sys.argv[2]))
errs = list(Draft202012Validator(s).iter_errors(r))
assert not errs, [e.message for e in errs][:3]
del r["coverage"]
assert list(Draft202012Validator(s).iter_errors(r)), "a record without coverage must be refused"
PY
}

@test "motion: a page that does not load is exit 1, usage is exit 2" {
  run bash "$SC/aid-ui-tool.sh" motion "http://127.0.0.1:$PORT/neni.html" "$OUT"
  [ "$status" -eq 1 ]
  run bash "$SC/aid-ui-tool.sh" motion "not-a-url" "$OUT"
  [ "$status" -eq 2 ]
}

@test "motion --dir: the tool serves the folder itself on a loopback port and records the folder's sha (the same as aid-ui-motion.py dirsha); a missing folder is exit 2" {
  run bash "$SC/aid-ui-tool.sh" motion --dir "$FX" "$OUT" --settle-ms 3000
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$(jq -r .url "$OUT")" == http://127.0.0.1:* ]]
  [ "$(jq -r .dir_sha256 "$OUT")" == "$(python3 "$SC/aid-ui-motion.py" dirsha "$FX")" ]
  [ "$(kf leave '.frequency')" == first_load_only ]
  jq -e '.page.observed and (.page.arrived_at | endswith("druha.html"))' "$OUT" >/dev/null
  run bash "$SC/aid-ui-tool.sh" motion --dir "$T/neni" "$OUT"
  [ "$status" -eq 2 ]
}
