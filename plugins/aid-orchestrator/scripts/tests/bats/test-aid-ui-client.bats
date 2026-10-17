#!/usr/bin/env bats
# aid-tier: t2
# Nightly since 3.4.0 (15. 10. 2026): the merge path overran its 10 min and the /aid-ui studio is the
# dearest area outside the core; no plan run passes through it, so a regression here shows the next morning.
# P113 step 3: the client is one role with one memory (its ratings at every place, its studio answers by: client,
# the PM's decisions apart) and the roles run on Claude Opus first, Codex their stand-in (D4).
# P113a step 2 - aid-ui-client.py: the critic rates the web from a bundle (a copy of site/, page shots, the
# frozen role; no history), Codex first and the Claude stand-in on a limit, an empty or an invalid answer, with
# the same prompt and working directory; text never sees OPENAI_API_KEY; every call goes to the cost book; the
# client agent answers the studio's first open question; the image budget of the project stops the logo model.

setup() {
  SC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CL="$SC/aid-ui-client.py"; CR="$SC/aid-ui-critic.py"
  T="$BATS_TEST_TMPDIR"; P="$T/p"; mkdir -p "$P/docs/content" "$P/site/cennik" "$T/bin"
  printf '# Pekárna U Mlýna\nKváskový chleba v Brně.\n' > "$P/docs/content/product-context.md"
  echo '<html lang="cs"><title>Pekárna</title><body>chleba</body></html>' > "$P/site/index.html"
  echo '<html lang="cs"><title>Ceník</title><body>ceny</body></html>' > "$P/site/cennik/index.html"
  python3 "$CR" freeze "$P" --type web-local >/dev/null
  # the P113a cases below test the stand-in mechanics with Codex first; the role order of D4 (Claude Opus first) has its own one-client: cases
  export AID_UI_ROLE_FIRST=codex
  export OPENAI_API_KEY=sk-should-never-reach-text ANTHROPIC_API_KEY=sk-ant-never PATH="$T/bin:$PATH" AID_UI_TOOL="$T/bin/tool" ANS="$T/ans.json"
  for role in tech owner; do python3 - "$SC/../skills/ui-design/critic/web-local.$role.yaml" > "$T/ans-$role.json" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1])); _lo = (yaml.safe_load(open(__import__("re").sub(r"\.(owner|tech)\.yaml$", ".yaml", sys.argv[1]))).get("launch_only") or {}).get(__import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)) or []; r["criteria"] = [c for c in r["criteria"] if c["id"] not in _lo]
import os; _r = __import__("re").search(r"\.(owner|tech)\.yaml$", sys.argv[1]).group(1)   # P113: the web is rated with the look and structure rubrics too
r["criteria"] += [dict(c, id=k + "." + c["id"]) for k in ("vzhled", "struktura") for c in yaml.safe_load(open(os.path.dirname(sys.argv[1]) + "/web-local.%s.%s.yaml" % (_r, k)))["criteria"]]
print(json.dumps({"criteria": [{"id": c["id"], "score": 8, "anchor": 8, "evidence": "úvod: nadpis a fotka pece",
  "missing_for_next": "vlastní motiv", "to_ten": {"studio": ["úvod: vlastní fotka ordinace přes celou šířku"], "client": []}} for c in r["criteria"]], "findings": [{"id": "f1", "criterion": r["criteria"][0]["id"], "severity": "minor",
  "owner": "agent", "kind": "remeslo", "text": "opakované slovo", "fix": "zkrátit", "where": "úvod, druhý odstavec"}],
  "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
  done; cp "$T/ans-owner.json" "$ANS"
  # screenshots: one tiny png per page and width
  cat > "$T/bin/tool" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == shot ]] || exit 2; shift; out="$1"; shift; mkdir -p "$out"; files=()
while (($#)); do case "$1" in --cookie|--studio) [[ "$1" == --studio ]] && { printf x > "$out/studio-1440.png"; files+=("\"$out/studio-1440.png\""); }; shift 2;;
  *) n="$(sed -E 's#https?://[^/]+/?##; s#/$##; s#[^a-z0-9]+#-#g' <<<"$1")"; n="${n:-index}"
     for w in 1440 390; do [[ "${FAKE_SHOT_DROP:-}" == "$n-$w" ]] && { files+=("\"ERR $n: timeout\""); continue; }; printf x > "$out/$n-$w.png"; files+=("\"$out/$n-$w.png\""); done; shift;; esac; done
IFS=,; echo "{\"files\": [${files[*]}]}"
EOF
  # codex: FAKE_CODEX = valid | limit | empty | invalid; records its prompt, cwd and whether it saw the key
  cat > "$T/bin/codex" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$BATS_TEST_TMPDIR/codex-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$BATS_TEST_TMPDIR/codex-n"
cat > "$BATS_TEST_TMPDIR/codex-prompt-$n"; echo "${OPENAI_API_KEY:-none}" > "$BATS_TEST_TMPDIR/codex-key"
while (($#)); do [[ "$1" == -C ]] && echo "$2" > "$BATS_TEST_TMPDIR/codex-cwd"; shift; done
case "${FAKE_CODEX:-valid}" in
  limit) echo "ERROR: You've hit your usage limit" >&2; exit 1;;
  empty) exit 0;;
  invalid) t='{"criteria": ['; ;;
  *) t="$(cat "${CODEX_ANS:-$ANS}")";;
esac
python3 -c 'import json,sys; print(json.dumps({"type":"item.completed","item":{"type":"agent_message","text":sys.argv[1]}})); print(json.dumps({"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":300}}))' "$t"
EOF
  cat > "$T/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/claude-prompt"; pwd > "$BATS_TEST_TMPDIR/claude-cwd"; echo "${OPENAI_API_KEY:-none}${ANTHROPIC_API_KEY:-}" > "$BATS_TEST_TMPDIR/claude-key"
[[ "${FAKE_CLAUDE:-ok}" == fail ]] && exit 1
cn=$(( $(cat "$BATS_TEST_TMPDIR/claude-n" 2>/dev/null || echo 0) + 1 )); echo "$cn" > "$BATS_TEST_TMPDIR/claude-n"
a="${CLAUDE_ANS:-$ANS}"; [[ -n "${CLAUDE_ANS2:-}" && "$cn" -ge 2 ]] && a="$CLAUDE_ANS2"
python3 -c 'import json,sys; print(json.dumps({"result": "tady je: " + open(sys.argv[1]).read(), "usage": {"input_tokens": 500, "output_tokens": 100}, "total_cost_usd": 0.02}))' "$a"
EOF
  chmod +x "$T/bin/"*
  serve_site
  # the owner compares with three competitors, shot once per loop
  echo '[{"name":"A","url":"https://a.example/","why":"blízko"},{"name":"B","url":"https://b.example/","why":"cena"},{"name":"C","url":"https://c.example/","why":"online"}]' > "$P/.aid-ui/critic/competitors.json"
  python3 "$CL" competitors "$P" >/dev/null
}

# the critic rates only an address that serves this site: a small server on the site directory
serve_site() {
  WPORT=$(( 38000 + RANDOM % 900 )); python3 -m http.server "$WPORT" --bind 127.0.0.1 --directory "$P/site" >/dev/null 2>&1 & WEBSRV=$!
  W="http://127.0.0.1:$WPORT/"; for _ in $(seq 50); do curl -s "$W" >/dev/null && return 0; sleep 0.1; done; return 1
}

teardown() { [[ -z "${SRV:-}" ]] || kill "$SRV" 2>/dev/null || true; [[ -z "${WEBSRV:-}" ]] || kill "$WEBSRV" 2>/dev/null || true; }

@test "critic: Codex rates from a bundle of the web only; score, record and cost book; no key, no threshold, no history" {
  run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.provider == "codex" and .quality_score == 8' <<<"${lines[-1]}" >/dev/null
  [ "$(cat "$T/codex-cwd")" = "$T/r1/bundle" ]; [ -f "$T/r1/bundle/site/cennik/index.html" ]; [ ! -e "$T/r1/bundle/.aid-ui" ]
  jq -se 'length == 1 and .[0].provider == "codex" and .[0].billing == "subscription" and .[0].purpose == "critic:critic:owner" and .[0].usd > 0' "$P/.aid-ui/costs.jsonl" >/dev/null
  [ ! -e "$T/r1/bundle/podklady/facts.yaml" ]; ! grep -q "podklady/facts.yaml" "$T/r1/prompt.md"   # no facts register: none in the bundle
  # the confirmed facts go with the web (the frozen context may be older than a confirmation)
  echo 'novi: {value: "áno", source: "klient 11. 10."}' > "$P/docs/content/facts.yaml"
  python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1f" >/dev/null
  cmp -s "$P/docs/content/facts.yaml" "$T/r1f/bundle/podklady/facts.yaml"; grep -q "podklady/facts.yaml" "$T/r1f/prompt.md"
  jq -e '.facts_sha | length == 64' "$T/r1f/run.json" >/dev/null; rm "$P/docs/content/facts.yaml"
  # what only the gate saw goes too, for this build only, with the open items (Coufal round 7)
  mkdir -p "$P/.aid-ui/verify" "$P/docs/design"; B="$(bash "$SC/aid-ui-state.sh" build-id "$P/site")"
  jq -n --arg b "$B" '{build_id: $b, rows: [{check: "form_delivery", status: "pass", detail: "delivered"}, {check: "form_delivery", status: "pass", detail: "delivered"}, {check: "no_overlap", status: "pass"}]}' > "$P/.aid-ui/verify/result.json"
  echo '{"open_items": [{"text": "príjem na hostingu", "owner": "agent", "critical": true, "status": "open"}, {"text": "hotovo", "status": "done"}]}' > "$P/docs/design/brand-state.json"
  CODEX_ANS="$T/ans-tech.json" python3 "$CL" critic "$P" --role tech --web "$W" --out "$T/r1g" >/dev/null
  jq -e '(.gate | length) == 1 and .gate[0].check == "form_delivery" and .gate[0].pass == 2 and .gate[0].details == ["delivered"] and (.open_items | length) == 1' "$T/r1g/bundle/podklady/overenie.json" >/dev/null
  grep -q "podklady/overenie.json" "$T/r1g/prompt.md"; jq -e '.role == "tech" and .score.quality_score == 8' "$T/r1g/run.json" >/dev/null
  [ ! -e "$T/r1g/bundle/podklady/konkurence" ]   # the competition is the owner's
  python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1o" >/dev/null
  jq -e '.gate == [] and (.open_items | length) == 1' "$T/r1o/bundle/podklady/overenie.json" >/dev/null   # the gate's numbers are the technician's, the open items both
  [ "$(ls "$T/r1o/bundle/podklady/konkurence" | wc -l)" -eq 6 ]; grep -q "Weby konkurence" "$T/r1o/prompt.md"
  jq '.build_id = "stale"' "$P/.aid-ui/verify/result.json" > "$T/x" && mv "$T/x" "$P/.aid-ui/verify/result.json"
  CODEX_ANS="$T/ans-tech.json" python3 "$CL" critic "$P" --role tech --web "$W" --out "$T/r1h" >/dev/null
  jq -e '(.gate | length) == 0' "$T/r1h/bundle/podklady/overenie.json" >/dev/null   # another build's gate never vouches
  rm -r "$P/.aid-ui/verify" "$P/docs/design/brand-state.json"
  # memory: the role's own past findings go along; a regression_of an id not in them is not a valid answer
  echo '[{"id":"r1-owner-f9","round":1,"criterion":"x","text":"stará vada","state":"fixed","evidence":"opraveno"}]' > "$T/hist.json"
  jq '.findings[0].regression_of = "r1-owner-f9"' "$ANS" > "$T/ans-reg.json"
  CODEX_ANS="$T/ans-reg.json" python3 "$CL" critic "$P" --role owner --web "$W" --history "$T/hist.json" --out "$T/r1m" >/dev/null
  cmp -s "$T/hist.json" <(jq . "$T/r1m/bundle/podklady/historie.json" | jq -c . | jq .) || jq -e '.[0].id == "r1-owner-f9"' "$T/r1m/bundle/podklady/historie.json" >/dev/null
  grep -q "podklady/historie.json" "$T/r1m/prompt.md"; jq -e '.history == 1 and .provider == "codex"' "$T/r1m/run.json" >/dev/null
  jq '.findings[0].regression_of = "r9-owner-nic"' "$ANS" > "$T/ans-bad.json"
  CODEX_ANS="$T/ans-bad.json" CLAUDE_ANS="$ANS" python3 "$CL" critic "$P" --role owner --web "$W" --history "$T/hist.json" --out "$T/r1n" >/dev/null
  jq -e '.provider == "claude" and ([.attempts[] | select(.error != null and (.error | contains("regression_of")))] | length) == 2' "$T/r1n/run.json" >/dev/null
  # a second score only where an open item of the CLIENT holds the web down (the owner sees the open items too)
  echo '{"open_items": [{"id": "oi-4", "text": "vlastné fotky", "owner": "klient", "status": "open"}, {"id": "oi-11", "text": "príjem na hostingu", "owner": "agent", "status": "open"}]}' > "$P/docs/design/brand-state.json"
  jq '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 8 | .studio_anchor = 8 | .limited_by = ["oi-4"] | .to_ten.client = ["vlastné fotky"])' "$ANS" > "$T/ans-lim.json"
  CODEX_ANS="$T/ans-lim.json" python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1l" >/dev/null
  jq -e '.provider == "codex" and .score.limited_by == ["oi-4"] and .score.quality_now < .score.quality_score' "$T/r1l/run.json" >/dev/null
  jq -e '(.open_items | map(.id)) == ["oi-4", "oi-11"] and .gate == []' "$T/r1l/bundle/podklady/overenie.json" >/dev/null
  jq '.criteria[0] |= (.score = 5 | .anchor = 4 | .studio_score = 8 | .studio_anchor = 8 | .limited_by = ["oi-11"] | .to_ten.client = ["prístup k hostingu"])' "$ANS" > "$T/ans-lim2.json"
  CODEX_ANS="$T/ans-lim2.json" CLAUDE_ANS="$ANS" python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1k" >/dev/null
  jq -e '.provider == "claude" and (.attempts[0].error | contains("limited_by oi-11"))' "$T/r1k/run.json" >/dev/null   # oi-11 is the studio's own
  # the stand-in gets the same second chance with the reason as Codex
  rm -f "$T/claude-n"; jq '.criteria[0].anchor = 4' "$ANS" > "$T/ans-anchor.json"
  FAKE_CODEX=limit CLAUDE_ANS="$T/ans-anchor.json" CLAUDE_ANS2="$ANS" python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/r1s" >/dev/null
  jq -e '.provider == "claude" and (.attempts | length) == 3 and (.attempts[1].error | contains("does not sit on its anchor")) and .attempts[2].error == null' "$T/r1s/run.json" >/dev/null
  grep -q "Předchozí odpověď nebyla platná" "$T/claude-prompt"
  rm "$P/docs/design/brand-state.json"
  # an audit is blind: no memory even when a history is passed
  python3 "$CL" critic "$P" --role owner --web "$W" --history "$T/hist.json" --audit --out "$T/r1a" >/dev/null
  [ ! -e "$T/r1a/bundle/podklady/historie.json" ]
  [ "$(cat "$T/codex-key")" = none ]
  jq -e '.kind == "critic" and (.site_sha | length) == 64 and .frozen_sha == $f and (.images | length) == 4 and .score.quality_score == 8 and .score.accepted == false
         and (.pages | index($w + "cennik/")) != null' --arg w "$W" --arg f "$(jq -r .sha256 "$P/.aid-ui/critic/frozen.json")" "$T/r1/run.json" >/dev/null
  grep -q "cennik-390.png" "$T/r1/prompt.md"; ! grep -qiE "akcept|threshold|8/10" "$T/r1/prompt.md"
  # an audit is the same bundle, recorded as an audit
  run python3 "$CL" critic "$P" --role owner --web "$W" --audit --out "$T/r2"; [ "$status" -eq 0 ]
  jq -e '.kind == "audit"' "$T/r2/run.json" >/dev/null
  [ "$(jq -r .site_sha "$T/r1/run.json")" = "$(jq -r .site_sha "$T/r2/run.json")" ]
}

@test "critic: a limit, an empty answer and an invalid answer twice each hand the same prompt and directory to the Claude stand-in" {
  for mode in limit empty invalid; do
    rm -f "$T/codex-n" "$T/claude-prompt"
    FAKE_CODEX=$mode run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/s-$mode"; [ "$status" -eq 0 ] || { echo "$mode: $output"; return 1; }
    jq -e '.provider == "claude" and (.stand_in_reason | length) > 0' "$T/s-$mode/run.json" >/dev/null
    # the stand-in got the Codex bundle: the same prompt (plus where the images are) and the same working directory
    head -c "$(stat -c %s "$T/codex-prompt-1")" "$T/claude-prompt" | cmp -s - "$T/codex-prompt-1"
    [ "$(cat "$T/claude-cwd")" = "$T/s-$mode/bundle" ]; [ "$(cat "$T/claude-key")" = none ]
  done
  jq -e '.stand_in_reason == "limit"' "$T/s-limit/run.json" >/dev/null
  jq -e '.stand_in_reason == "no answer"' "$T/s-empty/run.json" >/dev/null
  jq -e '(.stand_in_reason | startswith("invalid answer twice")) and (.attempts | length) == 3' "$T/s-invalid/run.json" >/dev/null
  [ "$(cat "$T/codex-n")" = 2 ]   # an invalid answer goes back to Codex once before the stand-in
  jq -se 'map(select(.provider == "claude")) | length == 3 and .[0].reported_usd == 0.02 and .[0].usd == 0.003' "$P/.aid-ui/costs.jsonl" >/dev/null
}

@test "critic: both providers failing, an answer off the frozen schema, or no frozen critic -> exit 1 with the record" {
  FAKE_CODEX=limit FAKE_CLAUDE=fail run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/f1"
  [ "$status" -eq 1 ]; [[ "$output" == *"no valid rating"* ]]; jq -e '.provider == null and (.score | not)' "$T/f1/run.json" >/dev/null
  jq '.criteria[0].anchor = 4' "$ANS" > "$T/bad.json"
  CODEX_ANS="$T/bad.json" CLAUDE_ANS="$T/bad.json" run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/f2"
  [ "$status" -eq 1 ]; jq -e '.attempts[0].error | contains("does not sit on its anchor")' "$T/f2/run.json" >/dev/null
  AID_UI_STANDIN=off FAKE_CODEX=limit run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/f3"
  [ "$status" -eq 1 ]; [ ! -e "$T/claude-prompt" ] || [ "$(jq '.attempts | length' "$T/f3/run.json")" -eq 1 ]
  # a page without its mobile shot: no rating, the model is never asked
  rm -f "$T/codex-n"; FAKE_SHOT_DROP=cennik-390 run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/f4"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing: cennik-390.png"* ]]; [ ! -e "$T/codex-n" ]
  # an address that does not serve this site is refused before any model is asked
  rm -f "$T/codex-n"
  run python3 "$CL" critic "$P" --role tech --web "http://127.0.0.1:1/"; [ "$status" -eq 1 ]; [[ "$output" == *"does not answer"* ]]
  run python3 "$CL" critic "$P" --role tech --web "${W}cennik/" --out "$T/f5"; [ "$status" -eq 1 ]; [[ "$output" == *"does not serve"* ]]; [ ! -e "$T/codex-n" ]
  Q="$T/q"; mkdir -p "$Q/site"; echo x > "$Q/site/index.html"
  run python3 "$CL" critic "$Q" --role tech --web "$W"; [ "$status" -eq 1 ]; [[ "$output" == *"frozen"* ]]
}

@test "answer: the client agent logs in, answers the first open question with a card, a refused answer goes back once; costs summarised" {
  PORT=$(( 39500 + RANDOM % 400 ))
  cat > "$T/studio.py" <<'PY'
import http.server, json, sys, os
P, T = sys.argv[2], sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj, cookie=None):
        b = json.dumps(obj).encode(); self.send_response(code); self.send_header("Content-Type", "application/json")
        if cookie: self.send_header("Set-Cookie", cookie)
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith("/?k="):
            ok = self.path[4:] == open(P + "/.aid-ui/studio.code").read().strip()
            return self.send(200, {}, "aid_studio_t=1; Path=/" if ok else None)
        if self.headers.get("Cookie") != "aid_studio_t=1": return self.send(403, {})
        if self.path == "/state":
            done = os.path.exists(T + "/answered")
            qs = [] if done else [{"id": "q1", "kind": "choice", "target": "direction", "title": "Smer"}, {"id": "q2", "kind": "choice", "target": "x", "title": "Druhá"}]
            return self.send(200, {"questions": qs,
                                   "cards": [{"id": "a", "question": "q1", "title": "Teplý", "url": "http://127.0.0.1:1/a/"},
                                             {"id": "b", "question": "q1", "title": "Chladný", "url": "http://127.0.0.1@evil.example/b/"}]})
        self.send(404, {})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(T + "/posts.jsonl", "a") as f: f.write(json.dumps(body) + "\n")
        if not os.path.exists(T + "/refused-once"):
            open(T + "/refused-once", "w").close(); return self.send(422, {"error": "choose needs a comment"})
        open(T + "/answered", "w").close(); self.send(200, {"ok": True})
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
  mkdir -p "$P/.aid-ui"; python3 "$T/studio.py" "$PORT" "$P" "$T" & SRV=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT/state" >/dev/null && break; sleep 0.1; done
  printf '{"answer": {"decision": "choose", "choice": "a", "comment": "teplejší"}, "feedback": {"question_clear": 4}}' > "$T/client.json"
  CODEX_ANS="$T/client.json" run python3 "$CL" answer "$P" --studio "http://127.0.0.1:$PORT" --once; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"answered q1: choose a"* ]]
  # only the card page on the studio's own host is photographed; a look-alike "host@elsewhere" address is not
  ls "$P/.aid-ui/client/turns/q1-1/" | grep -q "^a-1440.png"; ! ls "$P/.aid-ui/client/turns/q1-1/" | grep -q "^b-"
  [ "$(wc -l < "$T/posts.jsonl")" -eq 2 ]; jq -se '.[1].question == "q1" and .[1].choice == "a"' "$T/posts.jsonl" >/dev/null
  grep -q "Studio odmítlo odpověď" "$T/codex-prompt-2"; grep -q "Teplý" "$T/codex-prompt-1"; grep -q "Pekárna U Mlýna\|majitel" "$T/codex-prompt-1"
  jq -e '.provider == "codex" and .question == "q1"' "$P/.aid-ui/client/feedback.jsonl" >/dev/null
  [ "$(stat -c %a "$P/.aid-ui/client/cookie.txt")" = 600 ]
  run python3 "$CL" costs "$P"; jq -e '.calls == 2 and .api_usd == 0 and .image_budget_left_usd == 2' <<<"$output" >/dev/null
  # both providers failing writes the stop file and the next run refuses to start
  rm "$T/answered"; rm -f "$T/refused-once"
  FAKE_CODEX=limit FAKE_CLAUDE=fail run python3 "$CL" answer "$P" --studio "http://127.0.0.1:$PORT" --once
  [ -f "$P/.aid-ui/client/stop" ]
  run python3 "$CL" answer "$P" --studio "http://127.0.0.1:$PORT" --once; [ "$status" -eq 1 ]; [[ "$output" == *"stopped"* ]]
}

@test "image budget: the logo model sends nothing once the project's paid API total would pass the budget" {
  mkdir -p "$P/.aid-ui/logo"
  echo '{"situation":"new","slots":[{"id":"WC","kind":"name+sign"}]}' > "$P/.aid-ui/logo/route.json"
  printf '{"mode": "mark", "n": 1, "slots": {"WC": "x"}}' > "$P/.aid-ui/logo/gen.json"
  echo '{"provider": "openai", "billing": "api", "purpose": "logo:WC", "usd": 1.99}' > "$P/.aid-ui/costs.jsonl"
  run python3 "$SC/aid-ui-logo-gen.py" "$P" --spec .aid-ui/logo/gen.json; [ "$status" -eq 1 ]
  [[ "$output" == *"image budget 2.00 USD"* ]]; [ "$(wc -l < "$P/.aid-ui/costs.jsonl")" -eq 1 ]
  AID_UI_IMAGE_BUDGET_USD=1.5 run python3 "$CL" costs "$P"; jq -e '.api_usd == 1.99 and .image_budget_left_usd == -0.49' <<<"$output" >/dev/null
}

@test "image budget: the reservation is atomic - at the boundary and with parallel generators the project never passes the budget" {
  python3 - "$SC/lib" "$P" <<'PY'
import sys, multiprocessing as mp
sys.path.insert(0, sys.argv[1]); import aid_ui_costs as c
P = sys.argv[2]
assert c.reserve(P, {"provider": "openai", "usd": 1.96}) is None
assert c.reserve(P, {"provider": "openai", "usd": 0.04}) is None          # exactly 2.00 fits
assert "image budget 2.00" in c.reserve(P, {"provider": "openai", "usd": 0.001})
open(c.path(P), "w").close()
def one(_): return c.reserve(P, {"provider": "openai", "usd": 0.15}) is None
with mp.Pool(20) as pool: ok = sum(pool.map(one, range(20)))
assert ok == 13 and c.api_spent(P) == 1.95, (ok, c.api_spent(P))
c.tokens(P, "codex", None, {"input": 1000, "cached": 0, "output": 0}, "x")
assert c.api_spent(P) == 1.95                                              # subscription rows never count against it
PY
}

@test "shot: the real browser tool takes full pages at 1440 and 390 with the mobile layout" {
  [ -f "$SC/../lib/ui-fidelity/node_modules/.aid-installed" ] || skip "lib/ui-fidelity not installed here"
  W="$T/w"; mkdir -p "$W"
  printf '<html><style>main{display:grid;grid-template-columns:1fr 1fr}@media(max-width:600px){main{grid-template-columns:1fr}}div{height:900px;border:1px solid}</style><main><div>a</div><div>b</div><div>c</div><div>d</div></main></html>' > "$W/index.html"
  PORT=$(( 39100 + RANDOM % 300 )); python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$W" >/dev/null 2>&1 & SRV=$!
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT/" >/dev/null && break; sleep 0.1; done
  run bash "$SC/aid-ui-tool.sh" shot "$T/sh" "http://127.0.0.1:$PORT/"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 - "$T/sh" <<'PY'
import sys, struct
dim = lambda f: struct.unpack(">II", open(f, "rb").read(24)[16:24])
d, m = dim(sys.argv[1] + "/index-1440.png"), dim(sys.argv[1] + "/index-390.png")
assert d[0] == 1440 and m[0] == 390, (d, m)
assert m[1] > d[1] * 1.8, (d, m)   # one column on the phone: about twice as tall as the two-column desktop
PY
}

@test "answer: a card preview read from the payload never leaves the studio folder" {
  mkdir -p "$P/.aid-ui/studio/previews"; echo x > "$P/.aid-ui/studio/previews/a.png"; echo key > "$P/secret"
  echo '{"questions":[{"id":"q1","cards":[{"id":"a","preview":"previews/a.png"},{"id":"b","preview":"../../secret"}]}]}' > "$P/.aid-ui/studio/payload.json"
  python3 - "$CL" "$P" <<'PY'
import importlib.util, sys
cl, proj = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("c", cl); m = importlib.util.module_from_spec(spec); sys.argv = ["x"]; spec.loader.exec_module(m)
class S: project = proj
cs = m.question_cards(S(), {"cards": []}, {"id": "q1"})
assert cs[0]["_file"].endswith("previews/a.png") and cs[1]["_file"] is None, cs
PY
}

@test "P113a bod 8: the client's prompt carries only the change since its last answer, or says why the whole text" {
  run python3 - "$CL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("cl", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t = m.diff_text({"target": "docs/seo/brief.md@ab", "diff": {"lines": ["@@ -3 +3 @@", "-titulok: Krátky", "+titulok: Dlhší"], "truncated": 4}})
assert "Co se změnilo od minula" in t and "+titulok: Dlhší" in t and "docs/seo/brief.md@ab" in t and "dalších 4" in t, t
assert "Nic" in m.diff_text({"diff": {"same": True}})
t = m.diff_text({"target": "docs/seo/brief.md@" + "a" * 64, "diff": {"missing": True, "full": "celý text"}})
assert "Předchozí verzi studio nemá" in t and "celý text" in t and "a" * 64 in t, t
t = m.diff_text({"items": [{"id": "index.html", "target": "index.html@f2"}], "item_diffs": {"index.html": {"lines": ["-a", "+b"]}}})
assert "## index.html" in t and "+b" in t and "index.html@f2" in t, t
assert m.diff_text({}) == ""
print("ok")
PY
  [ "$status" -eq 0 ] && [ "${lines[-1]}" = ok ] || { echo "$output"; return 1; }
  grep -q 'answer.items' "$CL" && grep -q '"items"' "$SC/../skills/ui-design/critic/client-template.md"
}

# ---------------------------------------------------------------- P113 step 3: one client, roles on Opus
FX_MEM="$BATS_TEST_DIRNAME/../fixtures/aid-ui/client-memory/.aid-ui/studio/history.jsonl"
mem() { python3 -c 'import json,sys; sys.path.insert(0, sys.argv[1]); import aid_ui_memory as m; print(json.dumps(m.role_memory(sys.argv[2], sys.argv[3], sys.argv[4]), ensure_ascii=False))' "$SC/lib" "$P" "$1" "$2"; }
round_at() {   # round_at <place> <n>: a recorded round of both roles with one finding each
  local d="$P/.aid-ui/critic/rounds/$1"; [ "$1" != web ] || d="$P/.aid-ui/critic/rounds"
  mkdir -p "$d/$2"; jq -n --argjson n "$2" --arg p "$1" '{n: $n, at: "2026-10-12T08:00:00Z", place: $p, score: {criteria: {"owner.muj_podnik": 7, "tech.myslenka": 6}},
    to_ten: {owner: {muj_podnik: {studio: ["kóta odsazená od okapu"], client: []}}}, findings: [
    {id: "r\($n)-owner-f1", role: "owner", criterion: "muj_podnik", text: "dům je obecný", where: "karta b", state: "accepted", evidence: "kóta přidána"},
    {id: "r\($n)-tech-f1", role: "tech", criterion: "myslenka", text: "myšlenka slabá", where: "karta b", state: "rejected_with_reason", reason: "zadání"}]}' > "$d/$2/round.json"
}

@test "one-client: the client's answer goes with the agent token and X-AID-Role: client; the studio records it by client and the rating sees it" {
  bash "$SC/aid-ui-state.sh" init "$P" >/dev/null; bash "$SC/aid-ui-state.sh" method "$P" vision >/dev/null
  echo 0123456789abcdef0123456789abcdef > "$P/.aid-ui/studio.token"; mkdir -p "$P/.aid-ui/studio"
  jq -n --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" '{questions: [{id: "v1", kind: "vision", target: "vize@1", title: "Vize", opened_at: $o}], cards: []}' > "$P/.aid-ui/studio/payload.json"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  python3 "$SC/../lib/aid-ui-studio/server.py" --project "$P" --host 127.0.0.1 --port "$PORT" --token-file "$P/.aid-ui/studio.token" >"$T/studio.log" 2>&1 3>&- & SRV=$!
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
  printf '{"answer": {"decision": "approve", "choice": null, "comment": "sedí"}, "feedback": {"question_clear": 4}}' > "$T/client.json"
  sleep 0.05; CODEX_ANS="$T/client.json" run python3 "$CL" answer "$P" --studio "http://127.0.0.1:$PORT" --once; [ "$status" -eq 0 ] || { echo "$output"; cat "$T/studio.log"; return 1; }
  jq -se 'map(select(.question.id == "v1")) | length == 1 and .[0].by == "client"' "$P/.aid-ui/studio/history.jsonl" >/dev/null
  AID_UI_STUDIO_URL="http://127.0.0.1:$PORT" bash "$SC/aid-ui-state.sh" record-answer "$P" --question v1 >/dev/null 2>&1 || true
  # the client's rating at a place sees its own answer, as its own
  mem owner sdeleni > "$T/h.json"; jq -e '.my_studio_answers | map(.question) == ["v1"]' "$T/h.json" >/dev/null
  python3 "$CR" freeze "$P" --type web-local --place sdeleni >/dev/null
  python3 - "$P" > "$T/ans-sd.json" <<'PY'
import json, sys
fz = json.load(open(sys.argv[1] + "/.aid-ui/critic/frozen/sdeleni.json"))
print(json.dumps({"criteria": [{"id": c["id"], "score": 8, "anchor": 8, "evidence": "dokument, oddíl 1", "missing_for_next": "víc", "to_ten": {"studio": ["oddíl 1: doložit odlišení zakázkou"], "client": []}}
  for c in fz["roles"]["owner"]["rubric"]["criteria"]], "findings": [], "readiness": [], "summary": "Sdělení pro test paměti."}))
PY
  CODEX_ANS="$T/ans-sd.json" python3 "$CL" critic "$P" --place sdeleni --role owner --history "$T/h.json" --out "$T/rs" >/dev/null
  jq -e '.my_studio_answers[0].question == "v1"' "$T/rs/bundle/podklady/historie.json" >/dev/null; grep -q "Paměť hodnotitele" "$T/rs/prompt.md"
}

@test "one-client: the first rating at a new place sees the client's earlier places; the expert remembers its own place only" {
  round_at logo 1
  mem owner vzhled > "$T/o.json"; mem tech vzhled > "$T/t.json"
  jq -e '.place == "vzhled" and (.findings | length) == 0 and .other_places.logo.findings[0].id == "r1-owner-f1" and .other_places.logo.ratings[0].scores.muj_podnik == 7' "$T/o.json" >/dev/null
  jq -e '(has("other_places") | not) and (has("pm_decisions") | not) and (.findings | length) == 0' "$T/t.json" >/dev/null
  mem tech logo | jq -e '.findings == [.findings[0]] and .findings[0].id == "r1-tech-f1" and .ratings[0].scores.myslenka == 6' >/dev/null
}

@test "one-client: a PM answer is labelled the PM's, never the client's own words; the client's answer prompt shows both" {
  mkdir -p "$P/.aid-ui/studio"; cp "$FX_MEM" "$P/.aid-ui/studio/history.jsonl"
  mem owner logo > "$T/o.json"
  jq -e '(.my_studio_answers | map(.question)) == ["i1"] and (.pm_decisions | map(.question)) == ["v0","i2"] and .pm_decisions[1].comment == "PM: kóta musí být odsazená"' "$T/o.json" >/dev/null
  PORT=$(( 39500 + RANDOM % 400 ))
  python3 - "$PORT" "$P" <<'PY' & SRV=$!
import http.server, json, sys
P = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj, cookie=None):
        b = json.dumps(obj).encode(); self.send_response(code); self.send_header("Content-Type", "application/json")
        if cookie: self.send_header("Set-Cookie", cookie)
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith("/?k="): return self.send(200, {}, "aid_studio_t=1; Path=/")
        if self.path == "/state": return self.send(200, {"questions": [{"id": "d1", "kind": "direction", "target": "smer", "title": "Vzhled"}], "cards": []})
        self.send(404, {})
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
  for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT/state" >/dev/null && break; sleep 0.1; done
  run python3 "$CL" answer "$P" --studio "http://127.0.0.1:$PORT" --once --dry; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  f="$P/.aid-ui/client/turns/d1-1/prompt.md"
  grep -q "# Tvoje dřívější odpovědi ve studiu" "$f"; grep -q "nechci dům, chci kótu" "$f"
  grep -q "# Rozhodnutí PM (ne tvoje slova" "$f"; grep -q "PM: kóta musí být odsazená" "$f"
  ! awk '/# Tvoje dřívější odpovědi/,/# Rozhodnutí PM/' "$f" | grep -q "kóta musí být odsazená"
}

@test "one-client: the blind audit (--fresh) reads no memory; a corrupt studio history stops naming its line" {
  echo '{"findings": [{"id": "r1-owner-f9", "state": "fixed", "text": "x", "criterion": "x"}], "my_studio_answers": [{"question": "i1"}]}' > "$T/h.json"
  python3 "$CL" critic "$P" --role owner --web "$W" --history "$T/h.json" --fresh --out "$T/fr" >/dev/null
  [ ! -e "$T/fr/bundle/podklady/historie.json" ]; ! grep -q "historie.json" "$T/fr/prompt.md"; jq -e '.kind == "audit" and .history == null' "$T/fr/run.json" >/dev/null
  mkdir -p "$P/.aid-ui/studio"; { cat "$FX_MEM"; echo '{"by": "client", "question"'; } > "$P/.aid-ui/studio/history.jsonl"
  run mem owner logo; [ "$status" -ne 0 ]; [[ "$output" == *"line 5 is not JSON"* ]]
}

@test "one-client: role calls go to Claude Opus first with Codex as the stand-in; the model and provider of each call are recorded" {
  unset AID_UI_ROLE_FIRST
  run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/o1"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.provider == "claude" and .model == "opus" and .role_call == true and .attempts[0].provider == "claude" and .attempts[0].model == "opus"' "$T/o1/run.json" >/dev/null
  [ ! -e "$T/codex-n" ]
  FAKE_CLAUDE=fail run python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/o2"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.provider == "codex" and (.stand_in_reason | length) > 0 and .attempts[0].provider == "claude"' "$T/o2/run.json" >/dev/null
  AID_UI_ROLE_MODEL=sonnet python3 "$CL" critic "$P" --role owner --web "$W" --out "$T/o3" >/dev/null
  jq -e '.model == "sonnet"' "$T/o3/run.json" >/dev/null
  grep -n 'AID_UI_ROLE_MODEL' "$CL" >/dev/null
}
