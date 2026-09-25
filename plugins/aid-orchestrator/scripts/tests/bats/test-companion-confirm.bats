#!/usr/bin/env bats
# aid-tier: t0
# P102 Step 3 — the companion server keeps the PM's confirm per screen in memory
# (confirm-store.js); aid-ui-state.sh await-choice reads it from /aid/confirmed.
# Only the dependency-free store runs here (plain node, no node_modules).

setup() {
  STORE="$BATS_TEST_DIRNAME/../../../lib/brainstorm-server/confirm-store.js"
  command -v node >/dev/null || skip "node not installed"
}

js() { run node -e "const s = require('$STORE'); $1"; }

@test "a confirm without a choice field, matching hosts: stored and returned as /aid/confirmed serves it" {
  js 's.record("slogan-1.html", {type: "confirm", selected: ["s2"], text: " Vlastní "}, "10.20.20.22:3916", "10.20.20.22:3916") || process.exit(5);
      console.log(JSON.stringify(s.get("slogan-1.html")))'
  [ "$status" -eq 0 ]
  [ "$(jq -r .screen <<<"$output")" = slogan-1.html ]
  [ "$(jq -c .selected <<<"$output")" = '["s2"]' ]
  [ "$(jq -r .text <<<"$output")" = Vlastní ]
  [[ "$(jq -r .at <<<"$output")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]{12}Z$ ]]
}

@test "a host mismatch or a missing Origin is rejected; a path as screen is rejected" {
  js 'const a = s.record("logo-1.html", {selected: ["a"]}, "evil.example", "10.20.20.22:3916");
      const b = s.record("logo-1.html", {selected: ["a"]}, "", "10.20.20.22:3916");
      const c = s.record("../x.html", {selected: ["a"]}, "h:1", "h:1");
      console.log(a, b, c, s.get("logo-1.html"))'
  [ "$status" -eq 0 ]
  [ "$output" = "false false false null" ]
}

@test "clear on a rewritten screen removes its confirm; two screens never mix" {
  js 's.record("pages-1.html", {selected: ["uvod"]}, "h:1", "h:1");
      s.record("pages-2.html", {selected: ["cenik"]}, "h:1", "h:1");
      const two = s.get("pages-2.html").selected[0];
      s.clear("pages-1.html");
      console.log(s.get("pages-1.html"), two, s.get("pages-2.html").selected.join())'
  [ "$status" -eq 0 ]
  [ "$output" = "null cenik cenik" ]
}
