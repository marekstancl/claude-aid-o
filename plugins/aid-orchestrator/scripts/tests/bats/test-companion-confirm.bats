#!/usr/bin/env bats
# aid-tier: t0
# P102 Step 3 — the companion server keeps the PM's confirm per screen in memory
# (confirm-store.js); aid-ui-state.sh await-choice reads it from /aid/confirmed.
# Only the dependency-free store runs here (plain node, no node_modules).

setup() {
  STORE="$BATS_TEST_DIRNAME/../../../lib/brainstorm-server/confirm-store.js"
  command -v node >/dev/null || skip "node not installed"
}

js() { run node -e "const s = require('$STORE'); const ALLOWED = ['localhost', '127.0.0.1', '::1', '0.0.0.0', '10.20.20.22']; $1"; }

@test "a confirm without a choice field, matching hosts: stored and returned as /aid/confirmed serves it" {
  js 's.record("slogan-1.html", {type: "confirm", selected: ["s2"], text: " Vlastní "}, "10.20.20.22:3916", "10.20.20.22:3916", ALLOWED) || process.exit(5);
      console.log(JSON.stringify(s.get("slogan-1.html")))'
  [ "$status" -eq 0 ]
  [ "$(jq -r .screen <<<"$output")" = slogan-1.html ]
  [ "$(jq -c .selected <<<"$output")" = '["s2"]' ]
  [ "$(jq -r .text <<<"$output")" = Vlastní ]
  [[ "$(jq -r .at <<<"$output")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]{12}Z$ ]]
}

@test "a host mismatch or a missing Origin is rejected; a path as screen is rejected" {
  js 'const a = s.record("logo-1.html", {selected: ["a"]}, "evil.example", "10.20.20.22:3916", ALLOWED);
      const b = s.record("logo-1.html", {selected: ["a"]}, "", "10.20.20.22:3916", ALLOWED);
      const c = s.record("../x.html", {selected: ["a"]}, "h:1", "h:1", ["h"]);
      console.log(a, b, c, s.get("logo-1.html"))'
  [ "$status" -eq 0 ]
  [ "$output" = "false false false null" ]
}

@test "DNS rebinding: Origin and Host both a foreign name are rejected; own names on any port accepted" {
  js 'const a = s.record("logo-1.html", {selected: ["a"]}, "evil.example:3916", "evil.example:3916", ALLOWED);
      const b = s.record("logo-1.html", {selected: ["a"]}, "evil.example", "evil.example", ALLOWED);
      const c = s.record("logo-2.html", {selected: ["a"]}, "evil.example:3916", "evil.example:3916");
      const d = s.record("logo-3.html", {selected: ["a"]}, "localhost:50123", "localhost:50123", ALLOWED);
      const e = s.record("logo-4.html", {selected: ["a"]}, "[::1]:3916", "[::1]:3916", ALLOWED);
      console.log(a, b, c, s.get("logo-1.html"), d, e)'
  [ "$status" -eq 0 ]
  [ "$output" = "false false false null true true" ]
}

@test "clear on a rewritten screen removes its confirm; two screens never mix" {
  js 's.record("pages-1.html", {selected: ["uvod"]}, "h:1", "h:1", ["h"]);
      s.record("pages-2.html", {selected: ["cenik"]}, "h:1", "h:1", ["h"]);
      const two = s.get("pages-2.html").selected[0];
      s.clear("pages-1.html");
      console.log(s.get("pages-1.html"), two, s.get("pages-2.html").selected.join())'
  [ "$status" -eq 0 ]
  [ "$output" = "null cenik cenik" ]
}
