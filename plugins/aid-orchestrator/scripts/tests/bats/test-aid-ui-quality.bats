#!/usr/bin/env bats
# aid-tier: t2
# Nightly since 3.4.0 (15. 10. 2026): the merge path overran its 10 min and the /aid-ui studio is the
# dearest area outside the core; no plan run passes through it, so a regression here shows the next morning.
# P113a step 3 - aid-ui-quality.py: rounds of the two frozen critics (owner and tech, at once) over the current site,
# each with the memory of its own findings; every finding triaged (accepted needs the expected gain, fixed needs
# evidence), the regression check before each round, stop rules (conflict, nothing to fix, three repair rounds);
# both roles at 8.5 lead to three blind ratings per role of the same web and the verdict; the cost and time of
# every round, the agent's own work included (13. 10. 2026).

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  Q="$SC/aid-ui-quality.py"; K="$SC/../skills/ui-design/critic"
  T="$BATS_TEST_TMPDIR"; P="$T/p"; mkdir -p "$P/docs/content" "$P/site" "$T/bin"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><body>chleba</body></html>' > "$P/site/index.html"
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local >/dev/null
  # three competitors already shot (aid-ui-client.py competitors)
  for c in a b c; do mkdir -p "$P/.aid-ui/critic/competitors/$c"; printf x > "$P/.aid-ui/critic/competitors/$c/index-1440.png"; printf x > "$P/.aid-ui/critic/competitors/$c/index-390.png"; done
  echo '[{"name":"A","url":"https://a.example/"},{"name":"B","url":"https://b.example/"},{"name":"C","url":"https://c.example/"}]' > "$P/.aid-ui/critic/competitors.json"
  echo '{"at":"2026-10-13T08:00:00Z","list_sha256":"'"$(sha256sum "$P/.aid-ui/critic/competitors.json" | cut -c1-64)"'","competitors":[{"name":"A","url":"https://a.example/","shots":["a/index-1440.png","a/index-390.png"]},{"name":"B","url":"https://b.example/","shots":["b/index-1440.png","b/index-390.png"]},{"name":"C","url":"https://c.example/","shots":["c/index-1440.png","c/index-390.png"]}]}' > "$P/.aid-ui/critic/competitors/manifest.json"
  # the agent's own session: a transcript the cost book reads
  export CLAUDE_CODE_SESSION_ID=test-sid AID_UI_CLAUDE_PROJECTS="$T/cc"; mkdir -p "$T/cc/proj"; : > "$T/cc/proj/test-sid.jsonl"
  export PATH="$T/bin:$PATH" AID_UI_TOOL="$T/bin/tool" AID_UI_STATE_SH="$T/bin/state"
  printf '#!/usr/bin/env bash\n[[ -e "$BATS_TEST_TMPDIR/gate-red" ]] && { echo "ERROR: gate-check refused: fail row" >&2; exit 1; }; echo GATE OK\n' > "$T/bin/state"
  cat > "$T/bin/tool" <<'SH'
#!/usr/bin/env bash
shift; out="$1"; mkdir -p "$out"; printf x > "$out/index-1440.png"; printf x > "$out/index-390.png"
echo "{\"files\": [\"$out/index-1440.png\", \"$out/index-390.png\"]}"
SH
  # codex answers as the role its prompt names (the tech rubric's first criterion is only in the tech prompt)
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
p="\$(cat)"; role=owner; grep -q "$(yq -r '.criteria[0].id' "$K/web-local.tech.yaml")" <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":100000,"cached_input_tokens":0,"output_tokens":1000}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/"*
  WPORT=$(( 38000 + RANDOM % 900 )); python3 -m http.server "$WPORT" --bind 127.0.0.1 --directory "$P/site" >/dev/null 2>&1 & WEBSRV=$!
  W="http://127.0.0.1:$WPORT/"; for _ in $(seq 50); do curl -s "$W" >/dev/null && break; sleep 0.1; done
}

teardown() { kill "$WEBSRV" 2>/dev/null || true; }

# ans <owner score> [<tech score>] [<severity of f1>]: every criterion of a role at its score, f1 by the agent, f2 by the client
ans() {
  for role in owner tech; do
    local s="$1"; [[ $role == tech ]] && s="${2:-$1}"
    python3 - "$K/web-local.$role.yaml" "$s" "${3:-major}" > "$T/ans-$role.json" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1])); _lo = (yaml.safe_load(open(__import__("re").sub(r"\.(owner|tech)\.yaml$", ".yaml", sys.argv[1]))).get("launch_only") or {}).get(__import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)) or []; r["criteria"] = [c for c in r["criteria"] if c["id"] not in _lo]; s = int(sys.argv[2]); c0 = r["criteria"][0]["id"]
import os; _role = __import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)   # P113: the web is rated with the look and structure rubrics too
r["criteria"] += [dict(c, id=k + "." + c["id"]) for k in ("vzhled", "struktura") for c in yaml.safe_load(open(os.path.dirname(sys.argv[1]) + "/web-local.%s.%s.yaml" % (_role, k)))["criteria"]]
a = None if s < 4 else max(x for x in (4, 6, 8, 10) if x <= s)
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": a, "evidence": "úvod: nadpis a fotka pece", "missing_for_next": "víc", "to_ten": {"studio": ["úvod: vlastní fotka ordinace přes celou šířku"], "client": []}}
  for c in r["criteria"]], "findings": [
  {"id": "f1", "criterion": c0, "severity": sys.argv[3], "owner": "agent", "kind": "remeslo", "text": "obecná věta", "fix": "konkrétně", "where": "úvod"},
  {"id": "f2", "criterion": c0, "severity": "major", "owner": "client", "kind": "volba", "text": "chybí fotky", "fix": "dodat", "where": "o nás"}],
  "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
  done
}
dec() { python3 "$Q" status "$P" | jq -r .decision; }
cycle() {   # triage and fix the last round's agent findings of both roles
  local n; n="$(python3 "$Q" status "$P" | jq -r .rounds)"
  for r in owner tech; do
    python3 "$Q" triage "$P" "r$n-$r-f1" accepted --expected "+1" >/dev/null && python3 "$Q" fixed "$P" "r$n-$r-f1" --evidence "úvod přepsán" --method "steps/6-build.md" >/dev/null
  done
}
work() {   # the agent works: one assistant turn in its transcript, now
  python3 -c 'import json,time,sys,random; print(json.dumps({"type":"assistant","timestamp":time.strftime("%Y-%m-%dT%H:%M:%S.000Z",time.gmtime()),"message":{"id":"m%d"%random.randrange(10**9),"model":"claude-opus-5-5","usage":{"input_tokens":1000,"cache_read_input_tokens":2000000,"output_tokens":10000}}}))' >> "$T/cc/proj/test-sid.jsonl"
}

@test "a round: both roles at once with their own findings; triage, fix with evidence, client findings to readiness; memory and cost" {
  [ "$(dec)" = round ]
  ans 6 7; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.round == 1 and .owner == 6 and .tech == 7 and .decision == "triage"' <<<"${lines[-1]}" >/dev/null
  R1="$P/.aid-ui/critic/rounds/1"
  jq -e '.score.quality_score == 6 and .score.owner == 6 and .score.tech == 7 and .provider == {"owner":"codex","tech":"codex"}
         and ([.findings[].id] | sort) == ["r1-owner-f1","r1-owner-f2","r1-tech-f1","r1-tech-f2"]
         and ([.findings[] | select(.id | endswith("f2")) | .state] | unique) == ["blocked"] and (.site_sha | length) == 64' "$R1/round.json" >/dev/null
  jq -e '.role == "owner"' "$R1/owner/run.json" >/dev/null; jq -e '.role == "tech"' "$R1/tech/run.json" >/dev/null
  [ -d "$R1/owner/bundle/podklady/konkurence" ]; [ ! -e "$R1/tech/bundle/podklady/konkurence" ]
  jq -e '(.top3.owner | length) == 1 and (.loop_usd | type) == "number"' <<<"${lines[-1]}" >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"triage"* ]]
  run python3 "$Q" triage "$P" r1-owner-f1 accepted; [ "$status" -eq 2 ]; [[ "$output" == *"--expected"* ]]
  run python3 "$Q" fixed "$P" r1-owner-f1 --evidence x --method "steps/6-build.md"; [ "$status" -eq 1 ]
  python3 "$Q" triage "$P" r1-owner-f1 accepted --expected "+1" >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 duplicate --of r1-owner-f1 >/dev/null   # the same flaw from both roles
  [ "$(dec)" = fix ]
  run python3 "$Q" fixed "$P" r1-owner-f1 --evidence "úvod přepsán"; [ "$status" -eq 2 ]; [[ "$output" == *"--method"* ]]
  run python3 "$Q" fixed "$P" r1-owner-f1 --evidence "úvod přepsán" --method "z hlavy"; [ "$status" -eq 2 ]   # z hlavy needs the why
  run python3 "$Q" fixed "$P" r1-owner-f1 --evidence "úvod přepsán" --method "hotovo"; [ "$status" -eq 2 ]    # neither a procedure nor a why
  python3 "$Q" fixed "$P" r1-owner-f1 --evidence "úvod přepsán: konkrétní věta o kvásku" --method "z hlavy: krok 6 nemá postup pro přepis úvodu" >/dev/null; [ "$(dec)" = round ]
  jq -e '.history[0].findings[] | select(.id == "r1-owner-f1") | .method | startswith("z hlavy")' "$P/.aid-ui/critic/loop.json" >/dev/null
  touch "$T/gate-red"; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"regression check"* ]]; rm "$T/gate-red"
  work; work
  ans 7; run python3 "$Q" round "$P" --web "$W"
  jq -e '.fixed_before[0].id == "r1-owner-f1" and (.fixed_before[0].method | startswith("z hlavy"))' <<<"${lines[-1]}" >/dev/null
  # memory: each role got its own findings of round 1 with what happened to them, and nothing of the other role
  jq -e '(.findings | map(.id) | sort) == ["r1-owner-f1","r1-owner-f2"] and (.findings[] | select(.id == "r1-owner-f1") | .state == "fixed" and (.evidence | contains("kvásku")))
         and .ratings[0].round == 1 and .ratings[0].scores.prvni_dojem_a_premiovost == 6 and (.ratings[0].to_ten | length) > 0' "$P/.aid-ui/critic/rounds/2/history-owner.json" >/dev/null   # P113: the previous rating too
  jq -e '.findings[0].id' "$P/.aid-ui/critic/rounds/2/tech/bundle/podklady/historie.json" | grep -q tech
  # cost and time per round: the critics, and the agent's work after round 1 belongs to round 1
  jq -e '.rounds == 2 and .scores == [6, 7] and .history[0].cost.agent_measured == true and .history[0].cost.by.agent > 2
         and .history[0].cost.by.critic > 0 and (.history[0].cost.minutes | type) == "number" and .cost_total_usd > 2' "$P/.aid-ui/critic/loop.json" >/dev/null  || { jq -c . "$P/.aid-ui/costs.jsonl"; jq -c ".history[] | {n,at,cost}" "$P/.aid-ui/critic/loop.json"; return 1; }
  run python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --force; [ "$status" -eq 1 ]
  # the owner never rates without the current competitors at both widths
  echo '[{"name":"X","url":"https://x.example/"},{"name":"B","url":"https://b.example/"},{"name":"C","url":"https://c.example/"}]' > "$P/.aid-ui/critic/competitors.json"
  cycle; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"no rating from owner"* ]]
  grep -q "competitors.json are missing" "$(ls -d "$P/.aid-ui/critic/rounds/3-failed-"*)/owner/run.json" 2>/dev/null || [[ "$output" == *"competitors"* ]]
}

@test "stops: a conflict between the roles, nothing accepted to fix, three repair rounds" {
  ans 6; python3 "$Q" round "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-owner-f1 blocked --reason "větší fotka zpomalí web" --conflict-with r1-tech-f1 >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 accepted --expected "+1" >/dev/null
  [ "$(dec)" = stop:conflict ]; python3 "$Q" status "$P" | jq -e '.why | contains("r1-owner-f1") and contains("r1-tech-f1")' >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]
}

@test "nothing accepted below acceptance stops; three repair rounds below 8.5 stop with the best round" {
  ans 6; python3 "$Q" round "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason "v podkladech" >/dev/null; done
  [ "$(dec)" = stop:stagnation ]
  rm -r "$P/.aid-ui/critic/rounds"
  for s in 6 7 8 7; do ans 9 $s; python3 "$Q" round "$P" --web "$W" >/dev/null || return 1; cycle; done
  python3 "$Q" status "$P" | jq -e '.decision == "stop:round_cap" and .repair_rounds == 3 and (.why | contains("3 repair rounds") and contains("best round 3"))' >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]
}

@test "acceptance: both roles at 8.5 stop the repairs; three blind ratings per role of the same web; a failed audit is triaged" {
  ans 9 8; python3 "$Q" round "$P" --web "$W" >/dev/null; cycle
  [ "$(dec)" = round ]   # tech under 8.5: repair on
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]
  ans 9 9 minor; python3 "$Q" round "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r2-$r-f1" rejected_with_reason --reason "slovo je v podkladech" >/dev/null; done
  [ "$(dec)" = audit ]
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.accepted == true and .roles.owner.ratings == 3 and .roles.tech.ratings == 3 and .publish_blocked_by == ["vlastní fotky"] and .round == 2' "$P/.aid-ui/critic/verdict.json" >/dev/null
  A="$(ls -d "$P/.aid-ui/critic/audits/"*)"; ls "$A"/a3/owner/answer.json "$A"/a3/tech/answer.json >/dev/null
  [ ! -e "$A/a1/owner/bundle/podklady/historie.json" ]   # an audit is blind
  [ "$(dec)" = done ]
  # an audit that does not confirm the web: the auditors' findings become an audit round to triage, no repair round
  rm "$P/.aid-ui/critic/verdict.json"; ans 9 7; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  [ "$(dec)" = triage ]
  jq -e '.audit == true and .n == 3 and (.findings | length) == 12 and (.findings | map(.id) | index("r3-a1-tech-f1")) != null and .score.tech == 7' "$P/.aid-ui/critic/rounds/3/round.json" >/dev/null
  python3 "$Q" status "$P" | jq -e '.repair_rounds == 1' >/dev/null
  for k in 1 2 3; do for r in owner tech; do python3 "$Q" triage "$P" "r3-a$k-$r-f1" rejected_with_reason --reason "v podkladech" >/dev/null; done; done
  python3 "$Q" status "$P" | jq -e '.decision == "stop:stagnation" and (.why | startswith("the audit did not confirm"))' >/dev/null
}

@test "close and best: accepted with fixes open -> close; the audit rates the accepted web; a later accepted web is audited after a failed audit; reopen" {
  ans 9; python3 "$Q" round "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-owner-f1 accepted --expected "+1" >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 rejected_with_reason --reason x >/dev/null
  [ "$(dec)" = close ]; python3 "$Q" status "$P" | jq -e '.best.round == 1 and (.why | contains("r1-owner-f1"))' >/dev/null
  cp "$P/site/index.html" "$T/best.html"; echo '<html lang="cs"><body>chleba, jinak</body></html>' > "$P/site/index.html"
  python3 "$Q" fixed "$P" r1-owner-f1 --evidence x --method "steps/6-build.md" >/dev/null; [ "$(dec)" = audit ]   # a fix is allowed, the audit still rates round 1's web
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"not the best accepted web (round 1"* ]]
  cp "$T/best.html" "$P/site/index.html"
  ans 9 7; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 3 ]
  for k in 1 2 3; do for r in owner tech; do python3 "$Q" triage "$P" "r2-a$k-$r-f1" accepted --expected "+1" >/dev/null; python3 "$Q" fixed "$P" "r2-a$k-$r-f1" --evidence y --method "steps/6-build.md" >/dev/null; done; done
  [ "$(dec)" = round ]; echo '<html lang="cs"><body>chleba, lepší</body></html>' > "$P/site/index.html"
  ans 9 9 minor; python3 "$Q" round "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r3-$r-f1" rejected_with_reason --reason x >/dev/null; done
  python3 "$Q" status "$P" | jq -e '.decision == "audit" and .best.round == 3' >/dev/null   # round 1's web failed its audit
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ]; [ "$(dec)" = done ]
  run python3 "$Q" reopen "$P"; [ "$status" -eq 2 ]
  python3 "$Q" reopen "$P" --reason "PM: odstup od čar" >/dev/null; [ "$(dec)" = round ]; ls "$P/.aid-ui/critic/verdicts/"*.json >/dev/null
  echo '<html lang="cs"><body>chleba, znovu</body></html>' > "$P/site/index.html"
  ans 9 9 minor; python3 "$Q" round "$P" --web "$W" >/dev/null
  jq -e '(.findings | length) == 0 and (.ratings | length) == 0' "$P/.aid-ui/critic/rounds/4/history-owner.json" >/dev/null   # the memory restarts at the reopen
  for r in owner tech; do python3 "$Q" triage "$P" "r4-$r-f1" rejected_with_reason --reason x >/dev/null; done
  python3 "$Q" status "$P" | jq -e '.decision == "audit" and .best.round == 4 and .repair_rounds == 0' >/dev/null
}

@test "one loop, one critic, one address; links between findings must point at another finding of the round" {
  ans 6; python3 "$Q" round "$P" --web "$W" >/dev/null
  run python3 "$Q" triage "$P" r1-owner-f1 duplicate --of r1-owner-f9; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-owner-f1 duplicate --of r1-owner-f1; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-owner-f1 accepted --expected x --conflict-with r1-tech-f1; [ "$status" -eq 2 ]
  cycle
  run python3 "$Q" round "$P" --web "${W}cennik/"; [ "$status" -eq 1 ]; [[ "$output" == *"another address"* ]]
  jq '.frozen_sha = "0000"' "$P/.aid-ui/critic/rounds/1/round.json" > "$T/r.json" && mv "$T/r.json" "$P/.aid-ui/critic/rounds/1/round.json"
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"frozen critic changed"* ]]
}

@test "what the client has not delivered is no criterion of the studio's work: the round is accepted on the studio's score" {
  mkdir -p "$P/docs/design"; echo '{"open_items": [{"id": "oi-4", "text": "vlastné fotky", "owner": "klient", "status": "open", "critical": true}]}' > "$P/docs/design/brand-state.json"
  ans 9 9 minor
  jq '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 9 | .studio_anchor = 8 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky"])' "$T/ans-owner.json" > "$T/x" && mv "$T/x" "$T/ans-owner.json"
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.owner == 9 and .owner_now < 9 and .limited_by == ["oi-4"]' <<<"${lines[-1]}" >/dev/null
  jq -e '.score.accepted == true and .score.min_criterion == 9' "$P/.aid-ui/critic/rounds/1/round.json" >/dev/null
  jq -e '.history[0].owner_now < .history[0].owner' "$P/.aid-ui/critic/loop.json" >/dev/null
  jq -e '(.to_ten.owner | length) > 0' <<<"${lines[-1]}" >/dev/null
  # a critical open item blocks publishing even when no critic lists it
  jq '.readiness = []' "$T/ans-owner.json" > "$T/x" && mv "$T/x" "$T/ans-owner.json"; jq '.readiness = []' "$T/ans-tech.json" > "$T/x" && mv "$T/x" "$T/ans-tech.json"
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason x >/dev/null; done
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.accepted and .publish_blocked_by == ["vlastné fotky"] and (.verdict | contains("zveřejnění blokuje"))' "$P/.aid-ui/critic/verdict.json" >/dev/null
}

@test "a prefix the critic copied from its memory is not doubled; ids that would clash keep their own form" {
  ans 6
  jq '.findings[0].id = "r1-owner-r1-01" | .findings[1].id = "r1-owner-r1-02"' "$T/ans-owner.json" > "$T/x" && mv "$T/x" "$T/ans-owner.json"
  jq '.findings[0].id = "r1-01" | .findings[1].id = "r2-01"' "$T/ans-tech.json" > "$T/x" && mv "$T/x" "$T/ans-tech.json"
  python3 "$Q" round "$P" --web "$W" >/dev/null
  jq -e '([.findings[].id] | sort) == ["r1-owner-01", "r1-owner-02", "r1-tech-r1-01", "r1-tech-r2-01"]' "$P/.aid-ui/critic/rounds/1/round.json" >/dev/null
}

# P113 step 2: the loop per decision place - its own rounds, cap and reopen
pans() {   # pans <place> <score>: both roles' answers of a one-result place, f1 by the agent
  for role in owner tech; do
    python3 - "$P" "$1" "$role" "$2" > "$T/ans-$role.json" <<'PY'
import json, sys
p, place, role, s = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
fz = json.load(open(p + "/.aid-ui/critic/frozen/%s.json" % place))
ids = [c["id"] for c in fz["roles"][role]["rubrics"][0]["rubric"]["criteria"]]
a = None if s < 4 else max(x for x in (4, 6, 8, 10) if x <= s)
print(json.dumps({"criteria": [{"id": i, "score": s, "anchor": a, "evidence": "dokument, oddíl 1", "missing_for_next": "víc", "to_ten": {"studio": ["oddíl 1: doložit odlišení zakázkou"], "client": []}} for i in ids],
  "findings": [{"id": "f1", "criterion": ids[0], "severity": "major", "owner": "agent", "kind": "remeslo", "text": "obecná věta", "fix": "konkrétně", "where": "oddíl 1"}],
  "readiness": [], "summary": "Místo pro test smyčky."}))
PY
  done
}
pcycle() { local n; n="$(python3 "$Q" status "$P" --place "$1" | jq -r .rounds)"
  for r in owner tech; do python3 "$Q" triage "$P" "r$n-$r-f1" accepted --expected "+1" --place "$1" >/dev/null && python3 "$Q" fixed "$P" "r$n-$r-f1" --evidence "oddíl přepsán" --method "steps/1v-vision.md" --place "$1" >/dev/null; done; }

@test "gates: place loop - a fifth round at one place is refused while another place still has its rounds" {
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --place sdeleni >/dev/null
  # the codex stub tells the roles apart by the sdeleni tech rubric's first criterion
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 6
  for i in 1 2 3 4; do
    run python3 "$Q" round "$P" --place sdeleni; [ "$status" -eq 0 ] || { echo "round $i: $output"; return 1; }
    jq -e --argjson i "$i" '.round == $i and .place == "sdeleni"' <<<"${lines[-1]}" >/dev/null
    [ -f "$P/.aid-ui/critic/rounds/sdeleni/$i/round.json" ]
    [ "$i" -eq 4 ] || pcycle sdeleni
  done
  pcycle sdeleni
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r .decision)" = "stop:round_cap" ]
  run python3 "$Q" round "$P" --place sdeleni; [ "$status" -eq 1 ]; [[ "$output" == *"round_cap"* ]]
  # the finished web has its own count: no round yet, nothing of sdeleni in rounds/<n>
  [ "$(python3 "$Q" status "$P" | jq -r '.decision + " " + (.rounds | tostring)')" = "round 0" ]
  [ ! -e "$P/.aid-ui/critic/rounds/1" ]
  # the memory at the place carries the previous rating
  jq -e '.place == "sdeleni" and (.ratings | length) == 3 and (.findings | length) == 3 and (.findings | all(.role == null and (.id | contains("-tech-"))))' "$P/.aid-ui/critic/rounds/sdeleni/4/history-tech.json" >/dev/null
}

@test "gates: place loop - a reopen of one place does not reset another; the audit is the finished web's only" {
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --place sdeleni >/dev/null
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 6; for i in 1 2 3 4; do python3 "$Q" round "$P" --place sdeleni >/dev/null; pcycle sdeleni; done
  # the web place goes on in its own folder meanwhile
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
p="\$(cat)"; role=owner; grep -q "$(yq -r '.criteria[0].id' "$K/web-local.tech.yaml")" <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  ans 6 7; python3 "$Q" round "$P" --web "$W" >/dev/null
  run python3 "$Q" reopen "$P" --place sdeleni --reason "PM chce jiný slogan"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$P/.aid-ui/critic/rounds/sdeleni/reopened.json" ]; [ ! -e "$P/.aid-ui/critic/loop-reopened.json" ]
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r '.decision + " " + (.repair_rounds | tostring)')" = "round 0" ]
  [ "$(python3 "$Q" status "$P" | jq -r '.decision + " " + (.rounds | tostring)')" = "triage 1" ]
  run python3 "$Q" audit "$P" --place sdeleni --web "$W"; [ "$status" -eq 2 ]
}
