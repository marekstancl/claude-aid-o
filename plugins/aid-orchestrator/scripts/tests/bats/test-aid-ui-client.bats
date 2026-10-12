#!/usr/bin/env bats
# aid-tier: t1
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
  export OPENAI_API_KEY=sk-should-never-reach-text PATH="$T/bin:$PATH" AID_UI_TOOL="$T/bin/tool" ANS="$T/ans.json"
  python3 - "$SC/../skills/ui-design/critic/web-local.yaml" > "$ANS" <<'PY'
import sys, json, yaml
r = yaml.safe_load(open(sys.argv[1]))
print(json.dumps({"criteria": [{"id": c["id"], "score": 8, "anchor": 8, "evidence": "úvod: nadpis a fotka pece",
  "missing_for_next": "vlastní motiv"} for c in r["criteria"]], "findings": [{"id": "f1", "criterion": "copy", "severity": "minor",
  "owner": "agent", "text": "opakované slovo", "fix": "zkrátit", "where": "úvod, druhý odstavec"}],
  "readiness": [{"item": "vlastní fotky"}], "summary": "Solidní web, chybí nálada."}))
PY
  # screenshots: one tiny png per page and width
  cat > "$T/bin/tool" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == shot ]] || exit 2; shift; out="$1"; shift; mkdir -p "$out"; files=()
while (($#)); do case "$1" in --cookie|--studio) [[ "$1" == --studio ]] && { printf x > "$out/studio-1440.png"; files+=("\"$out/studio-1440.png\""); }; shift 2;;
  *) n="$(sed -E 's#https?://[^/]+/?##; s#/$##; s#[^a-z0-9]+#-#g' <<<"$1")"; n="${n:-index}"
     for w in 1440 390; do printf x > "$out/$n-$w.png"; files+=("\"$out/$n-$w.png\""); done; shift;; esac; done
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
cat > "$BATS_TEST_TMPDIR/claude-prompt"; pwd > "$BATS_TEST_TMPDIR/claude-cwd"; echo "${OPENAI_API_KEY:-none}" > "$BATS_TEST_TMPDIR/claude-key"
[[ "${FAKE_CLAUDE:-ok}" == fail ]] && exit 1
python3 -c 'import json,sys; print(json.dumps({"result": "tady je: " + open(sys.argv[1]).read(), "usage": {"input_tokens": 500, "output_tokens": 100}, "total_cost_usd": 0.02}))' "${CLAUDE_ANS:-$ANS}"
EOF
  chmod +x "$T/bin/"*
}

teardown() { [[ -z "${SRV:-}" ]] || kill "$SRV" 2>/dev/null || true; }

@test "critic: Codex rates from a bundle of the web only; score, record and cost book; no key, no threshold, no history" {
  run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --out "$T/r1"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.provider == "codex" and .quality_score == 8' <<<"${lines[-1]}" >/dev/null
  [ "$(cat "$T/codex-cwd")" = "$T/r1/bundle" ]; [ -f "$T/r1/bundle/site/cennik/index.html" ]; [ ! -e "$T/r1/bundle/.aid-ui" ]
  [ "$(cat "$T/codex-key")" = none ]
  jq -e '.kind == "critic" and (.site_sha | length) == 64 and .frozen_sha == $f and (.images | length) == 4 and .score.accepted == true
         and (.pages | index("http://127.0.0.1:1/cennik/")) != null' --arg f "$(jq -r .sha256 "$P/.aid-ui/critic/frozen.json")" "$T/r1/run.json" >/dev/null
  grep -q "cennik-390.png" "$T/r1/prompt.md"; ! grep -qiE "akcept|threshold|8/10" "$T/r1/prompt.md"
  jq -se 'length == 1 and .[0].provider == "codex" and .[0].billing == "subscription" and .[0].purpose == "critic:critic" and .[0].usd > 0' "$P/.aid-ui/costs.jsonl" >/dev/null
  # an audit is the same bundle, recorded as an audit
  run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --audit --out "$T/r2"; [ "$status" -eq 0 ]
  jq -e '.kind == "audit"' "$T/r2/run.json" >/dev/null
  [ "$(jq -r .site_sha "$T/r1/run.json")" = "$(jq -r .site_sha "$T/r2/run.json")" ]
}

@test "critic: a limit, an empty answer and an invalid answer twice each hand the same prompt and directory to the Claude stand-in" {
  for mode in limit empty invalid; do
    rm -f "$T/codex-n" "$T/claude-prompt"
    FAKE_CODEX=$mode run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --out "$T/s-$mode"; [ "$status" -eq 0 ] || { echo "$mode: $output"; return 1; }
    jq -e '.provider == "claude" and (.stand_in_reason | length) > 0' "$T/s-$mode/run.json" >/dev/null
    # the stand-in got the Codex bundle: the same prompt (plus where the images are) and the same working directory
    head -c "$(stat -c %s "$T/codex-prompt-1")" "$T/claude-prompt" | cmp -s - "$T/codex-prompt-1"
    [ "$(cat "$T/claude-cwd")" = "$T/s-$mode/bundle" ]; [ "$(cat "$T/claude-key")" = none ]
  done
  jq -e '.stand_in_reason == "limit"' "$T/s-limit/run.json" >/dev/null
  jq -e '.stand_in_reason == "no answer"' "$T/s-empty/run.json" >/dev/null
  jq -e '(.stand_in_reason | startswith("invalid answer twice")) and (.attempts | length) == 3' "$T/s-invalid/run.json" >/dev/null
  [ "$(cat "$T/codex-n")" = 2 ]   # an invalid answer goes back to Codex once before the stand-in
  jq -se 'map(select(.provider == "claude")) | length == 3 and .[0].usd == 0.02' "$P/.aid-ui/costs.jsonl" >/dev/null
}

@test "critic: both providers failing, an answer off the frozen schema, or no frozen critic -> exit 1 with the record" {
  FAKE_CODEX=limit FAKE_CLAUDE=fail run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --out "$T/f1"
  [ "$status" -eq 1 ]; [[ "$output" == *"no valid rating"* ]]; jq -e '.provider == null and (.score | not)' "$T/f1/run.json" >/dev/null
  jq '.criteria[0].anchor = 4' "$ANS" > "$T/bad.json"
  CODEX_ANS="$T/bad.json" CLAUDE_ANS="$T/bad.json" run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --out "$T/f2"
  [ "$status" -eq 1 ]; jq -e '.attempts[0].error | contains("does not sit on its anchor")' "$T/f2/run.json" >/dev/null
  AID_UI_STANDIN=off FAKE_CODEX=limit run python3 "$CL" critic "$P" --web http://127.0.0.1:1/ --out "$T/f3"
  [ "$status" -eq 1 ]; [ ! -e "$T/claude-prompt" ] || [ "$(jq '.attempts | length' "$T/f3/run.json")" -eq 1 ]
  Q="$T/q"; mkdir -p "$Q/site"; echo x > "$Q/site/index.html"
  run python3 "$CL" critic "$Q" --web http://127.0.0.1:1/; [ "$status" -eq 1 ]; [[ "$output" == *"frozen"* ]]
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
                                   "cards": [{"id": "a", "question": "q1", "title": "Teplý"}, {"id": "b", "question": "q1", "title": "Chladný"}]})
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
