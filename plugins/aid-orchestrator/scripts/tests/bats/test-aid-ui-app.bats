#!/usr/bin/env bats
# aid-tier: t1
# P116 - the /aid-ui studio for web applications: files and JSON only, no browser, no model.
# screens:  aid-ui-screens.py check - the model of screens and tasks (UA-1) refuses what a skeleton, a gate or a
#           package could not stand on.

setup() {
  T="$(mktemp -d)"
  SCR="$BATS_TEST_DIRNAME/../../aid-ui-screens.py"
  FIXA="$BATS_TEST_DIRNAME/../fixtures/aid-ui/app"
  APP="$T/app"
  mkdir -p "$APP/docs/design"
  cp "$FIXA/docs/design/screens.json" "$APP/docs/design/screens.json"
  M="$APP/docs/design/screens.json"
}
teardown() { rm -rf "$T"; }

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
