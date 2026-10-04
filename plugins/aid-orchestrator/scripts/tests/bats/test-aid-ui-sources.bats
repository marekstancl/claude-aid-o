#!/usr/bin/env bats
# aid-tier: t1
# P108 Step 3 — aid-ui-sources.py: candidates are listed with redacted excerpts and never enter
# the sources; a session enters only with the PM's approval; only the human's own records are
# kept; every detector of the shared redaction table fires; torn lines are counted.

setup() {
  SRC="$BATS_TEST_DIRNAME/../../aid-ui-sources.py"
  T="$BATS_TEST_TMPDIR"; P="$T/proj"; S="$T/sessions"; M="$P/.aid-ui/sources/manifest.json"
  mkdir -p "$P/docs/content" "$P/docs/design" "$S"
  printf '# Pekárna\nPečeme z kvásku.\n' > "$P/PRODUCT.md"
  echo '{"answers":{}}' > "$P/docs/design/brand-state.json"
  # every record carries cwd = the project, as Claude Code writes it; a foreign project's cwd differs
  u() { jq -nc --arg t "$1" --arg c "${2:-$P}" '{type:"user", cwd:$c, timestamp:"2026-09-09T10:00:00Z", message:{role:"user", content:$t}}'; }
  pad="$(printf 'x%.0s' {1..286})"   # the cut at 300 falls inside the secret's value
  {
    u "Chci web pro pekárnu, pečeme z kvásku od roku 2015."               # human, no origin
    u "heslo: password=hunter22secret a api_key=abcdefgh123 a token ghp_abcdefghijklmnop123456"
    u "pem -----BEGIN RSA PRIVATE KEY----- a Bearer abcdefghijklmnopqrstuv a AKIAABCDEFGHIJKLMNOP"
    u "openai sk-abcdefghijklmnopqrstu a github_pat_abcdefghijklmnopqrstuvwx a $(printf 'A%.0s' {1..45})"
    u "$pad password=straddlesecret99"                                   # a secret across the 300-char cut
    jq -nc --arg c "$P" '{type:"user", cwd:$c, origin:{kind:"human"}, timestamp:"2026-09-09T11:00:00Z", message:{content:"Zákazníci chválí kůrku."}}'
    jq -nc --arg c "$P" '{type:"user", cwd:$c, isMeta:true, message:{content:"TEXT SKILLU frontend-design"}}'
    jq -nc --arg c "$P" '{type:"user", cwd:$c, origin:{kind:"task-notification"}, message:{content:"NOTIFIKACE agenta"}}'
    jq -nc --arg c "$P" '{type:"user", cwd:$c, message:{content:[{type:"tool_result", content:"VYSTUP NASTROJE"}]}}'
    u "<system-reminder>PRIPOMINKA</system-reminder>"
    u "<pasted_content>VLOZENY TEXT</pasted_content>"
    u "CIZI PROJEKT ve stejném souboru" /jiny/projekt
    echo '{"type":"user", "message": {"content": "roztrzeny'
    jq -nc '{type:"assistant", message:{content:"ODPOVED AGENTA"}}'
  } > "$S/s1.jsonl"
  u "CIZI SOUBOR jiného projektu" /jiny/projekt > "$S/s2.jsonl"
}

@test "--list: candidates with redacted excerpts, project files as sources, no session text in sources" {
  run python3 "$SRC" "$P" --list --sessions-dir "$S"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '[.sources[] | select(.kind == "session")] | length == 0' "$M" >/dev/null
  jq -e '.sources[] | select(.path == "PRODUCT.md")' "$M" >/dev/null
  # a file with no record of this project is not a candidate at all
  jq -e '[.candidates[].file] | length == 1 and (.[0] | endswith("/s1.jsonl"))' "$M" >/dev/null
  ! grep -q "CIZI" "$M"
  c="$(jq -c '.candidates[0]' "$M")"
  [ "$(jq .records_human <<<"$c")" -eq 6 ]
  [ "$(jq .torn_lines <<<"$c")" -eq 1 ]
  jq -e '.excerpts | length == 5 and all(length <= 300)' <<<"$c" >/dev/null
  ex="$(jq -r '.excerpts | join(" | ")' <<<"$c")"
  [[ "$ex" == *"kvásku od roku 2015"* ]]
  for bad in "TEXT SKILLU" NOTIFIKACE VYSTUP PRIPOMINKA VLOZENY hunter22secret abcdefgh123 ghp_abcdef "BEGIN RSA" "Bearer abc" AKIAABC "sk-abc" github_pat_ AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA straddle 'password=s'; do
    [[ "$ex" != *"$bad"* ]] || { echo "excerpt leaks: $bad"; return 1; }
  done
  # --sessions-from admits the original project of a pilot copy
  python3 "$SRC" "$P" --list --sessions-dir "$S" --sessions-from /jiny/projekt >/dev/null
  jq -e '[.candidates[].file] | length == 2' "$M" >/dev/null
}

@test "a session not approved by the PM is refused; an approved one enters with every secret redacted" {
  run python3 "$SRC" "$P" --session "$S/s1.jsonl"
  [ "$status" -eq 1 ]; [[ "$output" == *"is not approved"* ]]
  # an approval of another file or another kind does not count
  sha="$(sha256sum "$S/s1.jsonl" | cut -d' ' -f1)"
  jq --arg t "$S/s2.jsonl@$sha" '.answers.a = {kind:"sources", decision:"approve", target:$t}
     | .answers.b = {kind:"facts", decision:"approve", target:"\($t)"}' "$P/docs/design/brand-state.json" > "$T/s" && mv "$T/s" "$P/docs/design/brand-state.json"
  run python3 "$SRC" "$P" --session "$S/s1.jsonl"; [ "$status" -eq 1 ]
  jq --arg t "$S/s1.jsonl@$sha" '.answers.c = {kind:"sources", decision:"approve", target:$t}' "$P/docs/design/brand-state.json" > "$T/s" && mv "$T/s" "$P/docs/design/brand-state.json"
  run python3 "$SRC" "$P" --session "$S/s1.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  txt="$P/$(jq -r '.sources[] | select(.kind == "session") | .text' "$M")"
  grep -q "kvásku od roku 2015" "$txt"; grep -q "chválí kůrku" "$txt"
  ! grep -q "CIZI PROJEKT" "$txt"
  for bad in "TEXT SKILLU" NOTIFIKACE VYSTUP PRIPOMINKA VLOZENY "ODPOVED AGENTA" hunter22secret abcdefgh123 ghp_abcdef "BEGIN RSA" "Bearer abc" AKIAABC "sk-abc" github_pat_ AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; do
    ! grep -qF "$bad" "$txt" || { echo "kept: $bad"; return 1; }
  done
  for d in assigned_secret github_token pem_private_key bearer_token aws_access_key openai_key github_pat high_entropy_blob; do
    grep -q "<redacted:$d>" "$txt" || { echo "detector did not fire: $d"; return 1; }
  done
  jq -e '.sources[] | select(.kind == "session") | .secret_lines_removed >= 10 and .torn_lines == 1 and .records_human == 6' "$M" >/dev/null
}
