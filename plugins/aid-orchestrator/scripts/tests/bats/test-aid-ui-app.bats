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
  [[ "$output" == *"destruktivní akce detail.smazat bez potvrzení (confirm)"* ]]
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

@test "app-path: the client role's or an agent's answer to a webapp's task question is refused; the PM's is recorded with the model sha" {
  app_proj
  run ans_by client c1 structure "docs/design/screens.json@$MSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_tasks_need_owner"*"by client"* ]]
  [ "$(jq '.answers.c1' "$STATE")" = null ]
  run ans_by agent a1 task_map "docs/design/screens.json@$MSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_tasks_need_owner"*"by agent"* ]]
  # the PM's answer to a target that is not the model now
  run ans p0 structure "sha256:abc"
  [ "$status" -ne 0 ]; [ "$(jq '.answers.p0' "$STATE")" = null ]
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"is not approved by the PM"* ]]
  ans p1 structure "docs/design/screens.json@$MSHA"
  [ "$(jq -r .app.approved_model_sha "$STATE")" = "$MSHA" ]
  [ "$(jq -r .answers.p1.by "$STATE")" = pm ]
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 0 ]; [[ "$output" == *"model approved: $MSHA"* ]]
  # no recorded variant: the guard fails closed - a model in the project is an app's, whatever the agent's file says
  jqw 'del(.variant)'; rm -f "$PROJ/.aid-ui/variant.json"
  run ans_by client c2 structure "docs/design/screens.json@$MSHA"
  [ "$status" -eq 1 ]; [[ "$output" == *"app_tasks_need_owner"* ]]
}

@test "app-path: a model changed after the PM approved it makes model-approved fail until the PM approves the new one" {
  app_proj
  ans p1 structure "docs/design/screens.json@$MSHA"
  jq '.tasks[0].title = "Založit novou poznámku"' "$PROJ/docs/design/screens.json" > "$T/m.json" && mv "$T/m.json" "$PROJ/docs/design/screens.json"
  run "$SCRIPT" model-approved "$PROJ"
  [ "$status" -eq 1 ]; [[ "$output" == *"changed since the PM approved it"* ]]
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

