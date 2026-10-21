#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: defaults/refusal-classes.yaml
# P117: every refusal code the plugin prints has a class saying who acts on it in an --auto run, so a run never
# stops on a PM question for a technical refusal. Defect it catches: a new refusal added without deciding who
# answers it (WAN P109-P112: eight stops on the PM in two days, each a code routed to the PM by default).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  REG="$AID_PLUGIN_PATH/defaults/refusal-classes.yaml"
}

@test "refusal class: every code the scripts print (When AID refuses, _pr_refuse, _dlg_refuse, _increment_fail, _pfsm_precondition, --blocked-checks) has a class from the closed set" {
  local codes c missing="" bad=""
  codes="$( { grep -roh 'When AID refuses: [a-z0-9_]*' "$AID_PLUGIN_PATH/scripts" | sed 's/.*: //'
              grep -roh '_\(pr\|dlg\)_refuse [a-z0-9_]*' "$AID_PLUGIN_PATH/scripts" | awk '{print $2}'
              grep -roh '_increment_fail [a-z0-9_]*' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" | awk '{print $2}'
              grep -roh '_pfsm_precondition "[a-z_]*"' "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" | cut -d'"' -f2
              # the forceable conditions: what --force --blocked-checks may waive
              grep -rohE --include='*.sh' --exclude-dir=tests -e "--blocked-checks [\"'][a-z0-9_]+[\"']" "$AID_PLUGIN_PATH/scripts" | sed -E "s/.*[\"']([a-z0-9_]+)[\"']/\1/"; } \
            | grep -vx -e '' -e with | sort -u)"
  for c in $codes; do
    yq -e ".codes.\"$c\"" "$REG" >/dev/null 2>&1 || missing+=" $c"
  done
  [ -z "$missing" ] || { echo "codes without a class:$missing"; false; }
  bad="$(yq -r '.codes | to_entries[] | select(.value.class | test("^(agent_fix|agent_fix_then_stand_in|prevent|stand_in|pm|incident|not_in_run)$") | not) | .key' "$REG")"
  [ -z "$bad" ] || { echo "classes outside the set: $bad"; false; }
}

@test "refusal class: _fsm_refusal_next prints the class from the same file; an unknown code reads as pm (fail-closed)" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/aid-fsm.sh' >/dev/null 2>&1; aid_refusal_class amend_scope_no_brief_point; aid_refusal_class no_such_code_xyz; _fsm_refusal_next amend_scope_no_brief_point 2>&1 | tail -1"
  echo "$output"
  [[ "${lines[0]}" == stand_in ]]; [[ "${lines[1]}" == pm ]]; [[ "${lines[2]}" == "class: stand_in"* ]]
}

@test "refusal class: a numbered code reads its <n> row (gates_runner_exit_1 is agent_fix, not pm); the uppercase codes of the recovery ladder have classes; aid-fsm.sh and aid-stand-in.sh read the registry through the one library" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-refusal-class.sh'; aid_refusal_class gates_runner_exit_1; aid_refusal_class gates_runner_exit_137"
  [ "${lines[0]}" = agent_fix ]; [ "${lines[1]}" = agent_fix ]
  local c missing=""
  for c in $(bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-recovery-ladder.sh' >/dev/null 2>&1; _aid_ladder_class_constants"); do
    yq -e ".codes.\"$c\"" "$REG" >/dev/null 2>&1 || missing+=" $c"
  done
  [ -z "$missing" ] || { echo "uppercase codes without a class:$missing"; false; }
  grep -q 'lib/aid-refusal-class.sh' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  grep -q 'lib/aid-refusal-class.sh' "$AID_PLUGIN_PATH/scripts/aid-stand-in.sh"
  ! grep -q 'refusal-classes.yaml' "$AID_PLUGIN_PATH/scripts/aid-stand-in.sh" "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" | grep -v '^#'
  ! grep -E 'refusal-classes\.yaml"' "$AID_PLUGIN_PATH/scripts/aid-stand-in.sh" "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" | grep -vE '^\S+:\s*#'
}
