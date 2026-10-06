#!/usr/bin/env bats
# aid-tier: t0
# 2.114.0 — lib/brainstorm-server/lifetime.js: a companion ends itself after
# 12 h with no browser and no new screen, not while the PM keeps it (Držet,
# a .keep file), and 60 days after it started whatever the PM pressed. Plain
# node with an injected clock.

setup() {
  L="$BATS_TEST_DIRNAME/../../../lib/brainstorm-server/lifetime.js"
  command -v node >/dev/null || skip "node not installed"
  T="$(mktemp -d)"
}
teardown() { rm -rf "$T"; }
js() { run node -e "const lt = require('$L'); let t = 0; const now = () => t; const l = lt.create({screenDir: '$T', now}); const H = 3600*1000; $1"; }

@test "idle after 12 h with nobody connected and nothing new; a connected browser or a new screen resets it" {
  js "t = 11*H; console.log(l.check()); t = 12*H; console.log(l.check()); l.touch(); t = 23*H; console.log(l.check()); t = 24*H + 1; console.log(l.check()); l.connected(); t = 48*H; console.log(l.check()); l.disconnected(); t = 59*H; console.log(l.check()); t = 60*H; console.log(l.check())"
  [ "$status" -eq 0 ]
  [ "$(paste -sd' ' <<<"$output")" = "null idle null idle null null idle" ]
}

@test "kept: no idle exit, the .keep file is the record; unkept: idle again; expired after 60 days even when kept" {
  js "console.log(l.keep('pm'), l.isKept()); t = 13*H; console.log(l.check()); console.log(l.unkeep(), l.isKept()); console.log(l.check()); l.keep('pm'); t = 60*24*H; console.log(l.check())"
  [ "$status" -eq 0 ]
  [ "$(paste -sd' ' <<<"$output")" = "true true null false false idle expired" ]
  js "l.keep('pm'); console.log(require('fs').readFileSync('$T/.keep','utf8').includes('\"by\":\"pm\"'))"
  [ "$output" = true ]
}
