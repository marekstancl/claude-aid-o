#!/usr/bin/env bats
# aid-tier: t1
# P113a step 3 - aid-ui-quality.py: rounds of the frozen critic over the current site, every finding triaged
# (accepted needs the expected gain, fixed needs evidence), the regression check before each round, stop rules
# (conflict, stagnation, round cap), acceptance leads to three blind ratings of the same web and the verdict.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  Q="$SC/aid-ui-quality.py"
  T="$BATS_TEST_TMPDIR"; P="$T/p"; mkdir -p "$P/docs/content" "$P/site" "$T/bin"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><body>chleba</body></html>' > "$P/site/index.html"
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local >/dev/null
  export PATH="$T/bin:$PATH" AID_UI_TOOL="$T/bin/tool" AID_UI_STATE_SH="$T/bin/state" ANS="$T/ans.json"
  printf '#!/usr/bin/env bash\n[[ -e "$BATS_TEST_TMPDIR/gate-red" ]] && { echo "ERROR: gate-check refused: fail row" >&2; exit 1; }; echo GATE OK\n' > "$T/bin/state"
  cat > "$T/bin/tool" <<'SH'
#!/usr/bin/env bash
shift; out="$1"; mkdir -p "$out"; printf x > "$out/index-1440.png"; printf x > "$out/index-390.png"
echo "{\"files\": [\"$out/index-1440.png\", \"$out/index-390.png\"]}"
SH
  cat > "$T/bin/codex" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}}))' "$ANS"
SH
  chmod +x "$T/bin/"*
  WPORT=$(( 38000 + RANDOM % 900 )); python3 -m http.server "$WPORT" --bind 127.0.0.1 --directory "$P/site" >/dev/null 2>&1 & WEBSRV=$!
  W="http://127.0.0.1:$WPORT/"; for _ in $(seq 50); do curl -s "$W" >/dev/null && break; sleep 0.1; done
}

teardown() { kill "$WEBSRV" 2>/dev/null || true; }

# ans <score> [<severity of the agent finding f1>]: every criterion at <score>, f1 by the agent, f2 by the client
ans() {
  python3 - "$SC/../skills/ui-design/critic/web-local.yaml" "$1" "${2:-major}" > "$ANS" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1])); s = int(sys.argv[2])
a = None if s < 4 else max(x for x in (4, 6, 8, 10) if x <= s)
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": a, "evidence": "úvod: nadpis a fotka pece", "missing_for_next": "víc"}
  for c in r["criteria"]], "findings": [
  {"id": "f1", "criterion": "copy", "severity": sys.argv[3], "owner": "agent", "text": "obecná věta", "fix": "konkrétně", "where": "úvod"},
  {"id": "f2", "criterion": "trust", "severity": "major", "owner": "client", "text": "chybí fotky", "fix": "dodat", "where": "o nás"}],
  "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
}
dec() { python3 "$Q" status "$P" | jq -r .decision; }
cycle() {   # triage and fix the last round's agent finding
  local n; n="$(python3 "$Q" status "$P" | jq -r .rounds)"
  python3 "$Q" triage "$P" "r$n-f1" accepted --expected "copy +1" >/dev/null && python3 "$Q" fixed "$P" "r$n-f1" --evidence "úvod přepsán" >/dev/null
}

@test "a round: findings triaged before anything else, accepted needs the expected gain, fixed needs evidence, client findings go to readiness" {
  [ "$(dec)" = round ]
  ans 6; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.round == 1 and .quality_score == 6 and .decision == "triage"' <<<"${lines[-1]}" >/dev/null
  jq -e '.findings[1].state == "blocked" and .findings[1].id == "r1-f2" and (.site_sha | length) == 64' "$P/.aid-ui/critic/rounds/1/round.json" >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"triage"* ]]
  run python3 "$Q" triage "$P" r1-f1 accepted; [ "$status" -eq 2 ]; [[ "$output" == *"--expected"* ]]
  run python3 "$Q" triage "$P" r1-f1 maybe --reason x; [ "$status" -eq 2 ]
  run python3 "$Q" fixed "$P" r1-f1 --evidence x; [ "$status" -eq 1 ]
  python3 "$Q" triage "$P" r1-f1 accepted --expected "copy +1" >/dev/null; [ "$(dec)" = fix ]
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"fix"* ]]
  python3 "$Q" fixed "$P" r1-f1 --evidence "úvod přepsán: konkrétní věta o kvásku" >/dev/null; [ "$(dec)" = round ]
  # the regression check holds the next round back while the gate is red
  touch "$T/gate-red"; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"regression check"* ]]; rm "$T/gate-red"
  ans 7; python3 "$Q" round "$P" --web "$W" >/dev/null
  jq -e '.rounds == 2 and .scores == [6, 7] and (.history | length) == 2 and .history[0].findings[0].evidence != null' "$P/.aid-ui/critic/loop.json" >/dev/null
  # the rubric is locked once the loop has rounds
  run python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --force; [ "$status" -eq 1 ]
}

@test "stops: a conflict between findings, two repair rounds without gain, the round cap" {
  ans 6; python3 "$Q" round "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-f1 blocked --reason "kratší úvod zhorší důvěru" --conflict-with r1-f2 >/dev/null
  [ "$(dec)" = stop:conflict ]; python3 "$Q" status "$P" | jq -e '.why | contains("r1-f1") and contains("r1-f2")' >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]
  # stagnation: 6, 6, 6 with the same findings
  python3 "$Q" triage "$P" r1-f1 accepted --expected "+1" >/dev/null; python3 "$Q" fixed "$P" r1-f1 --evidence x >/dev/null
  for _ in 1 2; do python3 "$Q" round "$P" --web "$W" >/dev/null; cycle; done
  [ "$(dec)" = stop:stagnation ]
}

@test "round cap: five repair rounds below acceptance stop with the reason" {
  for s in 2 3 4 5 6 7; do ans $s; python3 "$Q" round "$P" --web "$W" >/dev/null || return 1; cycle; done   # +1 every round
  python3 "$Q" status "$P" | jq -e '.decision == "stop:round_cap" and .repair_rounds == 5 and (.why | contains("5 repair rounds"))' >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]
}

@test "acceptance: improving on toward 10, then three blind ratings of the same web; the verdict names what blocks publishing" {
  ans 8; python3 "$Q" round "$P" --web "$W" >/dev/null; cycle
  [ "$(dec)" = round ]   # accepted at 8 but a fix is in: rate again, toward 10
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]
  ans 8 minor; python3 "$Q" round "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r2-f1 rejected_with_reason --reason "slovo je v podkladech" >/dev/null
  [ "$(dec)" = audit ]
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.accepted == true and .ratings == 3 and .publish_blocked_by == ["vlastní fotky"] and .round == 2' "$P/.aid-ui/critic/verdict.json" >/dev/null
  ls "$P/.aid-ui/critic/audits/"*/a3/answer.json >/dev/null
  [ "$(dec)" = done ]
  jq -e '.decision == "done" and .rounds == 2' "$P/.aid-ui/critic/loop.json" >/dev/null
  # an audit that does not confirm the web: the auditors' findings become an audit round to triage, no repair round
  rm "$P/.aid-ui/critic/verdict.json"; ans 7; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  [ "$(dec)" = triage ]
  jq -e '.audit == true and .n == 3 and (.findings | length) == 6 and .findings[0].id == "r3-a1-f1" and .findings[1].state == "blocked"' "$P/.aid-ui/critic/rounds/3/round.json" >/dev/null
  python3 "$Q" status "$P" | jq -e '.repair_rounds == 1' >/dev/null
  for k in 1 2 3; do python3 "$Q" triage "$P" "r3-a$k-f1" rejected_with_reason --reason "v podkladech" >/dev/null; done
  python3 "$Q" status "$P" | jq -e '.decision == "stop:stagnation" and (.why | startswith("the audit did not confirm"))' >/dev/null
}

@test "close and best: improvement ends with accepted findings still open -> close; the audit rates the best accepted web, not the last" {
  ans 9; python3 "$Q" round "$P" --web "$W" >/dev/null; cycle
  cp "$P/site/index.html" "$T/best.html"; echo '<html lang="cs"><body>chleba, horší</body></html>' > "$P/site/index.html"
  ans 8; python3 "$Q" round "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r2-f1 accepted --expected "+1" >/dev/null
  [ "$(dec)" = close ]; python3 "$Q" status "$P" | jq -e '.best.round == 1 and (.why | contains("r2-f1"))' >/dev/null
  run python3 "$Q" fixed "$P" r2-f1 --evidence x; [ "$status" -eq 0 ]   # fixing is allowed, but the audit still rates round 1's web
  python3 "$Q" triage "$P" r2-f1 superseded --reason "zlepšení skončilo" >/dev/null; [ "$(dec)" = audit ]
  ans 9 minor; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"not the best accepted web (round 1"* ]]
  cp "$T/best.html" "$P/site/index.html"
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.round == 1 and .accepted' "$P/.aid-ui/critic/verdict.json" >/dev/null; [ "$(dec)" = done ]
}

@test "one loop, one critic, one address; links between findings must point at another finding of the round" {
  ans 6; python3 "$Q" round "$P" --web "$W" >/dev/null
  run python3 "$Q" triage "$P" r1-f1 duplicate --of r1-f9; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-f1 duplicate --of r1-f1; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-f1 accepted --expected x --conflict-with r1-f2; [ "$status" -eq 2 ]
  python3 "$Q" triage "$P" r1-f1 accepted --expected "+1" >/dev/null; python3 "$Q" fixed "$P" r1-f1 --evidence x >/dev/null
  run python3 "$Q" round "$P" --web "${W}cennik/"; [ "$status" -eq 1 ]; [[ "$output" == *"another address"* ]]
  jq '.frozen_sha = "0000"' "$P/.aid-ui/critic/rounds/1/round.json" > "$T/r.json" && mv "$T/r.json" "$P/.aid-ui/critic/rounds/1/round.json"
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"frozen critic changed"* ]]
}
