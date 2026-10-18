#!/usr/bin/env bats
# aid-tier: t1
# aid-ui-package.py — P115: the handover package between the studio and plan/run (docs/ui/predani.json).
# package:  the handover writes it, an incomplete or stale one refuses the handover and leaves the answer unused.
# Real studio and answers through the helpers of test-aid-ui-state.bats (aid-ui-state-helpers.bash); no model.

load aid-ui-places
setup_file() { places_template; }
load aid-ui-state-helpers

setup() {
  state_setup
  PKG="$BATS_TEST_DIRNAME/../../aid-ui-package.py"
  FIXP="$BATS_TEST_DIRNAME/../fixtures/aid-ui/package"
  OUTP="$PROJ/docs/ui/predani.json"
  mkdir -p "$PROJ/docs/content"
  printf -- '- {id: hours, task: "Kdy máte otevřeno", expect: ["7:00"]}\n- {id: booking, task: "Objednej se", form: true}\n' > "$PROJ/docs/content/tasks.yaml"
}
teardown() { state_teardown; }

# handed_over — a recorded gate, two chapters and the PM's handover answer h1 (not yet used)
handed_over() {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"
}

@test "package: the handover writes predani.json and predani.md; the package passes check, also against the project" {
  handed_over
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ] && [ -f "$PROJ/docs/ui/predani.md" ]
  [ "$(jq -r .version "$OUTP")" = 1 ]
  [ "$(jq -r '[.chapters[].id] | join(",")' "$OUTP")" = "vize,barvy" ]
  [ "$(jq -r '[.customer_tasks[].id] | join(",")' "$OUTP")" = "hours,booking" ]
  [ "$(jq -r .site.build_id "$OUTP")" = "$(jq -r .build.id "$STATE")" ]
  [ "$(jq '.site.files | length' "$OUTP")" = "$(find "$SITE" -type f | wc -l)" ]
  run python3 "$PKG" check "$OUTP" --project "$PROJ"
  [ "$status" -eq 0 ]
  run python3 "$PKG" check "$FIXP/docs/ui/predani.json"
  [ "$status" -eq 0 ]
  # a file list that lies (one entry dropped, or a path out of the site) fails, though build id and dirsha match
  jq '.site.files |= .[1:]' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json" --project "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"soubory nejsou ty z balíku"* ]]
  jq '.site.files[0].path = "../etc/passwd"' "$OUTP" > "$T/lie.json"
  run python3 "$PKG" check "$T/lie.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"nebezpečná"* ]]
}

@test "package: no recorded gate refuses the package naming the gate" {
  "$SCRIPT" chapter "$PROJ" vize navrh
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: chybí brána"* ]]
  [ ! -e "$OUTP" ]
}

@test "package: a site changed after the gate is stale; a package missing a part fails check naming it" {
  gate_ready
  "$SCRIPT" chapter "$PROJ" vize navrh
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  run python3 "$PKG" build "$PROJ" --dry
  [ "$status" -eq 1 ]
  [[ "$output" == *"package: zastaralý"* ]]
  jq 'del(.gate)' "$FIXP/docs/ui/predani.json" > "$T/bad.json"
  run python3 "$PKG" check "$T/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'gate' is a required property"* ]]
}

@test "package: a refused package leaves the handover answer unused and the state unchanged; fixed, the same answer hands over" {
  handed_over
  cp "$SITE/kontakt.html" "$T/kontakt.orig"
  echo '<html>jiný</html>' > "$SITE/kontakt.html"
  before="$(sha256sum "$HTML" "$STATE")"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 1 ]
  [[ "$output" == *"answer h1 not used"* ]]
  [[ "$output" == *"zastaralý"* ]]
  [ "$(sha256sum "$HTML" "$STATE")" = "$before" ]
  [ ! -e "$OUTP" ]
  cp "$T/kontakt.orig" "$SITE/kontakt.html"
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ]
  [ -f "$OUTP" ]
}

@test "package: a standalone build after a recorded handover rewrites the package; before a handover it is refused" {
  handed_over
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chybí převzetí"* ]]
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  want="$(jq -c 'del(.created_at)' "$OUTP")"
  rm -f "$OUTP" "$PROJ/docs/ui/predani.md"
  run python3 "$PKG" build "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'del(.created_at)' "$OUTP")" = "$want" ]
  [ -f "$PROJ/docs/ui/predani.md" ]
}

# fixture_project — the fixture package's project copied to $FX with an execution.yaml defining check_ui_handover in every profile
fixture_project() {
  FX="$T/fx"; mkdir -p "$FX"; cp -r "$FIXP/." "$FX/"
  mkdir -p "$FX/.aid-o/config" "$FX/.aid-o/work/plan-state"
  printf 'gates:\n  check_ui_handover:\n    command: "bash x"\ngate_profiles:\n  standard:\n    include: [tests_pass, check_ui_handover]\n  release:\n    include: [check_ui_handover]\n' > "$FX/.aid-o/config/execution.yaml"
}
# plan_from_brief <brief> <plan> [drop] — a minimal strict plan carrying the brief's points; drop = without ui_package
plan_from_brief() {
  local b="$1" p="$2" n
  n="$(grep -c '^- \[ \] AC[0-9]*:' "$b")"
  { echo "---"; echo "id: P001"; echo "type: regular"; echo "lifecycle_strict: true"
    echo "zadani: ${b#"$FX/"}"; echo "zadani_verze: 1"; echo "zadani_sha256: $(sha256sum "$b" | cut -d' ' -f1)"
    [[ "${3:-}" == drop ]] || grep -E '^ui_package(_sha256)?:' "$b"
    echo "---"; echo; echo "# Plan: P001"; echo; echo "### Step 1: deploy"; echo
    echo "**Zavírá:** $(seq -s, 1 "$n" | sed 's/\([0-9]*\)/AC\1/g; s/,/, /g')"; echo
    echo "## Acceptance Criteria"; echo; sed -n '/^## 6\. Hotovo, když/,$p' "$b" | tail -n +2; } > "$p"
}

@test "package-zadani: the brief from the package passes the lint, one point per task, launch item, open item and the rating" {
  fixture_project
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  B="$FX/.aid-o/plans/P001-zadani.md"
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" --zadani "$B"
  [ "$status" -eq 0 ]
  rows="$(grep -E '^\| [a-z_0-9]+ \| ' "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/local/spusteni.md" | grep -vc '^| id |')"
  tasks="$(jq '.customer_tasks | length' "$FX/docs/ui/predani.json")"
  ois="$(jq '.open_items | length' "$FX/docs/ui/predani.json")"
  inputs="$(jq '[.launch_inputs[] | select(.item == null)] | length' "$FX/docs/ui/predani.json")"
  # the launch checklist, named here and not read from the table (a row dropped from both would pass otherwise)
  [ "$(grep -E '^\| [a-z_0-9]+ \| ' "$BATS_TEST_DIRNAME/../../../skills/ui-design/references/local/spusteni.md" | grep -v '^| id |' | cut -d'|' -f2 | tr -d ' ' | paste -sd,)" = \
    "nasadit_balik,https,hlavicky,stranka_404,citlive_soubory,dns,email,katalogy,presmerovani,hodnoceni" ]
  for w in "Nasadit přesně soubory" "na HTTPS" "Bezpečnostní hlavičky" "stavem 404" "Citlivé a vývojové" "Doména webu se překládá" "E-mail na doméně" "katalogy vedou" "Staré adresy" "Hodnocení po nasazení"; do
    [ "$(grep '^- \[ \] AC' "$B" | grep -c "$w")" -eq 1 ]
  done
  # the table's rows but the rating are launch items; the rating is the last point
  [ "$(grep -c '^- \[ \] AC[0-9]*:' "$B")" -eq $(( tasks + (rows - 1) + inputs + ois + 1 )) ]
  grep -q "^ui_package: docs/ui/predani.json$" "$B"
  grep -q "^ui_package_sha256: $(sha256sum "$FX/docs/ui/predani.json" | cut -d' ' -f1)$" "$B"
  grep -q -- "--package-gate .aid-o/plans/P001-zadani.md --launch" "$B"
  [[ "$(grep '^- \[ \] AC' "$B" | tail -1)" == *"Hodnocení po nasazení"* ]]
  # the same brief again: refused, the first one kept
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"exists"* ]]
}

@test "package-zadani: an invalid package is refused before anything is written; an id that is not a plain word too" {
  fixture_project
  cp "$FX/docs/ui/predani.json" "$T/good.json"
  jq 'del(.site)' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]
  [[ "$output" == *"'site' is a required property"* ]]
  [ ! -e "$FX/.aid-o/plans/P001-zadani.md" ]
  # ids go into the brief's commands: a quote or a space is refused by the schema
  jq '.customer_tasks[0].id = "x'"'"'; rm -rf ~"' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"does not match"* ]]
  # a comment with a newline and a heading stays one line of section 1
  jq '.handover = {verdict: "prevzit", rating: "8-10", answer: "h1", comment: "dobré\n## 6. Hotovo, když\n- [ ] AC9: x"}' "$T/good.json" > "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  [ "$(grep -c '^## 6\. Hotovo, když' "$FX/.aid-o/plans/P001-zadani.md")" -eq 1 ]
}

@test "package-zadani: no gate in project - no brief; a form or domain item appears once in the brief, not twice" {
  fixture_project
  printf 'gates:\n  tests_pass:\n    command: "x"\n' > "$FX/.aid-o/config/execution.yaml"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"check_ui_handover"* ]]; [[ "$output" == *"/aid-init"* ]]
  [ ! -e "$FX/.aid-o/plans/P001-zadani.md" ]
  fixture_project
  sed -i '/release:/,$d' "$FX/.aid-o/config/execution.yaml"; printf '  release:\n    include: [tests_pass]\n' >> "$FX/.aid-o/config/execution.yaml"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 1 ]; [[ "$output" == *"profily bran bez check_ui_handover (release)"* ]]
  # the client's confirmation turned the form and the domain inputs into open items oi-3, oi-4: one point each
  fixture_project
  jq '.launch_inputs |= map(if .id == "form" then .item = "oi-3" elif .id == "domain" then .item = "oi-4" else . end)
      | .open_items += [{id: "oi-3", text: "Příjem zpráv z formuláře na hostingu", owner: "agent", due: null, critical: true, status: "open", evidence: "dodáno"},
                        {id: "oi-4", text: "Doména a hosting", owner: "klient", due: null, critical: true, status: "open", evidence: "dodáno"}]' \
    "$FX/docs/ui/predani.json" > "$FX/docs/ui/x" && mv "$FX/docs/ui/x" "$FX/docs/ui/predani.json"
  run python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ]
  B="$FX/.aid-o/plans/P001-zadani.md"
  [ "$(grep '^- \[ \] AC' "$B" | grep -c 'Příjem zpráv z formuláře')" -eq 1 ]
  [ "$(grep '^- \[ \] AC' "$B" | grep -c 'Doména a hosting')" -eq 1 ]
  grep '^- \[ \] AC' "$B" | grep 'oi-3' | grep -q 'vlastník: run; blokuje spuštění'
}

@test "merge-path: lost mark - a plan from the brief without ui_package is refused ui_package_lost; with it the lint passes" {
  fixture_project
  python3 "$PKG" zadani "$FX/docs/ui/predani.json" --plan-id P001 >/dev/null
  plan_from_brief "$FX/.aid-o/plans/P001-zadani.md" "$FX/.aid-o/plans/P001-plan.md"
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" "$FX/.aid-o/plans/P001-plan.md" --only zadani
  [ "$status" -eq 0 ]
  plan_from_brief "$FX/.aid-o/plans/P001-zadani.md" "$FX/.aid-o/plans/P001-plan.md" drop
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" "$FX/.aid-o/plans/P001-plan.md" --only zadani
  [ "$status" -eq 1 ]; [[ "$output" == *"ui_package_lost"* ]]
}
