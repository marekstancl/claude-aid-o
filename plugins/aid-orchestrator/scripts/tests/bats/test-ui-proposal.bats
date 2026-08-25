#!/usr/bin/env bats
# aid-tier: t0
# test-ui-proposal.bats — a UI proposal starts from the application's real
# screen when there is one, is MARKED when there is not, never captures
# production data, and covers every viewport the project owes
# (P087 Steps 8 + 9).
#
# The capture tool is replaced by a fixture script (AID_UI_CAPTURE_CMD): this
# suite proves the basis decision and the viewport matrix, not Playwright.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  source "$AID_PLUGIN_PATH/scripts/lib/aid-ui-proposal.sh"
  TMP="$(mktemp -d)"
  APP="$TMP/app"; OUT="$TMP/out"
  mkdir -p "$APP/.aid-o/config" "$APP/src/components/ui" "$APP/src/styles"
  printf 'project_name: fixture\n' > "$APP/.aid-o/config/project.yaml"
  : > "$APP/src/styles/app.css"; : > "$APP/tailwind.config.js"
  printf '[{"url":"/api/x","status":200,"body":{}}]' > "$TMP/mocks.json"
  printf 'make the header sticky\n' > "$TMP/brief.md"
  # a capture that records what it was asked and leaves a "screenshot"
  cat > "$TMP/capture.sh" <<'SH'
#!/usr/bin/env bash
out=""; w=""; mocks=""
while [[ $# -gt 0 ]]; do case "$1" in --output-dir) out="$2";; --viewport-width) w="$2";; --api-mocks-file) mocks="$2";; esac; shift; done
[[ -n "$mocks" ]] || { echo "no mocks" >&2; exit 1; }
[[ -n "${FAIL_WIDTH:-}" && "$w" == "$FAIL_WIDTH" ]] && { echo "viewport refused" >&2; exit 1; }
printf 'png %s' "$w" > "$out/baseline.png"
SH
  chmod +x "$TMP/capture.sh"
  export AID_UI_CAPTURE_CMD="$TMP/capture.sh"
}
teardown() { rm -rf "$TMP"; }

@test "proposal: AC22 — with a screen and fixture data the basis is the live screen, captured per viewport" {
  aid_ui_proposal_build "$APP" "$OUT" --screen http://localhost:1/page --fixture-data "$TMP/mocks.json" --brief "$TMP/brief.md"
  [ "$(jq -r .basis "$OUT/proposal.json")" = "live-screen" ]
  [ "$(jq -r .marked "$OUT/proposal.json")" = "null" ]
  [ "$(cat "$OUT/desktop/baseline.png")" = "png 1280" ]
  [ "$(cat "$OUT/mobile/baseline.png")" = "png 390" ]
  [ "$(jq -c '[.viewports[].name]' "$OUT/proposal.json")" = '["desktop","mobile"]' ]
  [ "$(jq -r .brief "$OUT/proposal.json")" = "$TMP/brief.md" ]
}

@test "proposal: AC23 — without a screen the basis is the design system, inventoried from the tree, and the proposal says so" {
  aid_ui_proposal_build "$APP" "$OUT"
  [ "$(jq -r .basis "$OUT/proposal.json")" = "design-system" ]
  [[ "$(jq -r .marked "$OUT/proposal.json")" == "NO LIVE BASELINE"* ]]
  [ "$(jq -r .live_baseline "$OUT/proposal.json")" = "false" ]
  [ "$(jq -c '.design_system.theme_configs' "$OUT/proposal.json")" = '["tailwind.config.js"]' ]
  [ "$(jq -c '.design_system.style_sources' "$OUT/proposal.json")" = '["src/styles/app.css"]' ]
  [[ "$(jq -c '.design_system.component_dirs' "$OUT/proposal.json")" == *'"src/components"'* ]]
  [ ! -e "$OUT/desktop" ]
}

@test "proposal: AC24 — a screen without fixture data is NOT captured: nothing is photographed on real data, the proposal is marked and says why" {
  aid_ui_proposal_build "$APP" "$OUT" --screen http://localhost:1/page
  [ "$(jq -r .basis "$OUT/proposal.json")" = "design-system" ]
  [[ "$(jq -r .marked "$OUT/proposal.json")" == *"never captured on real data"* ]]
  [ "$(jq -r .production_data_used "$OUT/proposal.json")" = "false" ]
  [ ! -e "$OUT/desktop/baseline.png" ]
}

@test "proposal: AC25 — a responsive project (the default) owes desktop and mobile; the check refuses a proposal missing either rendering, naming the viewport" {
  aid_ui_proposal_build "$APP" "$OUT" --screen http://localhost:1/page --fixture-data "$TMP/mocks.json"
  printf 'x' > "$OUT/desktop/proposed.png"
  jq --arg p "$OUT/desktop/proposed.png" '.viewports[0].proposed = $p' "$OUT/proposal.json" > "$OUT/p2.json"
  run aid_ui_proposal_check "$OUT/p2.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mobile viewport (390x844) has no proposed rendering"* ]]
  printf 'x' > "$OUT/mobile/proposed.png"
  jq --arg p "$OUT/mobile/proposed.png" '.viewports[1].proposed = $p' "$OUT/p2.json" > "$OUT/p3.json"
  run aid_ui_proposal_check "$OUT/p3.json"
  [ "$status" -eq 0 ]
}

@test "proposal: AC26 — ui.responsive: false owes the desktop viewport only" {
  printf 'ui:\n  responsive: false\n' >> "$APP/.aid-o/config/project.yaml"
  run aid_ui_proposal_viewports "$APP"
  [ "$output" = "desktop 1280 720" ]
  aid_ui_proposal_build "$APP" "$OUT" --screen http://localhost:1/page --fixture-data "$TMP/mocks.json"
  [ "$(jq -c '[.viewports[].name]' "$OUT/proposal.json")" = '["desktop"]' ]
  [ "$(jq -r .responsive "$OUT/proposal.json")" = "false" ]
  [ ! -e "$OUT/mobile" ]
}

@test "proposal: AC27 — a mobile capture that fails stops the build naming the viewport, not with a general message" {
  FAIL_WIDTH=390 run aid_ui_proposal_build "$APP" "$OUT" --screen http://localhost:1/page --fixture-data "$TMP/mocks.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the mobile viewport (390x844) could not be captured"* ]]
  [ ! -e "$OUT/proposal.json" ]
}
