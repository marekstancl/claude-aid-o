#!/usr/bin/env bats
# aid-tier: t1
# P116 - the /aid-ui studio for web applications: files and JSON only, no browser, no model.
# screens:  aid-ui-screens.py check - the model of screens and tasks (UA-1) refuses what a skeleton, a gate or a
#           package could not stand on.
# app-path: the webapp path of the studio (aid-ui-state.sh, real studio server): skips with a recorded reason, the
#           tasks approved by the product owner (PM) only, bound to the model's sha; the web path unchanged.

load aid-ui-places
setup_file() { places_template; }
load aid-ui-state-helpers

setup() {
  T="$(mktemp -d)"; APPT="$T"
  SCR="$BATS_TEST_DIRNAME/../../aid-ui-screens.py"
  FIXA="$BATS_TEST_DIRNAME/../fixtures/aid-ui/app"
  APP="$T/app"
  mkdir -p "$APP/docs/design"
  cp "$FIXA/docs/design/screens.json" "$APP/docs/design/screens.json"
  M="$APP/docs/design/screens.json"
}
teardown() { [[ -z "${PROJ:-}" ]] || state_teardown; rm -rf "$APPT"; }

# mutate <jq filter> - rewrite the copied model
mutate() { jq "$1" "$M" > "$T/m.json" && mv "$T/m.json" "$M"; }

@test "screens: the fixture model passes the schema and every cross rule" {
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCREENS OK: 3 obrazovek, 2 úloh"* ]]
}

@test "screens: an action leading to a screen the model does not have is refused" {
  mutate '(.screens[0].actions[0].to) = "nikam"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/screens/0/actions/0/to: akce seznam.novy vede na neexistující obrazovku nikam"* ]]
  # an action without any target fails the schema
  cp "$FIXA/docs/design/screens.json" "$M"; mutate 'del(.screens[0].actions[0].to)'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"'to' is a required property"* ]]
}

@test "screens: a task missing one of the seven UA-1 states is refused; nenastává, protože … is a valid state" {
  mutate 'del(.tasks[0].states.recovery)'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"/tasks/0/states: 'recovery' is a required property"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[1].states.empty = "  "'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"/tasks/1/states/empty"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[1].states.empty = "nenastává, protože smazání nabízí jen existující poznámka"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 0 ]
}

@test "screens: a task without a verifiable result (done_when) is refused, also one whose result is not where it ends" {
  mutate 'del(.tasks[0].done_when)'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"'done_when' is a required property"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[0].done_when.screen = "seznam"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"úloha zalozit končí na detail, výsledek čeká na seznam"* ]]
}

@test "screens: a destructive action without confirmation is refused" {
  mutate 'del(.screens[2].actions[0].confirm)'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"destruktivní akce detail.smazat bez potvrzení"* ]]
}

@test "screens: a submitting task with neither a failure path nor nenastává, protože … is refused" {
  mutate '.tasks[0].failure_paths = []'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"úloha zalozit odesílá data, ale nemá cestu selhání"* ]]
  mutate '.tasks[0].states.failure = "nenastává, protože ukládá jen do prohlížeče"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 0 ]
}

@test "screens: steps that do not follow, an unknown action, a recover off the failing screen and an unknown replaced task are refused" {
  mutate '.tasks[1].steps[1].screen = "formular" | .tasks[1].steps[1].action = "zpet"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"krok 2 stojí na formular, předchozí akce vede na detail"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[0].steps[0].action = "letet"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"akce letet není na obrazovce seznam"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[0].failure_paths[0].recover = "smazat"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"obnova smazat není akce obrazovky formular"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[0].steps[1].input = {"na\"zev": "x"}'   # a field name goes into a selector
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"/tasks/0/steps/1/input"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"; mutate '.tasks[0].replaces = "stara"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"úloha výchozího stavu stara neexistuje (projekt nemá .aid-ui/baseline/tasks.json)"* ]]
  mkdir -p "$APP/.aid-ui/baseline"; echo '[{"id": "stara"}]' > "$APP/.aid-ui/baseline/tasks.json"
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 0 ]
}

@test "screens: a missing model names the step that writes it; broken JSON exits 2" {
  rm "$M"
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"píše ho krok Obrazovky a úlohy"* ]]
  echo '{' > "$M"
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 2 ]; [[ "$output" == *"není JSON"* ]]
}

@test "screens: a schema error and a cross-rule error are both reported; an unreadable baseline is named, never read as empty" {
  mutate 'del(.tasks[1].states.recovery) | .screens[0].actions[0].to = "nikam"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"/tasks/1/states: 'recovery' is a required property"* ]]
  [[ "$output" == *"vede na neexistující obrazovku nikam"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"
  mkdir -p "$APP/.aid-ui/baseline"; echo '{' > "$APP/.aid-ui/baseline/tasks.json"
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *".aid-ui/baseline/tasks.json nejde přečíst"* ]]
}

# app_proj [variant json] - a studio project (state_setup) of kind webapp with the fixture model; places off (the
# place rules have their own suite) and step 1 options all false
app_proj() {
  state_setup
  jqw --argjson v "${1:-{\"type\":\"webapp\",\"brand\":\"none\",\"local\":false\}}" '.variant = $v | .places = false | .options = {vision: false, seo: false, identity: false}'
  mkdir -p "$PROJ/docs/design"; cp "$FIXA/docs/design/screens.json" "$PROJ/docs/design/screens.json"
  MSHA="$(sha256sum "$PROJ/docs/design/screens.json" | cut -d' ' -f1)"
}
# ans_by <client|agent> <id> <kind> <target> [decision] - the question answered with the agent token (not the PM's page)
ans_by() {
  studio
  local p="$PROJ/.aid-ui/studio/payload.json" role=()
  [[ "$3" != task_map ]] || "$SCRIPT" method "$PROJ" task_map >/dev/null
  [[ "$1" != client ]] || role=(-H "X-AID-Role: client")
  jq --arg q "$2" --arg k "$3" --arg t "$4" --arg o "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
    '.questions += [{id: $q, kind: $k, target: $t, opened_at: $o} + (if $k == "exception" then {part: "vychozi-stav"} else {} end)] | .cards += [{id: "x", question: $q, method: "aplikace-postup.md"}]' "$p" > "$p.t" && mv "$p.t" "$p"
  curl -sf -o /dev/null -H "X-AID-Token: $STOKEN" "${role[@]}" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg q "$2" --arg k "$3" --arg t "$4" --arg d "${5:-approve}" '{question: $q, kind: $k, target: $t, decision: $d, choice: "x", comment: "role"}')" "$AID_UI_STUDIO_URL/answer"
  "$SCRIPT" record-answer "$PROJ" --question "$2"
}

@test "app-path: a webapp goes past step 1 only with a recorded reason for every skipped part" {
  app_proj
  "$SCRIPT" step "$PROJ" 1
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 1 ]; [[ "$output" == *"the app skips vize hledani logo without a recorded reason"* ]]
  mkdir -p "$PROJ/.aid-ui/studio"; [ -f "$PROJ/.aid-ui/studio/payload.json" ] || echo '{"questions": [], "cards": []}' > "$PROJ/.aid-ui/studio/payload.json"
  "$SCRIPT" decide "$PROJ" --step "Zadání a obsah" --title přeskočeno --outcome "vize přeskočena" --why "aplikace slogan nepotřebuje" >/dev/null
  "$SCRIPT" decide "$PROJ" --step "Zadání a obsah" --title přeskočeno --outcome "hledani přeskočena" --why "aplikace za přihlášením se nehledá" >/dev/null
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 1 ]; [[ "$output" == *"skips logo without"* ]]
  "$SCRIPT" decide "$PROJ" --step "Zadání a obsah" --title přeskočeno --outcome "logo přeskočena" --why "interní nástroj v LAN" >/dev/null
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 0 ]; [ "$(jq .step "$STATE")" = 2 ]
  # a webapp with a new brand keeps its logo place: identity false is refused even with a record, new needs none
  jqw '.variant.brand = "new" | .step = 1'
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 1 ]; [[ "$output" == *"new brand (variant.brand new) keeps its logo place"* ]]
  jqw '.options.identity = "new"'
  sed -i '/logo přeskočena/d' "$PROJ/.aid-ui/studio/history.jsonl"
  run "$SCRIPT" step "$PROJ" 2
  [ "$status" -eq 0 ]
}

@test "app-path: an agent's answer to a webapp's task question is refused; the PM's or the client role's is recorded with the model sha" {
  app_proj
  run ans_by agent a1 task_map "docs/design/screens.json@$MSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_tasks_need_owner"*"by agent"* ]]
  # the PM's answer to a target that is not the model now
  run ans p0 structure "sha256:abc"
  [ "$status" -ne 0 ]; [ "$(jq '.answers.p0' "$STATE")" = null ]
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"is not approved by the owner"* ]]
  ans p1 structure "docs/design/screens.json@$MSHA"
  [ "$(jq -r .app.approved_model_sha "$STATE")" = "$MSHA" ]
  [ "$(jq -r .answers.p1.by "$STATE")" = pm ]
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 0 ]; [[ "$output" == *"model approved: $MSHA"* ]]
  # the client role plays the owner (PM 19. 10. 2026): its approval counts too, the baseline stays the PM's
  ans_by client c1 structure "docs/design/screens.json@$MSHA" >/dev/null
  [ "$(jq -r .answers.c1.by "$STATE")" = client ]; [ "$(jq -r .app.approved_model_sha "$STATE")" = "$MSHA" ]
  # no recorded variant: the guard fails closed - a model in the project is an app's, whatever the agent's file says
  jqw 'del(.variant)'; rm -f "$PROJ/.aid-ui/variant.json"
  run ans_by agent a2 structure "docs/design/screens.json@$MSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_tasks_need_owner"* ]]
}

@test "app-path: a model changed after the PM approved it makes model-approved fail until the PM approves the new one" {
  app_proj
  ans p1 structure "docs/design/screens.json@$MSHA"
  jq '.tasks[0].title = "Založit novou poznámku"' "$PROJ/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$PROJ/docs/design/screens.json"
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since the owner approved it"* ]]
  n="$(sha256sum "$PROJ/docs/design/screens.json" | cut -d' ' -f1)"
  ans p2 structure "docs/design/screens.json@$n"
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 0 ]
}

@test "app-path: a client exception approving the baseline list or dropping a baseline task is refused; the PM's is recorded" {
  app_proj '{"type":"webapp","brand":"none","local":false,"existing":true}'
  mkdir -p "$PROJ/.aid-ui/baseline"; echo '[{"id": "stara"}, {"id": "hledat"}]' > "$PROJ/.aid-ui/baseline/tasks.json"
  BSHA="$(sha256sum "$PROJ/.aid-ui/baseline/tasks.json" | cut -d' ' -f1)"
  run ans_by client e1 exception "baseline@$BSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_owner_only"*"by client"* ]]
  run ans_by client e2 exception "task@stara"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_owner_only"* ]]
  # the PM's answer to a list that is not the one now, or to a task the baseline lacks, is refused too
  run ans e4 exception "baseline@0123abcd"
  [ "$status" -ne 0 ]; [ "$(jq '.answers.e4' "$STATE")" = null ]
  run ans e5 exception "task@nikdy"
  [ "$status" -ne 0 ]; [ "$(jq '.answers.e5' "$STATE")" = null ]
  # dropping a task does not finish the baseline part; approving the list does
  ans e3 exception "task@stara"
  [ "$(jq -r .answers.e3.by "$STATE")" = pm ]; [ "$(jq '.app_baseline' "$STATE")" = null ]
  ans e6 exception "baseline@$BSHA"
  [ "$(jq -r .app_baseline.approved_sha "$STATE")" = "$BSHA" ]
  # existing is only for a webapp
  run "$SCRIPT" set "$PROJ" variant '{"type":"web","brand":"new","local":true,"existing":true}' --answer v1
  [ "$status" -eq 2 ]
}

@test "app-path: a web project's structure question and steps are unchanged (an agent's answer is recorded, no skip records)" {
  state_setup
  jqw '.variant = {type: "web", brand: "new", local: true} | .places = false | .options = {vision: false, seo: false, identity: false}'
  run ans_by agent w1 structure "$(sha_of '{"pages":[]}')" choose
  [ "$status" -eq 0 ]; [ "$(jq -r .answers.w1.by "$STATE")" = agent ]
  [ "$(jq '.app' "$STATE")" = null ]
  "$SCRIPT" step "$PROJ" 1; run "$SCRIPT" step "$PROJ" 5
  [ "$status" -eq 0 ]
}

@test "app-path: the studio shows the app parts for a webapp and the page parts for a web; a structure question finds its part by kind" {
  app_proj '{"type":"webapp","brand":"none","local":false,"existing":true}'
  studio
  st() { curl -s -H "X-AID-Token: $STOKEN" "$AID_UI_STUDIO_URL/state" | jq -r --arg p "$1" '.sections.steps[].parts[] | select(.id == $p) | .status'; }
  [ "$(st stranky)" = skipped ]; [ "$(st obrazovky)" != skipped ]; [ "$(st vychozi-stav)" != skipped ]; [ "$(st vize)" = skipped ]
  ans p1 structure "docs/design/screens.json@$MSHA"
  [ "$(st obrazovky)" = done ]
  jqw '.variant = {type: "web", brand: "new", local: true}'
  [ "$(st stranky)" != skipped ]; [ "$(st obrazovky)" = skipped ]; [ "$(st vychozi-stav)" = skipped ]
}

@test "merge-path: app skeleton refuses an invalid model and a webapp without a model, naming why, nothing written" {
  SK="$BATS_TEST_DIRNAME/../../lib/aid-ui-skeleton.py"
  mkdir -p "$APP/.aid-ui"; echo '{"type": "webapp", "brand": "none", "local": false}' > "$APP/.aid-ui/variant.json"
  mutate 'del(.screens[2].actions[0].confirm)'
  run python3 "$SK" build "$APP"
  [ "$status" -eq 2 ]; [[ "$output" == *"the model fails aid-ui-screens.py check"*"bez potvrzení"* ]]
  [ ! -e "$APP/site" ]
  rm "$M"
  run python3 "$SK" build "$APP"
  [ "$status" -eq 2 ]; [[ "$output" == *"no docs/design/screens.json"*"Obrazovky a úlohy"* ]]
  # the valid model builds one page per screen and the home page, all as a draft
  cp "$FIXA/docs/design/screens.json" "$M"
  run python3 "$SK" build "$APP"
  [ "$status" -eq 0 ]; [[ "$output" == *'"approved": false'* ]]
  [ "$(ls "$APP"/site/*/index.html | wc -l)" -eq 3 ]; grep -q data-aid-draft "$APP/site/index.html"
}

@test "merge-path: generated scenario checks done_when - one per task, the model's sha, the result, the failure variants" {
  FL="$BATS_TEST_DIRNAME/../../aid-ui-flows.py"
  mkdir -p "$APP/.aid-ui/scenarios"
  echo '// not generated' > "$APP/.aid-ui/scenarios/vlastni.mjs"
  printf '%s\n%s\n' "// aid-ui-flows.py: generated from docs/design/screens.json - do not edit, run aid-ui-flows.py generate" 'x' > "$APP/.aid-ui/scenarios/stara.mjs"
  run python3 "$FL" generate "$APP"
  [ "$status" -eq 0 ]; [[ "$output" == *"FLOWS: 2 scenarios"* ]]; [[ "$output" == *"removed .aid-ui/scenarios/stara.mjs"* ]]
  [ -f "$APP/.aid-ui/scenarios/vlastni.mjs" ] && [ ! -e "$APP/.aid-ui/scenarios/stara.mjs" ]   # a foreign file is never touched
  sha="$(sha256sum "$M" | cut -d' ' -f1)"
  grep -q "^export const model_sha256 = \"$sha\";" "$APP/.aid-ui/scenarios/zalozit.mjs"
  t() { sed -n 's/^const T = \(.*\);$/\1/p' "$APP/.aid-ui/scenarios/$1.mjs"; }
  [ "$(t zalozit | jq -c .done)" = '{"screen":"detail","expect":"Nákup na sobotu"}' ]
  t zalozit | jq -e '.variants["fail-1"] == {at_step: 2, kind: "network", recover: "znovu", generated: false}' >/dev/null
  t smazat | jq -e '(.variants | keys) == ["fail-1", "fail-2"] and .variants["fail-2"].kind == "server" and .kinds["detail.smazat"] == "destructive"' >/dev/null
  # the runtime: a result is done only when the result screen shows the expected text; a missing state is refused
  grep -q 'done: !!ok' "$APP/.aid-ui/scenarios/zalozit.mjs"; grep -q 'nemá stav scénáře' "$APP/.aid-ui/scenarios/zalozit.mjs"
  node --check "$APP/.aid-ui/scenarios/zalozit.mjs"
  # no failure path in the model: one generated network failure on the last submit, recovered by that action
  mutate '.tasks[0].failure_paths = [] | .tasks[0].states.failure = "nenastává, protože ukládá jen do prohlížeče"'
  python3 "$FL" generate "$APP" >/dev/null
  t zalozit | jq -e '.variants["fail-1"] == {at_step: 2, kind: "network", recover: "ulozit", generated: true}' >/dev/null
  # a title with a line break stays inside the generated comment: nothing of the model becomes code
  mutate '.tasks[0].title = "x\nprocess.exit(7) //\u2028y"'
  python3 "$FL" generate "$APP" >/dev/null
  ! grep -q '^process.exit' "$APP/.aid-ui/scenarios/zalozit.mjs"; node --check "$APP/.aid-ui/scenarios/zalozit.mjs"
  # an invalid model writes nothing
  mutate 'del(.tasks[0].done_when)'
  run python3 "$FL" generate "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"fails aid-ui-screens.py check"* ]]
}

# ---------------------------------------------------------------- baseline: an existing app keeps every task (P116)
BL="$BATS_TEST_DIRNAME/../../aid-ui-baseline.py"
# base_proj - the fixture model in an existing-app project with the fixture baseline list (not approved)
base_proj() {
  mkdir -p "$APP/.aid-ui/baseline"
  cp "$BATS_TEST_DIRNAME/../fixtures/aid-ui/app-existing/tasks.json" "$APP/.aid-ui/baseline/tasks.json"
  BSHA="$(sha256sum "$APP/.aid-ui/baseline/tasks.json" | cut -d' ' -f1)"
  echo '{"variant": {"type": "webapp", "existing": true}, "answers": {}}' > "$APP/docs/design/brand-state.json"
}
st_set() { jq "$1" "$APP/docs/design/brand-state.json" > "$T/s.json" && mv "$T/s.json" "$APP/docs/design/brand-state.json"; }
# approve_list [by] - the state as record-answer leaves it after the PM's (or another's) approval of the list
approve_list() { st_set ".app_baseline = {approved_sha: \"$BSHA\", answer: \"b1\"} | .answers.b1 = {kind: \"exception\", decision: \"approve\", by: \"${1:-pm}\", target: \"baseline@$BSHA\"}"; }
captured() { echo "{\"tasks_sha256\": \"$BSHA\", \"results\": [{\"id\": \"prehled\", \"passed\": true}, {\"id\": \"hledat\", \"passed\": true}]}" > "$APP/.aid-ui/baseline/result.json"; }
# gate_passed <task>... - the last gate's app_flows rows of these tasks pass on the model now
gate_passed() {
  local s; s="$(sha256sum "$M" | cut -d' ' -f1)"; mkdir -p "$APP/.aid-ui/verify"
  printf '%s\n' "$@" | jq -R --arg s "$s" '{check: "app_flows", page: ., state: "normal", status: "pass", model_sha256: $s}' | jq -s '{rows: .}' > "$APP/.aid-ui/verify/result.json"
}
# replace <new task index> <baseline id> <expect> - a model task replaces a baseline task with that result
replace() { mutate ".tasks[$1].replaces = \"$2\" | .tasks[$1].done_when.expect = \"$3\""; }

@test "baseline: list drafts today's tasks from the navigation; capture refuses the draft and a list changed after the PM approved it" {
  mkdir -p "$T/old"; cp "$BATS_TEST_DIRNAME/../fixtures/aid-ui/app-existing/site/index.html" "$T/old/"
  echo '{"variant": {"type": "webapp", "existing": true}}' > "$APP/docs/design/brand-state.json"
  run python3 "$BL" list "$APP" --url "file://$T/old/index.html"
  [ "$status" -eq 0 ]; [[ "$output" == *"BASELINE DRAFT"*"2 úloh z navigace"* ]]
  [ "$(jq -r '[.[].title] | join(",")' "$APP/.aid-ui/baseline/tasks.json")" = "Přehled,Hledání" ]
  [ "$(jq -r '.[1].steps[0].url' "$APP/.aid-ui/baseline/tasks.json")" = "/?hledat=1" ]   # the query is another screen
  run python3 "$BL" list "$APP" --url "file://$T/old/index.html"
  [ "$status" -eq 1 ]; [[ "$output" == *"exists"* ]]   # never overwritten
  run python3 "$BL" capture "$APP" --url http://127.0.0.1:9/
  [ "$status" -eq 1 ]; [[ "$output" == *"the PM has not approved the baseline list (exception baseline@"* ]]
  BSHA="$(sha256sum "$APP/.aid-ui/baseline/tasks.json" | cut -d' ' -f1)"; approve_list
  jq '.[0].result.expect = "jiný"' "$APP/.aid-ui/baseline/tasks.json" > "$T/t.json" && mv "$T/t.json" "$APP/.aid-ui/baseline/tasks.json"
  run python3 "$BL" capture "$APP" --url http://127.0.0.1:9/
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since the PM approved it"* ]]
}

@test "baseline: a task of today's app without a replacing task with the same result fails" {
  base_proj; approve_list; captured
  replace 0 prehled "3 objednávky čekají"; gate_passed zalozit
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"FAIL hledat: žádná nová úloha ji nenahrazuje (replaces)"* ]]
  [[ "$output" == *"OK   prehled: nahrazena úlohou zalozit"* ]]
  # replaced, but with another result, or by a task that did not pass the gate
  replace 1 hledat "Výsledek hledání"; gate_passed zalozit smazat
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"FAIL hledat: náhrada končí jiným výsledkem"* ]]
  replace 1 hledat "Nalezeno: mouka (2 položky)"; gate_passed zalozit
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"FAIL hledat: náhrada neprošla poslední bránou"* ]]
}

@test "baseline: every task replaced with the same result passes; two new tasks for one old pass when either reproduces it" {
  base_proj; approve_list; captured
  replace 0 prehled "Dnes: 3 objednávky čekají"; replace 1 hledat "Nalezeno: mouka"; gate_passed zalozit smazat
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 0 ]; [[ "$output" == *"compare: OK (2 úloh výchozího stavu)"* ]]
  # results of an older model do not count
  cp "$FIXA/docs/design/screens.json" "$M"; replace 0 prehled "3 objednávky čekají"; replace 1 hledat "Nalezeno: mouka"
  gate_passed zalozit smazat; mutate '.tasks[1].title = "Smazat poznámku teď"'
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"neprošla poslední bránou"* ]]
  # two tasks replace prehled: one with another result, one with the same - passes
  cp "$FIXA/docs/design/screens.json" "$M"; replace 0 prehled "jiný souhrn"; replace 1 prehled "3 objednávky čekají"
  mutate '.tasks += [.tasks[1] | .id = "najit" | .replaces = "hledat" | .done_when.expect = "Nalezeno: mouka"]'
  gate_passed zalozit smazat najit
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "baseline: a task the PM approved to drop passes and is listed; a client's or an agent's drop does not" {
  base_proj; approve_list; captured
  replace 0 prehled "3 objednávky čekají"; gate_passed zalozit
  st_set '.answers.c1 = {kind: "exception", decision: "approve", by: "client", target: "task@hledat", comment: "klient"}'
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"FAIL hledat"* ]]
  st_set '.answers.p1 = {kind: "exception", decision: "approve", by: "pm", target: "task@hledat", comment: "hledání se ruší"}'
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 0 ]; [[ "$output" == *"ZRUŠENA hledat: zrušení schválil PM (hledání se ruší)"* ]]
}

@test "baseline: no baseline passes with bez výchozího stavu; an unapproved or uncaptured baseline fails compare" {
  run python3 "$BL" compare "$FIXA"
  [ "$status" -eq 0 ]; [[ "$output" == *"bez výchozího stavu"* ]]
  base_proj; replace 0 prehled "3 objednávky čekají"; replace 1 hledat "Nalezeno: mouka"; gate_passed zalozit smazat
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"has not approved the baseline list"* ]]; [[ "$output" == *"not captured"* ]]
  approve_list; captured
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------- app-package: the handover of an app (P116)
PKGPY="$BATS_TEST_DIRNAME/../../aid-ui-package.py"
# app_handover [result jq filter] - a studio project of kind webapp: the fixture model approved by the PM, a recorded
# gate whose result carries the app_flows rows of both tasks on that model, two chapters and the PM's handover
app_handover() {
  state_setup
  jqw '.options = {vision: false, seo: false, identity: false}'
  mkdir -p "$PROJ/docs/design"; cp "$FIXA/docs/design/screens.json" "$PROJ/docs/design/screens.json"
  MSHA="$(sha256sum "$PROJ/docs/design/screens.json" | cut -d' ' -f1)"
  "$SCRIPT" build-record "$PROJ" "$SITE" >/dev/null
  result ".rows += ([\"zalozit\", \"smazat\"] | map({check: \"app_flows\", page: ., state: \"normal\", viewport: \"1440\", browser: \"chromium\", role: \"\", status: \"pass\", model_sha256: \"$MSHA\"})) | ${1:-.}"
  "$SCRIPT" gate-record "$PROJ" "$RES" >/dev/null   # recorded while the variant is still a web's: the required matrix of pages
  end_order; serve_200; "$SCRIPT" links "$PROJ" --web "$LINK_URL" --customer "$CUST_URL" >/dev/null
  "$SCRIPT" chapter "$PROJ" vize navrh; "$SCRIPT" chapter "$PROJ" barvy navrh
  ans h1 handover "$("$SCRIPT" chapter-all-target "$PROJ")"   # the helper rates the web place with the web's type: before the variant
  jqw --arg s "$MSHA" '.variant = {type: "webapp", brand: "none", local: false} | .app = {approved_model_sha: $s, answer: "p1", at: "t"}' 
  printf 'gates:\n  check_ui_handover:\n    command: "bash x"\ngate_profiles:\n  standard:\n    include: [check_ui_handover]\n' > "$PROJ/.aid-o/config/execution.yaml"
}

@test "app-package: the package of an app carries kind, the approved model and the task results, and passes check" {
  app_handover
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  O="$PROJ/docs/ui/predani.json"
  [ "$(jq -r '.version, .kind, .screens.sha256, .screens.approved_sha256' "$O" | tr '\n' ' ')" = "2 webapp $MSHA $MSHA " ]
  [ "$(jq -c '[.task_results[] | [.task, .passed, .verified_on, .model_sha256 == $s]]' --arg s "$MSHA" "$O")" = '[["zalozit",true,"skeleton",true],["smazat",true,"skeleton",true]]' ]
  run python3 "$PKGPY" check "$O" --project "$PROJ"
  [ "$status" -eq 0 ]
  # the model changed after the handover: the package is stale against the project
  jq '.app = "jiná"' "$PROJ/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$PROJ/docs/design/screens.json"
  run python3 "$PKGPY" check "$O" --project "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"model docs/design/screens.json není ten z předání"* ]]
  # a version 1 package stays valid; a web package cannot carry an app's parts
  run python3 "$PKGPY" check "$BATS_TEST_DIRNAME/../fixtures/aid-ui/package/docs/ui/predani.json"
  [ "$status" -eq 0 ]
  jq '.kind = "web" | .version = 1 | .x = 1 | del(.x)' "$O" > "$T/w.json"
  run python3 "$PKGPY" check "$T/w.json"
  [ "$status" -eq 1 ]
}

@test "app-package: the code-change brief passes the lint with the contract first, a point per task and per failure path" {
  app_handover
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  run python3 "$PKGPY" zadani "$PROJ/docs/ui/predani.json" --plan-id P001
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"úlohy 2, selhání 4, smlouva 1, spuštění 1"* ]]
  B="$PROJ/.aid-o/plans/P001-zadani.md"
  run bash "$BATS_TEST_DIRNAME/../../aid-plan-lint.sh" --zadani "$B"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -q '^- \[ \] AC1: Aplikace běží na adrese' "$B"; grep -q '^- \[ \] AC2: Smlouva stavby' "$B"
  grep -q 'AC3: Úloha „Založit poznámku“ projde včetně výsledku' "$B"; grep -q 'AC4: Selhání network v kroku 2 úlohy „Založit poznámku“' "$B"
  grep -q 'AC5: Selhání server v kroku 2 úlohy „Založit poznámku“' "$B"; grep -q 'AC6: Úloha „Smazat poznámku“' "$B"
  grep -q -- "--package-gate .aid-o/plans/P001-zadani.md --launch" "$B"
  grep -q "live-row docs/ui/predani.json task_recovery --detail 'zalozit / fail-1: výsledek nastal'" "$B"
  grep -q 'verified_on: skeleton' "$B"
}

@test "app-package: a gate without a passed task refuses the handover, nothing written" {
  app_handover '.rows |= map(select(.check != "app_flows"))'
  run "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1
  [ "$status" -ne 0 ]; [[ "$output" == *"chybí úloha, která prošla bránou"* ]]; [ ! -e "$PROJ/docs/ui/predani.json" ]
}

@test "app-package: one task passed and one failed refuses the handover; check refuses a package edited to a failed or foreign result" {
  app_handover '.rows |= map(if .check == "app_flows" and .page == "smazat" then .status = "fail" else . end)'
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"úlohy aplikace v bráně neprošly: app_flows smazat normal"* ]]
}

@test "app-package: check binds the task results to the model - failed, foreign, repeated or missing results are refused" {
  app_handover
  "$SCRIPT" chapter-all "$PROJ" --by PM --answer h1 >/dev/null
  O="$PROJ/docs/ui/predani.json"
  for f in '.task_results[1].passed = false' '.task_results[0].model_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
           '.task_results[1] = .task_results[0]'; do
    jq "$f" "$O" > "$T/b.json"; run python3 "$PKGPY" check "$T/b.json"; [ "$status" -eq 1 ] || { echo "$f passed"; return 1; }
  done
  jq '.task_results |= .[:1]' "$O" > "$T/b.json"
  run python3 "$PKGPY" check "$T/b.json"; [ "$status" -eq 0 ]   # alone the package cannot know the model's tasks
  run python3 "$PKGPY" check "$T/b.json" --project "$PROJ"; [ "$status" -eq 1 ]; [[ "$output" == *"nejsou úlohy modelu"* ]]
}

@test "app-package: a lost input in the gate (task_recovery fail) refuses the package" {
  app_handover '.rows += [{check: "task_recovery", page: "zalozit", state: "fail-1", viewport: "1440", browser: "chromium", role: "", status: "fail", detail: "krok 2: po selhání (network) se ztratil vstup nazev"}]'
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"úlohy aplikace v bráně neprošly: task_recovery zalozit fail-1"* ]]
}

@test "app-package: task results of an older model are refused" {
  app_handover '.rows |= map(if .check == "app_flows" then .model_sha256 = "0000000000000000000000000000000000000000000000000000000000000000" else . end)'
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"z jiného modelu než schváleného"* ]]
}

@test "app-package: a model the PM did not approve (or changed since) is refused" {
  app_handover
  jqw '.app.approved_model_sha = "1111111111111111111111111111111111111111111111111111111111111111"'
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"model docs/design/screens.json se změnil od schválení PM"* ]]
  jqw 'del(.app)'
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"PM neschválil"* ]]
}

@test "app-package: an existing app whose task of today has no replacement is refused at the handover" {
  app_handover
  mkdir -p "$PROJ/.aid-ui/baseline"; cp "$BATS_TEST_DIRNAME/../fixtures/aid-ui/app-existing/tasks.json" "$PROJ/.aid-ui/baseline/tasks.json"
  b="$(sha256sum "$PROJ/.aid-ui/baseline/tasks.json" | cut -d' ' -f1)"
  jqw --arg b "$b" '.app_baseline = {approved_sha: $b}'
  echo "{\"tasks_sha256\": \"$b\", \"results\": []}" > "$PROJ/.aid-ui/baseline/result.json"
  run python3 "$PKGPY" build "$PROJ" --dry
  [ "$status" -eq 1 ]; [[ "$output" == *"regrese existující aplikace"* ]]
}

@test "baseline: a list approved by anyone but the PM is not approved; a capture where a task failed does not count" {
  base_proj; approve_list client; captured
  replace 0 prehled "3 objednávky čekají"; replace 1 hledat "Nalezeno: mouka"; gate_passed zalozit smazat
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"has not approved the baseline list"* ]]
  run python3 "$BL" capture "$APP" --url http://127.0.0.1:9/
  [ "$status" -eq 1 ]; [[ "$output" == *"has not approved"* ]]
  approve_list
  echo "{\"tasks_sha256\": \"$BSHA\", \"results\": [{\"id\": \"prehled\", \"passed\": true}, {\"id\": \"hledat\", \"passed\": false}]}" > "$APP/.aid-ui/baseline/result.json"
  run python3 "$BL" compare "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"did not record every task of the list passing once (hledat)"* ]]
}

@test "screens: the bar (shell) - one only; a task step on it follows any screen; it has no state rows in the matrix" {
  mutate '.screens += [{id: "lista", title: "Lišta", purpose: "Na každé obrazovce.", nav: false, shell: true,
      actions: [{id: "stop", label: "STOP", to: "seznam", kind: "submit"}],
      states: {empty: "nenastává, protože lišta je vždy", loading: "Zastavuji…", error: "STOP nedoběhl; Zkusit znovu.", filled: "Lišta."}}]
    | .tasks += [{id: "zastavit", title: "Zastavit", roles: ["uživatel"], steps: [{screen: "seznam", action: "otevrit"}, {screen: "lista", action: "stop"}],
      done_when: {screen: "seznam", expect: "Pozastaveno"}, states: .tasks[1].states, failure_paths: [{at_step: 2, kind: "network", keeps_input: true, recover: "stop"}, {at_step: 2, kind: "server", keeps_input: true, recover: "stop"}]}]'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run python3 "$SCR" matrix "$APP"
  [ "$(jq '[.rows[] | select(.page == "screen:lista")] | length' <<<"$output")" -eq 0 ]
  [ "$(jq '[.rows[] | select(.page == "zastavit")] | length' <<<"$output")" -eq 4 ]
  mutate '.screens += [.screens[-1] | .id = "lista2"]'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"lišta (shell: true) je jen jedna"* ]]
}

@test "merge-path: the skeleton shows the model's fields, samples, data sources, trace, glossary, the bar's content, Zkusit znovu and Zpět" {
  SK="$BATS_TEST_DIRNAME/../../lib/aid-ui-skeleton.py"
  mkdir -p "$APP/.aid-ui"; echo '{"type": "webapp", "brand": "none", "local": false}' > "$APP/.aid-ui/variant.json"
  printf 'Poznámky\nZaložit poznámku\n' > "$APP/zadani.md"
  mutate '.requirements = [{id: "z1", source: "zadani.md:2", text: "Založit poznámku", covered_by: ["task:zalozit"]}, {id: "z2", source: "zadani.md:1", text: "Export", out_of_scope: "později"}]
    | .glossary = [{term: "Poznámka", meaning: "jeden zápis"}] | .out_of_scope = [{what: "Export", why: "později"}]
    | .screens[1].fields = [{name: "nazev", label: "Název poznámky", hint: "do 80 znaků"}]
    | .screens[0].sample = ["Nákup · 18. 10."] | .screens[0].data = [{what: "seznam", source: "databáze", freshness: "při načtení"}]
    | .screens[2].actions[1].back = true
    | .screens += [{id: "lista", title: "Lišta", purpose: "Nahoře.", nav: false, shell: true, actions: [], states: {empty: "nenastává, protože vždy", loading: "nenastává, protože vždy", error: "nenastává, protože vždy", filled: "3 poznámky"}}]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run python3 "$SK" build "$APP"; [ "$status" -eq 0 ]
  f="$APP/site/formular/index.html"; s="$APP/site/seznam/index.html"; d="$APP/site/detail/index.html"
  grep -q '<label for="f-formular-nazev">Název poznámky</label> <input id="f-formular-nazev" name="nazev" aria-describedby="h-formular-nazev f-formular-nazev-chyba">' "$f"
  grep -q 'Ukázka (ne skutečná data)' "$s"; grep -q 'seznam: databáze; při načtení' "$s"
  grep -q 'z1 (zadani.md:2): Založit poznámku → task:zalozit' "$s"; grep -q 'mimo rozsah: později' "$s"; grep -q '<b>Poznámka</b>: jeden zápis' "$s"
  grep -q 'class="lista-stav" role="status">3 poznámky' "$d"
  grep -q '>Zkusit znovu</a>' "$s"; grep -q 'data-aid-action="detail.zpet" data-aid-back' "$d"
  # a requirement without a cover or with a wrong source is refused by the check
  mutate '.requirements[0].source = "zadani.md:9"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"zadani.md:9 není soubor:řádek v projektu"* ]]
  mutate '.requirements[0].source = "zadani.md:2" | .requirements[0].covered_by = ["task:nikdy"]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"task:nikdy není úloha modelu"* ]]
}

@test "merge-path: one number in one place, named confirm buttons, actions by mode, task states on call, field limits, deep links" {
  SK="$BATS_TEST_DIRNAME/../../lib/aid-ui-skeleton.py"
  mkdir -p "$APP/.aid-ui"; echo '{"type": "webapp", "brand": "none", "local": false}' > "$APP/.aid-ui/variant.json"
  mutate '.values = {pocet: {value: "3", source: "ukázka: tři poznámky"}} | .modes = [{id: "bezi", label: "Běží"}, {id: "pauza", label: "Pauza"}]
    | .screens[0].sample = ["Poznámek: {pocet}"] | .screens[2].actions[0].confirm = "Smazat 1 z {pocet} poznámek?"
    | .screens[0].actions[1].query = "id=nakup-1" | .screens[0].actions[0].modes = ["bezi"] | .screens[0].actions[0].disabled_reason = "V pauze nové poznámky nejdou."
    | .screens[1].fields = [{name: "nazev", label: "Název", required: true, maxlength: 80, error: "Název je povinný, nejvýš 80 znaků."}]
    | .tasks[1].mode = "bezi"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 "$SK" build "$APP" >/dev/null
  s="$APP/site/seznam/index.html"; f="$APP/site/formular/index.html"; d="$APP/site/detail/index.html"
  grep -q 'Poznámek: 3' "$s"; grep -q 'Smazat 1 z 3 poznámek?' "$d"; grep -q '<b>3</b>: ukázka: tři poznámky' "$s"   # the named value in every text, with its source
  grep -q '>Smazat poznámku</a> <button type="button" data-aid-confirm-no>Nechat poznámku</button>' "$d"   # buttons name the action
  grep -q 'href="/detail/?id=nakup-1" data-aid-action="seznam.otevrit"' "$s"                # a deep link
  grep -q 'data-aid-modes="bezi" data-aid-reason="proc-seznam-novy"' "$s"; grep -q 'V pauze nové poznámky nejdou.' "$s"; grep -q 'data-aid-modes-list="bezi pauza"' "$s"
  grep -q 'data-aid-task-state="zalozit.validation" hidden' "$s"                              # a task's states on its first screen
  grep -q 'name="nazev" aria-describedby="f-formular-nazev-chyba" required maxlength="80"' "$f"; grep -q 'Název je povinný, nejvýš 80 znaků.' "$f"
  # the task-state rows are in the matrix; the generated scenario starts in the task's mode
  [ "$(python3 "$SCR" matrix "$APP" | jq '[.rows[] | select(.page == "task:zalozit")] | length')" -eq 6 ]
  python3 "$BATS_TEST_DIRNAME/../../aid-ui-flows.py" generate "$APP" >/dev/null
  grep -q '"url": "/seznam/?rezim=bezi"' "$APP/.aid-ui/scenarios/smazat.mjs"
  # an unknown value, an unknown mode, a mode-bound action without its reason, a confirm without its buttons are refused
  mutate '.screens[0].sample = ["{nikde}"] | .tasks[1].mode = "spi" | del(.screens[0].actions[0].disabled_reason) | del(.screens[2].actions[0].confirm_yes)'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]
  [[ "$output" == *"{nikde} není pojmenovaná hodnota"* ]]; [[ "$output" == *"režim spi model nezná"* ]]
  [[ "$output" == *"neříká proč jinak ne"* ]]; [[ "$output" == *"tlačítka, která jmenují akci"* ]]
}

@test "merge-path: a sample table is drawn as a real table with its caption and named values; a row of another width is refused" {
  SK="$BATS_TEST_DIRNAME/../../lib/aid-ui-skeleton.py"
  mkdir -p "$APP/.aid-ui"; echo '{"type": "webapp", "brand": "none", "local": false}' > "$APP/.aid-ui/variant.json"
  mutate '.values = {cena: {value: "120", source: "ukázka"}} | .screens[2].tables = [{caption: "Úrovně místo grafu", columns: ["Úroveň", "Cena"], rows: [["vstup", "{cena}"]]}]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 "$SK" build "$APP" >/dev/null
  grep -q '<table tabindex="0"><caption>Úrovně místo grafu</caption><thead><tr><th scope="col">Úroveň</th><th scope="col">Cena</th></tr></thead><tbody><tr><td>vstup</td><td>120</td></tr>' "$APP/site/detail/index.html"
  mutate '.screens[2].tables[0].rows += [["cíl"]] | .screens[2].tables[0].rows[0][1] = "{neni}"'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"nemá tolik buněk"* ]]; [[ "$output" == *"tables/0/rows/0/1"* ]]
  mutate '.screens[2].tables[0].rows = [["vstup", "1"]] | .screens[2].tables[0].caption = "Za {dni} dní"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"tables/0/caption"* ]]
}

@test "screens: a step that sends a form without one of its required fields is refused" {
  mutate '.screens[1].fields = [{name: "nazev", label: "Název", required: true}, {name: "stitek", label: "Štítek", required: true}]'
  run python3 "$SCR" check "$APP"
  [ "$status" -eq 1 ]; [[ "$output" == *"odešle formulář formular bez povinného pole stitek"* ]]
  mutate '(.tasks[0].steps[1].input.stitek) = "doma"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "screens (P118 lint): an amount, R or percent written out instead of a named value, a number in a purpose, a writing task without permission or both failure kinds are refused" {
  mutate '.screens[0].sample = ["Celkem 120 USDT"]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"/screens/0/sample/0: číslo s jednotkou „120 USDT“"* ]]
  mutate '.values = {celkem: {value: "120 USDT", source: "ukázka"}} | .screens[0].sample = ["Celkem {celkem}"]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  mutate '.screens[0].purpose = "Seznam poznámek, obnova po 30 s"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"/screens/0/purpose: účel obrazovky nese číslo"*"30 s"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"
  mutate '(.tasks[0].states.permission) = "nenastává, protože je jeden uživatel"'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"úloha zalozit zapisuje, stav oprávnění"* ]]
  cp "$FIXA/docs/design/screens.json" "$M"
  mutate '(.tasks[1].failure_paths) = [{at_step: 2, kind: "network", keeps_input: true, recover: "smazat"}]'
  run python3 "$SCR" check "$APP"; [ "$status" -eq 1 ]; [[ "$output" == *"úloha smazat zapisuje - potřebuje cestu selhání sítě"* ]]
}
