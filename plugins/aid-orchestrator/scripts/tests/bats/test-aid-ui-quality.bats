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
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; export SC
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
  # P113: role calls go to Claude Opus first; these cases stub Codex, so Codex goes first and a real Claude is never
  # reachable from a test (a stub that fails loudly: no model call in any test, llm-test-cost-control)
  export AID_UI_ROLE_FIRST=codex
  export AID_UI_VERIFY_HOME="$T/verify-home" AID_UI_VERIFY_KEY="$T/verify.key"   # P118: verify records never in the real home
  printf '#!/usr/bin/env bash\necho "a real claude was called from a test" >&2; exit 1\n' > "$T/bin/claude"
  printf '#!/usr/bin/env bash\n[[ -e "$BATS_TEST_TMPDIR/gate-red" ]] && { echo "ERROR: gate-check refused: fail row" >&2; exit 1; }; echo GATE OK\n' > "$T/bin/state"
  cat > "$T/bin/tool" <<'SH'
#!/usr/bin/env bash
shift; out="$1"; mkdir -p "$out"; printf x > "$out/index-1440.png"; printf x > "$out/index-390.png"
echo "{\"files\": [\"$out/index-1440.png\", \"$out/index-390.png\"]}"
SH
  # codex answers as the role its prompt names (the tech rubric's first criterion is only in the tech prompt)
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "$(yq -r '.criteria[0].id' "$K/web-local.tech.yaml")" <<<"\$p" && role=tech
grep -q "# Co po tobě studio chce" <<<"\$p" && role=supply
grep -q "nezávislý ověřovatel verze" <<<"\$p" && role=verify
grep -q "^Jsi soudce" <<<"\$p" && role=judge
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":100000,"cached_input_tokens":0,"output_tokens":1000}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/"*
  WPORT=$(( 38000 + RANDOM % 900 )); while ss -ltnH "sport = :$WPORT" | grep -q .; do WPORT=$(( 38000 + RANDOM % 900 )); done   # a port another process holds answers 404
  python3 -m http.server "$WPORT" --bind 127.0.0.1 --directory "$P/site" >/dev/null 2>&1 & WEBSRV=$!
  W="http://127.0.0.1:$WPORT/"; for _ in $(seq 50); do curl -s "$W" >/dev/null && break; sleep 0.1; done
}

teardown() { kill "$WEBSRV" 2>/dev/null || true; }

# selfdoc [score] [place] - the producer's own check of the place (every criterion of both frozen roles at the score)
selfdoc() {
  python3 - "$P" "${1:-9}" "${2:-web}" > "$T/self.json" <<'PY2'
import json, os, sys
p, sc, pl = sys.argv[1], float(sys.argv[2]), sys.argv[3]
f = os.path.join(p, ".aid-ui/critic", "frozen.json" if pl == "web" else "frozen/%s.json" % pl)
rec = json.load(open(f)); out = {}
for r in ("owner", "tech"):
    out[r] = {("" if e["key"] == pl else e["key"] + ".") + c["id"]: {"score": sc, "evidence": "úvod: nadpis a cena chleba"}
              for e in rec["roles"][r]["rubrics"] for c in e["rubric"]["criteria"]}
doc = {"requirements": [{"id": "r1", "source": "docs/content/product-context.md:2", "text": "Kváskový chleba v Brně", "covered_by": ["index.html"]}]}
print(json.dumps(doc))
PY2
}
# verified [place] - the signed record a verifier run over the version now would write (FIXCHECK=nepravda: a fix not
# seen; WHOLE_OPEN=<text>: an open point; FIXCHECK=none: no record); the real command has its own case below
verified() {
  [[ "${FIXCHECK:-}" == none ]] && return 0
  python3 - "$P" "${1:-web}" <<'PY2'
import importlib.util, json, os, sys
sys.path.insert(0, os.environ["SC"] + "/lib"); import aid_ui_memory as m
spec = importlib.util.spec_from_file_location("c", os.environ["SC"] + "/aid-ui-client.py"); c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
p, pl = sys.argv[1], sys.argv[2]
art = c.site_sha(os.path.join(p, "site")) if pl == "web" else c.place_bundle(p, pl)[1]
rs = m.rounds(p, pl)
fx = {f["id"]: {"verdict": os.environ.get("FIXCHECK", "overeno"), "where": "page /", "seen": "úvod: nová věta je vidět"} for f in (rs[-1]["findings"] if rs else []) if f.get("state") == "accepted" and f.get("evidence")}
m.verify_append(p, pl, {"artifact": art, "at": "t", "provider": "test", "round": rs[-1]["n"] if rs else 0, "fixes": fx, "open": [{"where": "index", "what": os.environ["WHOLE_OPEN"]}] if os.environ.get("WHOLE_OPEN") else []})
PY2
}
# qround <project> [args] - a round after the producer's own check of the current version (PM 18. 10. 2026)
qround() {
  local pl=web a; for a in "$@"; do [[ "${prev:-}" == --place ]] && pl="$a"; prev="$a"; done; prev=""
  [[ -f "$P/.aid-ui/critic/$([[ $pl == web ]] && echo frozen.json || echo frozen/$pl.json)" ]] && selfdoc 9 "$pl" && verified "$pl" && { python3 "$Q" self "$P" --place "$pl" --file "$T/self.json" >/dev/null || return; }
  python3 "$Q" round "$@" || return
  supply_missing "$pl"
}
# supply_missing [place] - the client role answered every item of the last round as missing (what the loop did
# before P116: client findings stay blocked); the real supply has its own cases below
supply_missing() {
  python3 - "$P" "${1:-web}" <<'PY2'
import json, os, sys
sys.path.insert(0, os.environ["SC"] + "/lib"); import aid_ui_memory as m
p, pl = sys.argv[1], sys.argv[2]
items = m.unsupplied(p, pl)
if items:
    t = ".aid-ui/client/turns/supply-%s-r%d-1" % (pl.replace("-", ""), items[0]["round"]); os.makedirs(os.path.join(p, t), exist_ok=True)
    json.dump({"answer": {"items": [{"key": i["key"], "status": "missing", "missing": "klient dodá později"} for i in items]}}, open(os.path.join(p, t, "turn.json"), "w"))
    f = m.supply_file(p, pl); os.makedirs(os.path.dirname(f), exist_ok=True)
    cur = m.supply_records(p, pl)
    cur.update({i["key"]: dict(i, status="missing", missing="klient dodá později", turn=t) for i in items})
    json.dump({"place": pl, "items": cur}, open(f, "w"))
PY2
}

# ans <owner score> [<tech score>] [<severity of f1>]: every criterion of a role at its score, f1 by the agent, f2 by the client
ans() {
  for role in owner tech; do
    local s="$1"; [[ $role == tech ]] && s="${2:-$1}"
    python3 - "$K/web-local.$role.yaml" "$s" "${3:-major}" > "$T/ans-$role.json" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1])); _lo = (yaml.safe_load(open(__import__("re").sub(r"\.(owner|tech)\.yaml$", ".yaml", sys.argv[1]))).get("launch_only") or {}).get(__import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)) or []; r["criteria"] = [c for c in r["criteria"] if c["id"] not in _lo or __import__("os").environ.get("ANS_LAUNCH")]; s = int(sys.argv[2]); c0 = r["criteria"][0]["id"]
import os; _role = __import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)   # P113: the web is rated with the look and structure rubrics too
r["criteria"] += [dict(c, id=k + "." + c["id"]) for k in ("vzhled", "struktura") for c in yaml.safe_load(open(os.path.dirname(sys.argv[1]) + "/web-local.%s.%s.yaml" % (_role, k)))["criteria"]]
a = None if s < 4 else max(x for x in (4, 6, 8, 10) if x <= s)
print(json.dumps({"criteria": [{"id": c["id"], "score": s, "anchor": a, "evidence": "úvod: nadpis a fotka pece", "missing_for_next": "víc", "to_ten": {"studio": ["úvod: vlastní fotka ordinace přes celou šířku"], "client": []}}
  for c in r["criteria"]], "findings": [
  {"id": "f1", "criterion": c0, "severity": sys.argv[3], "owner": "agent", "kind": "remeslo", "blocking": False, "text": "obecná věta", "fix": "konkrétně", "where": "úvod"},
  {"id": "f2", "criterion": c0, "severity": "major", "owner": "client", "kind": "remeslo", "blocking": False, "text": "chybí fotky", "fix": "dodat", "where": "o nás"}],
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
  ans 6 7; run qround "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.round == 1 and .owner == 6 and .tech == 7 and .decision == "triage"' <<<"${lines[-1]}" >/dev/null
  R1="$P/.aid-ui/critic/rounds/1"
  jq -e '.score.quality_score == 6 and .score.owner == 6 and .score.tech == 7 and .provider == {"owner":"codex","tech":"codex"}
         and ([.findings[].id] | sort) == ["r1-owner-f1","r1-owner-f2","r1-tech-f1","r1-tech-f2"]
         and ([.findings[] | select(.id | endswith("f2")) | .state] | unique) == ["blocked"] and (.site_sha | length) == 64' "$R1/round.json" >/dev/null
  jq -e '.role == "owner"' "$R1/owner/run.json" >/dev/null; jq -e '.role == "tech"' "$R1/tech/run.json" >/dev/null
  [ -d "$R1/owner/bundle/podklady/konkurence" ]; [ ! -e "$R1/tech/bundle/podklady/konkurence" ]
  jq -e '(.top3.owner | length) == 1 and (.loop_usd | type) == "number"' <<<"${lines[-1]}" >/dev/null
  run qround "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"triage"* ]]
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
  touch "$T/gate-red"; run qround "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"regression check"* ]]; rm "$T/gate-red"
  work; work
  ans 7; run qround "$P" --web "$W"
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
  cycle; run qround "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"no rating from owner"* ]]
  grep -q "competitors.json are missing" "$(ls -d "$P/.aid-ui/critic/rounds/3-failed-"*)/owner/run.json" 2>/dev/null || [[ "$output" == *"competitors"* ]]
}

@test "stops: a conflict between the roles, nothing accepted to fix, three repair rounds" {
  ans 6; qround "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-owner-f1 blocked --reason "větší fotka zpomalí web" --conflict-with r1-tech-f1 >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 accepted --expected "+1" >/dev/null
  [ "$(dec)" = stop:conflict ]; python3 "$Q" status "$P" | jq -e '.why | contains("r1-owner-f1") and contains("r1-tech-f1")' >/dev/null
  run qround "$P" --web "$W"; [ "$status" -eq 1 ]
}

@test "nothing accepted below acceptance stops; three repair rounds below 8.5 stop with the best round" {
  ans 6; qround "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason "v podkladech" >/dev/null; done
  [ "$(dec)" = stop:stagnation ]
  rm -r "$P/.aid-ui/critic/rounds"
  for s in 6 7 8 7; do ans 9 $s; qround "$P" --web "$W" >/dev/null || return 1; cycle; done
  python3 "$Q" status "$P" | jq -e '.decision == "stop:round_cap" and .repair_rounds == 3 and (.why | contains("3 repair rounds") and contains("best round 3"))' >/dev/null
  run qround "$P" --web "$W"; [ "$status" -eq 1 ]
}

@test "acceptance: both roles at 8.5 stop the repairs; three blind ratings per role of the same web; a failed audit is triaged" {
  ans 9 8; qround "$P" --web "$W" >/dev/null; cycle
  [ "$(dec)" = round ]   # tech under 8.5: repair on
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]
  ans 9 9 minor; qround "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r2-$r-f1" rejected_with_reason --reason "slovo je v podkladech" >/dev/null; done
  [ "$(dec)" = audit ]
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.accepted == true and .roles.owner.ratings == 3 and .roles.tech.ratings == 3 and .publish_blocked_by == ["vlastní fotky"] and .round == 2' "$P/.aid-ui/critic/verdict.json" >/dev/null
  A="$(ls -d "$P/.aid-ui/critic/audits/"*)"; ls "$A"/a3/owner/answer.json "$A"/a3/tech/answer.json >/dev/null
  [ ! -e "$A/a1/owner/bundle/podklady/historie.json" ]   # an audit is blind
  [ "$(dec)" = done ]
  # an audit that does not confirm the web: the auditors' findings become an audit round to triage, no repair round
  rm "$P/.aid-ui/critic/verdict.json"; ans 9 7; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 3 ] || { echo "$output"; return 1; }; supply_missing
  [ "$(dec)" = triage ]
  jq -e '.audit == true and .n == 3 and (.findings | length) == 12 and (.findings | map(.id) | index("r3-a1-tech-f1")) != null and .score.tech == 7' "$P/.aid-ui/critic/rounds/3/round.json" >/dev/null
  python3 "$Q" status "$P" | jq -e '.repair_rounds == 1' >/dev/null
  for k in 1 2 3; do for r in owner tech; do python3 "$Q" triage "$P" "r3-a$k-$r-f1" rejected_with_reason --reason "v podkladech" >/dev/null; done; done
  python3 "$Q" status "$P" | jq -e '.decision == "stop:stagnation" and (.why | startswith("the audit did not confirm"))' >/dev/null
}

@test "close and best: accepted with fixes open -> close; the audit rates the accepted web; a later accepted web is audited after a failed audit; reopen" {
  ans 9; qround "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-owner-f1 accepted --expected "+1" >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 rejected_with_reason --reason x >/dev/null
  [ "$(dec)" = close ]; python3 "$Q" status "$P" | jq -e '.best.round == 1 and (.why | contains("r1-owner-f1"))' >/dev/null
  cp "$P/site/index.html" "$T/best.html"; echo '<html lang="cs"><body>chleba, jinak</body></html>' > "$P/site/index.html"
  python3 "$Q" fixed "$P" r1-owner-f1 --evidence x --method "steps/6-build.md" >/dev/null; [ "$(dec)" = audit ]   # a fix is allowed, the audit still rates round 1's web
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"not the best accepted web (round 1"* ]]
  cp "$T/best.html" "$P/site/index.html"
  ans 9 7; run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 3 ]; supply_missing
  for k in 1 2 3; do for r in owner tech; do python3 "$Q" triage "$P" "r2-a$k-$r-f1" accepted --expected "+1" >/dev/null; python3 "$Q" fixed "$P" "r2-a$k-$r-f1" --evidence y --method "steps/6-build.md" >/dev/null; done; done
  [ "$(dec)" = round ]; echo '<html lang="cs"><body>chleba, lepší</body></html>' > "$P/site/index.html"
  ans 9 9 minor; qround "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r3-$r-f1" rejected_with_reason --reason x >/dev/null; done
  python3 "$Q" status "$P" | jq -e '.decision == "audit" and .best.round == 3' >/dev/null   # round 1's web failed its audit
  run python3 "$Q" audit "$P" --web "$W"; [ "$status" -eq 0 ]; [ "$(dec)" = done ]
  run python3 "$Q" reopen "$P"; [ "$status" -eq 2 ]
  python3 "$Q" reopen "$P" --reason "PM: odstup od čar" >/dev/null; [ "$(dec)" = round ]; ls "$P/.aid-ui/critic/verdicts/"*.json >/dev/null
  echo '<html lang="cs"><body>chleba, znovu</body></html>' > "$P/site/index.html"
  ans 9 9 minor; qround "$P" --web "$W" >/dev/null
  jq -e '(.findings | length) > 0 and (.ratings | length) > 0' "$P/.aid-ui/critic/rounds/4/history-owner.json" >/dev/null   # P118: the memory survives the reopen
  for r in owner tech; do python3 "$Q" triage "$P" "r4-$r-f1" rejected_with_reason --reason x >/dev/null; done
  python3 "$Q" status "$P" | jq -e '.decision == "audit" and .best.round == 4 and .repair_rounds == 0' >/dev/null
}

@test "one loop, one critic, one address; links between findings must point at another finding of the round" {
  ans 6; qround "$P" --web "$W" >/dev/null
  run python3 "$Q" triage "$P" r1-owner-f1 duplicate --of r1-owner-f9; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-owner-f1 duplicate --of r1-owner-f1; [ "$status" -eq 1 ]
  run python3 "$Q" triage "$P" r1-owner-f1 accepted --expected x --conflict-with r1-tech-f1; [ "$status" -eq 2 ]
  cycle
  run qround "$P" --web "${W}cennik/"; [ "$status" -eq 1 ]; [[ "$output" == *"another address"* ]]
  jq '.frozen_sha = "0000"' "$P/.aid-ui/critic/rounds/1/round.json" > "$T/r.json" && mv "$T/r.json" "$P/.aid-ui/critic/rounds/1/round.json"
  run qround "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"frozen critic changed"* ]]
}

@test "what the client has not delivered is no criterion of the studio's work: the round is accepted on the studio's score" {
  mkdir -p "$P/docs/design"; echo '{"open_items": [{"id": "oi-4", "text": "vlastné fotky", "owner": "klient", "status": "open", "critical": true}]}' > "$P/docs/design/brand-state.json"
  ans 9 9 minor
  jq '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 9 | .studio_anchor = 8 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky"])' "$T/ans-owner.json" > "$T/x" && mv "$T/x" "$T/ans-owner.json"
  run qround "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
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
  qround "$P" --web "$W" >/dev/null
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
  "findings": [{"id": "f1", "criterion": ids[0], "severity": "major", "owner": "agent", "kind": "remeslo", "blocking": False, "text": "obecná věta", "fix": "konkrétně", "where": "oddíl 1"}],
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
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 6
  for i in 1 2 3 4; do
    run qround "$P" --place sdeleni; [ "$status" -eq 0 ] || { echo "round $i: $output"; return 1; }
    jq -e --argjson i "$i" '.round == $i and .place == "sdeleni"' <<<"${lines[-1]}" >/dev/null
    [ -f "$P/.aid-ui/critic/rounds/sdeleni/$i/round.json" ]
    [ "$i" -eq 4 ] || pcycle sdeleni
  done
  pcycle sdeleni
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r .decision)" = "stop:round_cap" ]
  run qround "$P" --place sdeleni; [ "$status" -eq 1 ]; [[ "$output" == *"round_cap"* ]]
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
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 6; for i in 1 2 3 4; do qround "$P" --place sdeleni >/dev/null; pcycle sdeleni; done
  # the web place goes on in its own folder meanwhile
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "$(yq -r '.criteria[0].id' "$K/web-local.tech.yaml")" <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  ans 6 7; qround "$P" --web "$W" >/dev/null
  run python3 "$Q" reopen "$P" --place sdeleni --reason "PM chce jiný slogan"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$P/.aid-ui/critic/rounds/sdeleni/reopened.json" ]; [ ! -e "$P/.aid-ui/critic/loop-reopened.json" ]
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r '.decision + " " + (.repair_rounds | tostring)')" = "round 0" ]
  [ "$(python3 "$Q" status "$P" | jq -r '.decision + " " + (.rounds | tostring)')" = "triage 1" ]
  run python3 "$Q" audit "$P" --place sdeleni --web "$W"; [ "$status" -eq 2 ]
}

@test "gates: place loop - the path to 10 of a place with directions is read per direction (the logo round crashed on it)" {
  run python3 -c '
import importlib.util as u, sys
s = u.spec_from_file_location("q", sys.argv[1]); m = u.module_from_spec(s); s.loader.exec_module(m)
t = {"studio": ["x"], "client": []}; e = {"studio": [], "client": []}
one = {"directions": [{"id": "pm", "criteria": [{"id": "myslenka", "to_ten": t}, {"id": "typografie", "to_ten": e}]}]}
two = {"directions": [{"id": "a", "criteria": [{"id": "myslenka", "to_ten": t}]}, {"id": "b", "criteria": [{"id": "myslenka", "to_ten": t}]}]}
flat = {"criteria": [{"id": "poznam_se", "to_ten": t}]}
assert m.criteria_to_ten(one) == {"myslenka": t}, m.criteria_to_ten(one)
assert sorted(m.criteria_to_ten(two)) == ["a:myslenka", "b:myslenka"]
assert m.criteria_to_ten(flat) == {"poznam_se": t}
print("ok")' "$BATS_TEST_DIRNAME/../../aid-ui-quality.py"
  [ "$status" -eq 0 ] && [ "$output" = ok ] || { echo "$output"; return 1; }
}

# ── P115: the launch rating - the same loop over the live address in .aid-ui/critic/launch ──────────────────────────
# snap — sha of every file of the build loop (everything under .aid-ui/critic but launch/)
snap() { (cd "$P/.aid-ui/critic" && find . -path ./launch -prune -o -type f -print | sort | xargs sha256sum); }

@test "launch: the launch loop writes only under launch/ and leaves the build loop's files byte-identical; frozen in phase launch rates the launch-only criteria" {
  ans 6 7; qround "$P" --web "$W" >/dev/null
  before="$(snap)"
  ANS_LAUNCH=1 ans 9 9 minor
  run python3 "$Q" launch "$P" --url "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(snap)" = "$before" ]
  L="$P/.aid-ui/critic/launch"
  jq -e '.phase == "launch" and .type == "web-local"' "$L/frozen.json" >/dev/null
  jq -e '[.roles.tech.rubrics[].criteria[]?.id] | index("bezpecnost_spusteni") != null' "$L/frozen.json" >/dev/null || \
    jq -e 'tostring | contains("bezpecnost_spusteni")' "$L/frozen.json" >/dev/null
  jq -e '.n == 1 and .web == "'"$W"'"' "$L/rounds/1/round.json" >/dev/null
  # the build loop is still where it was: round 1 to triage
  [ "$(dec)" = triage ]
  [ "$(python3 "$Q" status "$P" --launch | jq -r .decision)" = triage ]
}

@test "launch: the verdict uses the web gates; launch-status passes for the deployment it rated" {
  ANS_LAUNCH=1 ans 9 9 minor
  python3 "$Q" launch "$P" --url "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason "v podkladech" --launch >/dev/null; done
  [ "$(python3 "$Q" status "$P" --launch | jq -r .decision)" = audit ]
  run python3 "$Q" audit "$P" --web "$W" --launch; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  L="$P/.aid-ui/critic/launch"
  jq -e '.accepted == true and .url == "'"$W"'" and .owner >= 8.5 and .tech >= 8.5' "$L/launch-verdict.json" >/dev/null
  [ ! -e "$P/.aid-ui/critic/verdict.json" ]   # the build's verdict is not written by the launch audit
  run python3 "$Q" launch-status "$P"; [ "$status" -eq 0 ]
  # the gates the launch verdict applied are the web place's gate files (aid-ui-critic.py verdict reads them from frozen)
  jq -e '.roles.owner.gates == ("'"$(jq -c .roles.owner.gates "$P/.aid-ui/critic/frozen.json" | sed 's/"/\\"/g')"'" | fromjson)' "$L/frozen.json" >/dev/null
  run python3 "$Q" launch "$P" --url "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"accepted already"* ]]
  # another package than the project's own is refused; a directory the variable may not name is refused
  echo '{"site": {"sha256": "x"}}' > "$T/jiny.json"
  run python3 "$Q" launch-status "$P" --package "$T/jiny.json"; [ "$status" -eq 1 ]; [[ "$output" == *"docs/ui/predani.json"* ]]
  AID_UI_CRITIC_DIR=/tmp run python3 "$Q" status "$P"; [ "$status" -ne 0 ]; [[ "$output" == *"may only be"* ]]
}

@test "launch: stale deployment - a verdict for another address or an older site is refused at the launch point" {
  ANS_LAUNCH=1 ans 9 9 minor
  python3 "$Q" launch "$P" --url "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason x --launch >/dev/null; done
  mkdir -p "$P/docs/ui"; echo '{"site": {"sha256": "'"$(printf a%.0s {1..64})"'"}}' > "$P/docs/ui/predani.json"
  python3 "$Q" audit "$P" --web "$W" --launch >/dev/null
  jq -n --arg u "$W" '{url: $u}' > "$P/docs/ui/nasazeni.json"
  run python3 "$Q" launch-status "$P" --package "$P/docs/ui/predani.json"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo '{"site": {"sha256": "'"$(printf b%.0s {1..64})"'"}}' > "$P/docs/ui/predani.json"
  run python3 "$Q" launch-status "$P" --package "$P/docs/ui/predani.json"; [ "$status" -eq 1 ]; [[ "$output" == *"another web"* ]]
  echo '{"site": {"sha256": "'"$(printf a%.0s {1..64})"'"}}' > "$P/docs/ui/predani.json"
  jq -n '{url: "https://jinde.example/"}' > "$P/docs/ui/nasazeni.json"
  run python3 "$Q" launch-status "$P" --package "$P/docs/ui/predani.json"; [ "$status" -eq 1 ]; [[ "$output" == *"rate the deployed address"* ]]
}

@test "launch: no --url is a usage error; an address that does not answer stops before any role call" {
  run python3 "$Q" launch "$P"; [ "$status" -eq 2 ]
  run python3 "$Q" launch "$P" --url "$W" --reopen "znovu"; [ "$status" -eq 2 ]; [[ "$output" == *"no launch rating to reopen"* ]]
  printf '#!/usr/bin/env bash\necho "a role was called" >&2; exit 1\n' > "$T/bin/codex"
  run python3 "$Q" launch "$P" --url "http://127.0.0.1:9/"; [ "$status" -eq 1 ]; [[ "$output" == *"does not answer"* ]]
  [ ! -e "$P/.aid-ui/critic/launch/frozen.json" ]
}


@test "self: no round without the check of this version; a requirement without a source or cover, a stale check refuse it" {
  ans 9; selfdoc 9; verified web
  run python3 "$Q" round "$P" --web "$W"
  [ "$status" -eq 1 ]; [[ "$output" == *"no round: the version is not ready for the roles - vlastní kontrola chybí"* ]]
  jq '.requirements[0].source = "docs/content/product-context.md:99"' "$T/self.json" > "$T/s2.json"
  run python3 "$Q" self "$P" --file "$T/s2.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"není soubor:řádek v projektu"* ]]
  jq 'del(.requirements[0].covered_by)' "$T/self.json" > "$T/s2.json"
  run python3 "$Q" self "$P" --file "$T/s2.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"buď covered_by"*"nebo out_of_scope"* ]]
  jq '.requirements[0] |= (del(.covered_by) | .out_of_scope = "pekárna neprodává po internetu")' "$T/self.json" > "$T/s2.json"
  run python3 "$Q" self "$P" --file "$T/s2.json"; [ "$status" -eq 0 ]
  # a check over another version of the site does not let the round run
  python3 "$Q" self "$P" --file "$T/self.json" >/dev/null
  echo '<html lang="cs"><body>chleba a rohlíky</body></html>' > "$P/site/index.html"
  run python3 "$Q" round "$P" --web "$W"
  [ "$status" -eq 1 ]; [[ "$output" == *"nad jinou verzí podkladů místa"* ]]
}

@test "self: a fix whose evidence carries a cut character is recorded, not crashed on" {
  ans 6; qround "$P" --web "$W" >/dev/null
  id="$(jq -r '.findings[0].id' "$P/.aid-ui/critic/rounds/1/round.json")"
  python3 "$Q" triage "$P" "$id" accepted --expected x >/dev/null
  run python3 "$Q" fixed "$P" "$id" --evidence "$(printf 'oprava \xc3')" --method "steps/6-build.md 3a"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# supply_ans <how> - the client's answer to the last round's items: the owner's f2 a fact (good | badquote | studio
# source), the tech's f2 an owner's choice, the readiness missing
supply_ans() {
  python3 - "$P" "$1" > "$T/ans-supply.json" <<'PY2'
import json, os, sys
sys.path.insert(0, os.environ["SC"] + "/lib"); import aid_ui_memory as m
p, how = sys.argv[1], sys.argv[2]
out = []
for i in m.supply_items(p, "web"):
    if i["kind"] == "readiness":
        out.append({"key": i["key"], "status": "missing", "missing": "fotky dodá majitel"})
    elif i["role"] == "tech":
        out.append({"key": i["key"], "status": "decided", "decided_kind": "naming", "answer": "Galerie", "reason": "tak tomu říkají zákazníci"})
    else:
        src = {"good": ("docs/content/product-context.md:2", "Kváskový chleba v Brně"), "badquote": ("docs/content/product-context.md:2", "Rohlíky z Prahy a okolí"),
               "studio": ("site/index.html:1", "chleba</body>"), "dotted": ("./site/index.html:1", "chleba</body>")}[how]
        out.append({"key": i["key"], "status": "supplied", "answer": "pečeme kváskový chleba", "source": src[0], "quote": src[1]})
print(json.dumps({"items": out}))
PY2
}

@test "supply: what the roles left to the client is answered by the client role before the next round - a fact with its quoted source, an owner's choice, or missing" {
  ans 6 7; selfdoc 9 web; verified web; python3 "$Q" self "$P" --place web --file "$T/self.json" >/dev/null
  python3 "$Q" round "$P" --web "$W" >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" accepted --expected "+1" >/dev/null; done
  [ "$(dec)" = supply ]; python3 "$Q" status "$P" | jq -r .why | grep -q "aid-ui-client.py supply"
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"supply"* ]]
  # a quote that is not on the cited line, or the studio's own output as the source: refused, nothing recorded
  for how in badquote studio dotted; do
    supply_ans "$how"; run python3 "$SC/aid-ui-client.py" supply "$P" --place web
    [ "$status" -eq 1 ]; [ ! -e "$P/.aid-ui/client/supplied/web.json" ]
  done
  grep -q "the quote is not on docs/content/product-context.md:2" "$P"/.aid-ui/client/turns/supply-web-r1-1/turn.json
  grep -q "what the studio wrote" "$P"/.aid-ui/client/turns/supply-web-r1-2/turn.json
  # a record typed in by hand (no client run behind it) is no record
  mkdir -p "$P/.aid-ui/client/supplied"; python3 -c 'import json,sys,os; sys.path.insert(0, os.environ["SC"]+"/lib"); import aid_ui_memory as m
json.dump({"items": {i["key"]: dict(i, status="decided", answer="x", turn="ruka") for i in m.supply_items(sys.argv[1], "web")}}, open(sys.argv[1]+"/.aid-ui/client/supplied/web.json", "w"))' "$P"
  [ "$(dec)" = supply ]; rm "$P/.aid-ui/client/supplied/web.json"
  supply_ans good; run python3 "$SC/aid-ui-client.py" supply "$P" --place web; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '[.items[] | .status] | sort == ["decided","missing","supplied"]' "$P/.aid-ui/client/supplied/web.json" >/dev/null
  jq -e '[.items[] | select(.status == "supplied")][0] | .source == "docs/content/product-context.md:2" and .provider == "codex" and (.turn | startswith(".aid-ui/client/turns/supply-web-r1-"))' "$P/.aid-ui/client/supplied/web.json" >/dev/null
  # a record edited by hand (the client's run said otherwise) or a fact whose quote left its source is no record
  F="$P/.aid-ui/client/supplied/web.json"; cp "$F" "$T/sup.json"
  jq '(.items[] | select(.status == "supplied") | .answer) = "pečeme rohlíky"' "$T/sup.json" > "$F"; [ "$(dec)" = supply ]; cp "$T/sup.json" "$F"
  cp "$P/docs/content/product-context.md" "$T/pc.md"; sed -i 's/Kváskový/Pšeničný/' "$P/docs/content/product-context.md"; [ "$(dec)" = supply ]
  cp "$T/pc.md" "$P/docs/content/product-context.md"
  # answered client findings go back to the agent; the missing readiness stays the PM's and stops nothing
  [ "$(dec)" = triage ]; python3 "$Q" status "$P" | jq -r .why | grep -q "r1-owner-f2"
  run python3 "$SC/aid-ui-client.py" supply "$P" --place web; [[ "$output" == *"nothing left"* ]]
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f2" accepted --expected "+1" >/dev/null; python3 "$Q" fixed "$P" "r1-$r-f2" --evidence "o nás: kváskový chleba" --method "steps/6-build.md" >/dev/null; done
  for r in owner tech; do python3 "$Q" fixed "$P" "r1-$r-f1" --evidence "úvod přepsán" --method "steps/6-build.md" >/dev/null; done
  [ "$(dec)" = round ]
  # the roles see what the client supplied
  ans 7; qround "$P" --web "$W" >/dev/null
  jq -e '.items | length == 3' "$P/.aid-ui/critic/rounds/2/owner/bundle/podklady/klient-dodal.json" >/dev/null
  grep -q "klient-dodal.json" "$P/.aid-ui/critic/rounds/2/tech/prompt.md"
  # what the client decided without the PM, and what is left to the PM
  run python3 "$SC/aid-ui-client.py" decided "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"Dodal z podkladů"*"zdroj docs/content/product-context.md:2: „Kváskový chleba v Brně“"* ]]
  [[ "$output" == *"Rozhodl jako vlastník"*"Galerie (naming; tak tomu říkají zákazníci)"* ]]
  [[ "$output" == *"Zbývá na PM"*"vlastní fotky → fotky dodá majitel"* ]]
}

@test "supply: a client finding the client could not supply stays blocked; with nothing else to fix the loop stops and says it waits on the client" {
  ans 6 7; qround "$P" --web "$W" >/dev/null   # qround: the client answered every item as missing
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason "úvod je konkrétní" >/dev/null; done
  run python3 "$Q" status "$P"
  jq -e '.decision == "stop:stagnation" and (.why | contains("waits on what the client has not supplied (r1-owner-f2, r1-tech-f2)"))' <<<"$output" >/dev/null || { echo "$output"; return 1; }
}

@test "round (P118 1A): the verifier runs with the roles when no record is over this version; its open points and the fixes it did not see are findings of the round" {
  ans 6 7; qround "$P" --web "$W" >/dev/null; cycle
  echo '<p>opraveno</p>' >> "$P/site/index.html"   # the fixed version: no verifier record over it yet
  selfdoc 9 web; python3 "$Q" self "$P" --place web --file "$T/self.json" >/dev/null   # no verifier record is needed before the round
  echo '{"fixes": {"r1-owner-f1": {"verdict": "nepravda", "seen": "věta je pořád obecná", "where": "site/index.html:1"}, "r1-tech-f1": {"verdict": "overeno", "seen": "opraveno", "where": "site/index.html:1"}},
    "open": [{"where": "site/index.html:1", "what": "cena 10 na úvodu, 12 v ceníku", "why": "dvě čísla"}]}' > "$T/ans-verify.json"
  ans 7 7; run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$P/.aid-ui/critic/rounds/2/verify.log" ]; supply_missing web
  jq -e '(.verify | length) >= 1 and (.verify[0].sig | length) > 10' "$P/.aid-ui/critic/rounds/2/round.json" >/dev/null   # the signed records the verify findings come from
  H="$(python3 "$Q" status "$P")"
  jq -e '[.history[-1].findings[] | select(.role == "verify") | .text] | (index("cena 10 na úvodu, 12 v ceníku") != null) and (map(test("^oprava r1-owner-f1 ve verzi nepravda")) | any) and (map(test("r1-tech-f1")) | any | not)' <<<"$H" >/dev/null || { jq -c '[.history[-1].findings[] | select(.role == "verify")]' <<<"$H"; return 1; }
  # a verifier that gives no valid answer: no round
  cycle; for f in $(jq -r '.history[-1].findings[] | select(.role == "verify") | .id' <<<"$H"); do python3 "$Q" triage "$P" "$f" rejected_with_reason --reason "test" >/dev/null; done
  echo 'nic' > "$T/ans-verify.json"; printf 'x' >> "$P/site/index.html"
  selfdoc 9 web; python3 "$Q" self "$P" --place web --file "$T/self.json" >/dev/null
  run python3 "$Q" round "$P" --web "$W"; [ "$status" -eq 1 ] || { echo "$output" | tail -3; return 1; }; [[ "$output" == *"no rating from verify"* ]] || { echo "$output" | tail -3; return 1; }
}

@test "verify (P118): the command captures the version, asks the verifier, signs the record; open points and unseen fixes exit 3" {
  ans 6 7; qround "$P" --web "$W" >/dev/null; cycle
  ids="$(python3 "$Q" status "$P" | jq -c '[.history[-1].findings[] | select(.state == "accepted" and .evidence) | .id]')"
  jq -n --argjson i "$ids" '{fixes: ([$i[] | {key: ., value: {verdict: "overeno", where: "page /", seen: "index: nová věta"}}] | from_entries), open: []}' > "$T/ans-verify.json"
  run python3 "$SC/aid-ui-client.py" verify "$P" --place web --web "$W"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"VERIFY web over"*"0 open, fixes 2/2 seen"* ]]
  d="$(ls -d "$P"/.aid-ui/verify/*-web | tail -1)"; jq -e '."page /" | contains("chleba")' "$d/capture.json" >/dev/null
  grep -q "nezávislý ověřovatel verze" "$d/prompt.md"; grep -q "r1-owner-f1" "$d/prompt.md"
  selfdoc 9 web; run python3 "$Q" self "$P" --place web --file "$T/self.json"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq '.open = [{where: "page /", what: "cena 10 tady, 12 jinde"}]' "$T/ans-verify.json" > "$T/a2" && mv "$T/a2" "$T/ans-verify.json"
  run python3 "$SC/aid-ui-client.py" verify "$P" --place web --web "$W"; [ "$status" -eq 3 ]
  run python3 "$Q" self "$P" --place web --file "$T/self.json"; [ "$status" -eq 0 ]   # P118 1A: an open point does not stop the round, it is its finding
  jq '.open = [] | .fixes[] .where = "nikde"' "$T/ans-verify.json" > "$T/a2" && mv "$T/a2" "$T/ans-verify.json"   # a place that is neither a capture key nor file:line
  run python3 "$SC/aid-ui-client.py" verify "$P" --place web --web "$W"; [ "$status" -eq 1 ]
  mkdir -p "$T/old"; echo '<html lang="cs"><body>stará verze</body></html>' > "$T/old/index.html"   # an address serving another version than the files
  OP=$(( 38900 + RANDOM % 90 )); python3 -m http.server $OP --bind 127.0.0.1 --directory "$T/old" >/dev/null 2>&1 & OS=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$OP/" >/dev/null && break; sleep 0.1; done
  run python3 "$SC/aid-ui-client.py" verify "$P" --place web --web "http://127.0.0.1:$OP/"; kill $OS
  [ "$status" -eq 1 ]; [[ "$output" == *"serves another version"* ]]
  echo '{"fixes": {}, "open": []}' > "$T/ans-verify.json"   # a fix without a verdict is no valid answer (twice, then the stand-in fails)
  run python3 "$SC/aid-ui-client.py" verify "$P" --place web --web "$W"; [ "$status" -eq 1 ]
}

@test "facts (P118): two independent readers at once; the judge pairs the same claim at any lines, a contradiction blocks the lint, one reader's fact only informs; agreed facts persist; a stale quote fails" {
  mkdir -p "$P/src" "$P/docs/design"
  printf 'def on_rejected_sl(p):\n    close_market(p)\n    pause()\n' > "$P/src/execute.py"
  printf '# Roadmapa\nOdmítnutý SL → okamžité zavření marketem + alert.\n' > "$P/docs/content/roadmap.md"
  F1='{"id": "sl-odmitnut", "kind": "observed_current", "statement": "Odmítnutý SL appka zavře trhem a pozastaví se.", "conditions": "SL nejde nastavit", "result": "zavření a pauza", "unwanted": "pozice bez SL", "sources": [{"source": "src/execute.py:1-3", "quote": "close_market(p)", "source_kind": "code"}]}'
  F2='{"id": "zavreni-sl", "kind": "observed_current", "statement": "Když SL nejde nastavit, appka pozici zavře trhem a pozastaví se.", "sources": [{"source": "src/execute.py:2", "quote": "close_market(p)", "source_kind": "code"}]}'
  F3='{"id": "jen-codex", "kind": "assumption", "statement": "Alert jde i do Telegramu.", "sources": [{"source": "docs/content/roadmap.md:2", "quote": "zavření marketem + alert", "source_kind": "roadmap"}]}'
  echo "{\"facts\": [$F1, $F3]}" > "$T/ans-owner.json"   # the Codex stub answers what the owner file holds for a prompt without the tech rubric
  printf '#!/usr/bin/env bash\ncat >/dev/null; python3 -c '"'"'import json,sys; print(json.dumps({"result": open(sys.argv[1]).read(), "usage": {}}))'"'"' "%s"\n' "$T/ans-claude.json" > "$T/bin/claude"
  echo "{\"facts\": [$F2]}" > "$T/ans-claude.json"
  echo '{"same": [], "conflict": []}' > "$T/ans-judge.json"   # nothing paired: all three only inform, nothing blocks
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.facts | length) == 0 and (.open | length) == 0 and ([.unconfirmed[].fact.id] | sort) == ["jen-codex", "sl-odmitnut", "zavreni-sl"]' "$P/docs/design/app-facts.json" >/dev/null
  echo '{"same": [{"a": 0, "b": 0}]}' > "$T/ans-judge.json"   # the same claim under other ids and other lines
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.facts | map(.id)) == ["sl-odmitnut"] and .facts[0].agreed_by == ["codex", "opus"] and (.unconfirmed | map(.fact.id)) == ["jen-codex"]' "$P/docs/design/app-facts.json" >/dev/null || { jq -c '[.facts[].id, [.unconfirmed[].fact.id]]' "$P/docs/design/app-facts.json"; return 1; }
  # a pair the judge calls both the same and a contradiction is no valid answer: nothing written
  echo '{"same": [{"a": 1, "b": 0}], "conflict": [{"a": 1, "b": 0, "why": "x"}]}' > "$T/ans-judge.json"
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 1 ]
  # a pair of different kinds is no agreement even when the judge says so; the fact agreed before stays (it is in O)
  echo '{"same": [{"a": 1, "b": 0}]}' > "$T/ans-judge.json"
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.facts | map(.id)) == ["sl-odmitnut"] and (.open | length) == 0' "$P/docs/design/app-facts.json" >/dev/null
  # restated by a fact agreed now: replaced, not kept twice
  echo '{"same": [{"a": 0, "b": 0}], "restated": [{"o": 0, "a": 0}]}' > "$T/ans-judge.json"
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ]; jq -e '(.facts | map(.id)) == ["sl-odmitnut"]' "$P/docs/design/app-facts.json" >/dev/null
  # a contradiction is open; a fact agreed before that a reader now contradicts leaves the facts and is open too
  echo '{"same": [], "conflict": [{"a": 1, "b": 0, "why": "alert vs pauza"}], "disputed": [{"o": 0, "b": 0, "why": "jiný výsledek"}]}' > "$T/ans-judge.json"
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '(.facts | length) == 0 and ([.open[].fact.id] | sort) == ["spor-jen-codex", "spor-sl-odmitnut"]' "$P/docs/design/app-facts.json" >/dev/null || { jq -c '[.facts[].id, [.open[].fact.id]]' "$P/docs/design/app-facts.json"; return 1; }
  jq -e '[.unconfirmed[].fact.id] == ["sl-odmitnut"]' "$P/docs/design/app-facts.json" >/dev/null   # the disputed facts are open, not "one reader only"
  echo '{"same": [{"a": 0, "b": 0}]}' > "$T/ans-judge.json"   # agreed again; the open contradictions stay until dropped
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 0 ]
  jq -e '(.facts | map(.id)) == ["sl-odmitnut"] and ([.open[].fact.id] | sort) == ["spor-jen-codex", "spor-sl-odmitnut"]' "$P/docs/design/app-facts.json" >/dev/null
  python3 "$SC/aid-ui-client.py" facts "$P" --drop spor-sl-odmitnut --reason "kód zavírá trhem" >/dev/null
  # an open question of the format before (one reader) is not lost by a rerun: it stays unconfirmed until dropped
  jq '.open += [{"from": "codex", "fact": {"id": "stara", "kind": "assumption", "statement": "Stará otázka.", "sources": []}}]' "$P/docs/design/app-facts.json" > "$T/f.json" && mv "$T/f.json" "$P/docs/design/app-facts.json"
  echo '{"same": [{"a": 0, "b": 0}]}' > "$T/ans-judge.json"
  for _ in 1 2; do python3 "$SC/aid-ui-client.py" facts "$P" >/dev/null; done
  jq -e '[.unconfirmed[] | select(.fact.id == "stara") | .from] == ["before P118 H5: codex"]' "$P/docs/design/app-facts.json" >/dev/null
  python3 "$SC/aid-ui-client.py" facts "$P" --drop stara --reason "nahrazeno" >/dev/null
  jq -e '[.unconfirmed[] | select(.fact.id == "stara")] == []' "$P/docs/design/app-facts.json" >/dev/null
  echo '{"same": [], "conflict": [], "x": "' > "$T/ans-judge.json"   # no valid judge: nothing written
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 1 ]; jq -e '(.open | map(.fact.id)) == ["spor-jen-codex"]' "$P/docs/design/app-facts.json" >/dev/null
  # the model of an existing app: an open question and a writing task without facts are refused
  mkdir -p "$P/docs/design"; cp "$SC/tests/fixtures/aid-ui/app/docs/design/screens.json" "$P/docs/design/screens.json"
  run python3 "$SC/aid-ui-screens.py" check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }   # an app without a UI today: facts are not required
  echo '{"type": "webapp", "brand": "none", "local": false, "existing": true}' > "$P/.aid-ui/variant.json"
  run python3 "$SC/aid-ui-screens.py" check "$P"; [ "$status" -eq 1 ]
  [[ "$output" == *"1 otevřených otázek"*"spor-jen-codex"* ]]; [[ "$output" == *"úloha zalozit zapisuje, ale neodkazuje na fakta appky"* ]]
  jq '.tasks[0].new = "R9"' "$P/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$P/docs/design/screens.json"   # new behaviour needs a real requirement
  run python3 "$SC/aid-ui-screens.py" check "$P"; [[ "$output" == *"/tasks/0/new: R9 není id požadavku"* ]]
  jq '.requirements = [{"id": "R9", "source": "docs/content/roadmap.md:2", "text": "zavření a alert", "covered_by": ["task:zalozit"]}]' "$P/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$P/docs/design/screens.json"
  run python3 "$SC/aid-ui-screens.py" check "$P"; [[ "$output" != *"/tasks/0/"* ]]; [[ "$output" == *"úloha smazat zapisuje, ale neodkazuje na fakta appky"* ]]
  jq 'del(.tasks[0].new) | del(.requirements)' "$P/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$P/docs/design/screens.json"
  run python3 "$SC/aid-ui-client.py" facts "$P" --drop spor-jen-codex; [ "$status" -eq 2 ]
  python3 "$SC/aid-ui-client.py" facts "$P" --drop spor-jen-codex --reason "Telegram se v UI neřeší" >/dev/null
  jq '(.tasks[] | .facts) = ["sl-odmitnut"]' "$P/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$P/docs/design/screens.json"
  run python3 "$SC/aid-ui-screens.py" check "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  sed -i 's/close_market(p)/close_limit(p)/' "$P/src/execute.py"   # the code changed under the fact
  run python3 "$SC/aid-ui-screens.py" check "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"/app-facts/sl-odmitnut: zdroj zestárl"* ]]
  # a quote that is not in the file is no valid answer; with no stand-in the run stops
  sed -i 's/close_limit(p)/close_market(p)/' "$P/src/execute.py"; echo '{"facts": [{"id": "x", "kind": "unknown", "statement": "y", "sources": [{"source": "src/execute.py:1", "quote": "nic takového tu není", "source_kind": "code"}]}]}' > "$T/ans-claude.json"
  run python3 "$SC/aid-ui-client.py" facts "$P"; [ "$status" -eq 1 ]; [[ "$output" == *"no valid answer from opus"* ]]
}

@test "delta (P118): fixes after an accepted place round give one more round over the fixed version, no reopen; the roles keep their memory" {
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --place sdeleni >/dev/null
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 9
  run qround "$P" --place sdeleni; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  pcycle sdeleni
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r .decision)" = verdict ]   # accepted, the version unchanged
  f="$(python3 "$SC/aid-ui-critic.py" bundle-files "$P" --place sdeleni | head -1)"; echo "Doplněno podle nálezu." >> "$P/$f"
  run python3 "$Q" status "$P" --place sdeleni; jq -e '.decision == "delta" and (.why | contains("rate it once"))' <<<"$output" >/dev/null || { echo "$output"; return 1; }
  run qround "$P" --place sdeleni; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.round == 2' <<<"${lines[-1]}" >/dev/null
  jq -e '[.findings[].id] | index("r1-owner-f1") != null' "$P/.aid-ui/critic/rounds/sdeleni/2/history-owner.json" >/dev/null
  jq -e '.delta == true' "$P/.aid-ui/critic/rounds/sdeleni/2/round.json" >/dev/null
  # after the delta round no second one: fixed again and changed again, the place goes to its verdict
  pcycle sdeleni; echo "Ještě jedna věta." >> "$P/$f"
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r .decision)" = verdict ]
  run qround "$P" --place sdeleni; [ "$status" -eq 1 ]
}

@test "delta (P118): a changed version without accepted and fixed findings gives no delta round" {
  python3 "$SC/aid-ui-critic.py" freeze "$P" --type web-local --place sdeleni >/dev/null
  cat > "$T/bin/codex" <<SH
#!/usr/bin/env bash
[[ "\$1" == --version ]] && exit 0
p="\$(cat)"; role=owner; grep -q "### $(yq -r '.criteria[0].id' "$K/web-local.tech.sdeleni.yaml") " <<<"\$p" && role=tech
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":open(sys.argv[1]).read()}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":10}}))' "$T/ans-\$role.json"
SH
  chmod +x "$T/bin/codex"
  pans sdeleni 9; qround "$P" --place sdeleni >/dev/null
  for r in owner tech; do python3 "$Q" triage "$P" "r1-$r-f1" rejected_with_reason --reason "věta je přesná" --place sdeleni >/dev/null; done
  f="$(python3 "$SC/aid-ui-critic.py" bundle-files "$P" --place sdeleni | head -1)"; echo "Nesouvisející úprava." >> "$P/$f"
  [ "$(python3 "$Q" status "$P" --place sdeleni | jq -r .decision)" = verdict ]
}

@test "brief (P118): the producer's brief holds the findings to fix, what the client supplied and the verifier's open points - nothing else" {
  ans 6 7; qround "$P" --web "$W" >/dev/null
  python3 "$Q" triage "$P" r1-owner-f1 accepted --expected "+1" >/dev/null
  python3 "$Q" triage "$P" r1-tech-f1 rejected_with_reason --reason "už je konkrétní" >/dev/null
  WHOLE_OPEN="cena na úvodu nesedí s ceníkem" verified web
  run python3 "$Q" brief "$P"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  B="$output"; [ -f "$B" ]
  grep -q '^- \*\*r1-owner-f1\*\*' "$B"; ! grep -q 'r1-tech-f1' "$B"            # only what is accepted and not fixed
  grep -q 'vlastní fotky: missing' "$B"                                         # the client's answers (qround: missing)
  grep -q 'cena na úvodu nesedí s ceníkem' "$B"
}

@test "status (P118): every round shows where its time went - roles, verifier, gate, producer" {
  ans 6 7; qround "$P" --web "$W" >/dev/null
  mkdir -p "$P/.aid-ui"; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "{\"mode\": \"precheck\", \"started\": \"$now\", \"ended\": \"$now\", \"open\": 0}" >> "$P/.aid-ui/gate-times.jsonl"
  run python3 "$Q" status "$P"
  jq -e '.history[0].cost.phases | (keys | sort) == ["gate", "producer_and_waiting", "roles", "verify"] and all(.[]; type == "number" and . >= 0)' <<<"$output" >/dev/null || { echo "$output" | jq -c '.history[0].cost'; return 1; }
}
