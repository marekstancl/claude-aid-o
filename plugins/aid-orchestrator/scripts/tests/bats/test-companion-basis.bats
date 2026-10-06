#!/usr/bin/env bats
# aid-tier: t0
# 2.114.0 — lib/brainstorm-server/basis.js composes the companion page of a UI
# brainstorm over the application's real screenshot: today (the capture at its
# real width) beside the proposal (the agent's screen in a frame at the same
# width); a design-system basis shows its NO LIVE BASELINE banner. Plain node,
# no express: the module is dependency-free on purpose.

setup() {
  B="$BATS_TEST_DIRNAME/../../../lib/brainstorm-server/basis.js"
  command -v node >/dev/null || skip "node not installed"
  T="$(mktemp -d)"; mkdir -p "$T/desktop" "$T/mobile"; printf 'PNG' > "$T/desktop/baseline.png"; printf 'PNG' > "$T/mobile/baseline.png"
}
teardown() { rm -rf "$T"; }
js() { run node -e "const b = require('$B'); $1"; }

@test "live-screen: the page carries the capture at the viewport width, the frame at the same width on /screen, one tab per viewport" {
  jq -n --arg d "$T/desktop/baseline.png" --arg m "$T/mobile/baseline.png" '{basis: "live-screen", viewports: [{name: "desktop", width: 1280, height: 720, baseline: $d}, {name: "mobile", width: 390, height: 844, baseline: $m}]}' > "$T/proposal.json"
  js "const x = b.load('$T/proposal.json'); process.stdout.write(b.compose(x, '/screen'))"
  [ "$status" -eq 0 ]
  [[ "$output" == *'data-basis="live-screen"'* ]]
  [[ "$output" == *'src="/basis/desktop/baseline.png"'*'style="width:1280px'* ]]
  [[ "$output" == *'<iframe id="proposal" src="/screen" style="width:1280px;height:720px"'* ]]
  [[ "$output" == *'data-vp="mobile" data-w="390"'* ]]
  [[ "$output" != *'class="basis-banner"'* ]]
}

@test "design-system: the banner carries the mark and the reason, there is no today pane; a basis without its screenshot or of an unknown kind is refused" {
  jq -n '{basis: "design-system", marked: "NO LIVE BASELINE — no screen to capture <x>", viewports: [{name: "desktop", width: 1280, height: 720, baseline: null}]}' > "$T/p2.json"
  js "const x = b.load('$T/p2.json'); process.stdout.write(b.compose(x, '/screen'))"
  [ "$status" -eq 0 ]
  [[ "$output" == *'class="basis-banner">NO LIVE BASELINE — no screen to capture &lt;x&gt;<'* ]]
  [[ "$output" != *'pane-today'* ]]
  jq -n --arg d "$T/nowhere.png" '{basis: "live-screen", viewports: [{name: "desktop", width: 1280, height: 720, baseline: $d}]}' > "$T/p3.json"
  js "b.load('$T/p3.json')"
  [ "$status" -ne 0 ]; [[ "$output" == *"no baseline capture"* ]]
  jq -n '{basis: "sketch", viewports: [{name: "desktop", width: 1280, height: 720}]}' > "$T/p4.json"
  js "b.load('$T/p4.json')"
  [ "$status" -ne 0 ]; [[ "$output" == *"neither live-screen nor design-system"* ]]
  js "process.stdout.write(String(b.load('')))"
  [ "$status" -eq 0 ]; [ "$output" = null ]
}
