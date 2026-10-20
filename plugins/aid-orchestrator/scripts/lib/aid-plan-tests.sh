# shellcheck shell=bash
# aid-plan-tests.sh — the nightly tests a plan names, run by the close itself and bound to the candidate
# (P117 (17); WAN P111: the close profile did not run the plan's Playwright/T2 tests, CP7 reported "T2 without
# evidence" twice, and a hand-attached proof could not be accepted).
#
# execution.yaml (state root):
#   plan_tests:
#     - glob: "**/*.bats"               # which plan-named tests this entry runs
#       command: "bats {path}"          # {path}: repo-relative, run from the candidate worktree's top
#       nightly: false                  # true: every matching plan-named test is run (e2e without a tier header)
#       timeout_s: 600                  # 1..1800, default 600
# A plan-named test (a Create:/Test:/Modify: path that looks like a test) is the close's to run when its file
# carries `aid-tier: t2`, or an entry that matches it says nightly: true.
#
#   aid_plan_tests_named <plan_file>                      plan-named test paths, one per line
#   aid_plan_tests_command <exec_yaml> <path>             "<command>\t<timeout>\t<nightly>" of the first entry, or 1
#   aid_plan_tests_run <tree> <exec_yaml> <plan_file> <candidate> <run_dir>   writes <run_dir>/plan-tests.json
#   aid_plan_tests_bad <run_dir> <candidate>              0 when every listed test passed at this candidate with an
#                                                          unchanged log; else prints why and returns 1

_AID_PT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F _aid_ancillary_glob_match >/dev/null || source "${_AID_PT_LIB}/aid-ancillary.sh"
declare -F aid_test_tier_of >/dev/null || source "${_AID_PT_LIB}/aid-test-tier.sh"

aid_plan_tests_named() {
  grep -oE '^- (Create|Test|Modify): `[^`]+`' "$1" 2>/dev/null | sed -E 's/^- [A-Za-z]+: `([^`]+)`/\1/' \
    | grep -E '(^|/)(tests?|spec|e2e|__tests__)/|(^|/)test[-_][^/]*$|_test\.[^/]+$|\.(test|spec)\.[^/]+$|\.bats$' | sort -u
}

aid_plan_tests_command() {
  local ex="$1" p="$2" g c t n
  [[ -f "$ex" ]] || return 1
  while IFS=$'\t' read -r g c t n; do
    _aid_ancillary_glob_match "$p" "$g" && { printf '%s\t%s\t%s\n' "$c" "$t" "$n"; return 0; }
  done < <(yq -o=json '.plan_tests // []' "$ex" 2>/dev/null | jq -r '.[] | [(.glob // ""), (.command // ""), ((.timeout_s // 600) | tostring), ((.nightly // false) | tostring)] | @tsv')
  return 1
}

# _aid_pt_nightly <tree> <exec_yaml> <path> — the close runs it: a t2 header, or a matching nightly: true entry
_aid_pt_nightly() {
  local line; line="$(aid_plan_tests_command "$2" "$3")" && [[ "$(cut -f3 <<< "$line")" == true ]] && return 0
  [[ -f "$1/$3" ]] && [[ "$(aid_test_tier_of "$1/$3" 2>/dev/null)" == t2 ]]
}

# aid_plan_tests_expected <tree> <exec_yaml> <plan_file> — the set the close must run: [{path, command, timeout_s}]
aid_plan_tests_expected() {
  local p line cmd t rows="[]"
  while IFS= read -r p; do
    [[ -n "$p" ]] && _aid_pt_nightly "$1" "$2" "$p" || continue
    cmd=""; t=600
    if line="$(aid_plan_tests_command "$2" "$p")"; then cmd="$(cut -f1 <<< "$line")"; t="$(cut -f2 <<< "$line")"; fi
    [[ "$t" =~ ^[1-9][0-9]*$ ]] || t=600; (( t > 1800 )) && t=1800
    rows="$(jq -c --arg p "$p" --arg c "$cmd" --argjson t "$t" '. + [{path: $p, command: (if $c == "" then null else $c end), timeout_s: $t}]' <<< "$rows")"
  done < <(aid_plan_tests_named "$3")
  printf '%s\n' "$rows"
}

# aid_plan_tests_needed <tree> <exec_yaml> <plan_file> — 0 when the plan names a test the close must run
aid_plan_tests_needed() {
  local p
  while IFS= read -r p; do [[ -n "$p" ]] && _aid_pt_nightly "$1" "$2" "$p" && return 0; done < <(aid_plan_tests_named "$3")
  return 1
}

# _aid_pt_secrets — the values a test log must never hold: secret-named variables, connection strings with
# credentials (the same rule as the measurement, aid-plan-diff.sh)
_aid_pt_secrets() {
  local n v
  while IFS= read -r n; do v="${!n:-}"; (( ${#v} >= 6 )) && printf '%s\n' "$v"; done < <(compgen -e | grep -Ei 'TOKEN|SECRET|PASSWORD|PASSWD|_KEY$|APIKEY|CREDENTIAL' || true)
  while IFS= read -r n; do v="${!n:-}"; [[ "$v" == *://*@* ]] && printf '%s\n' "$v"; done < <(compgen -e | grep -Ei '(_URL|_DSN|_URI)$' || true)
}

aid_plan_tests_run() {
  local tree="$1" ex="$2" plan="$3" cand="$4" rd="$5" p line cmd t rc start dur log rows="[]" i=0
  mkdir -p "${rd}/plan-tests"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    _aid_pt_nightly "$tree" "$ex" "$p" || continue
    i=$((i + 1)); log="${rd}/plan-tests/${i}.log"
    if ! line="$(aid_plan_tests_command "$ex" "$p")" || [[ -z "$(cut -f1 <<< "$line")" ]]; then
      rows="$(jq -c --arg p "$p" '. + [{path: $p, command: null, exit: null, reason: "no plan_tests entry in execution.yaml runs it"}]' <<< "$rows")"; continue
    fi
    # the path reaches the command as a variable, never as text spliced into it (a path with shell characters)
    cmd="$(cut -f1 <<< "$line")"; cmd="${cmd//\{path\}/\"\$AID_TEST_PATH\"}"; t="$(cut -f2 <<< "$line")"
    [[ "$t" =~ ^[1-9][0-9]*$ ]] || t=600; (( t > 1800 )) && t=1800
    start="$(date +%s)"; rc=0
    # the log is the last 8 KiB, redacted before it reaches the disk (lib/aid-redact-filter.py)
    ( cd "$tree" && AID_TEST_PATH="$p" timeout "$t" bash -c "$cmd" </dev/null 2>&1 ) \
      | AID_PD_SECRETS="$(_aid_pt_secrets)" python3 "${_AID_PT_LIB}/aid-redact-filter.py" out > "$log"
    rc="${PIPESTATUS[0]}"
    dur=$(( $(date +%s) - start ))
    rows="$(jq -c --arg p "$p" --arg c "$(cut -f1 <<< "$line")" --argjson e "$rc" --argjson d "$dur" --argjson t "$t" --arg l "plan-tests/${i}.log" \
      --arg s "$(sha256sum "$log" | cut -d' ' -f1)" '. + [{path: $p, command: $c, exit: $e, duration_s: $d, timeout_s: $t, log: $l, log_sha256: $s}]' <<< "$rows")"
  done < <(aid_plan_tests_named "$plan")
  jq -n --arg c "$cand" --argjson r "$rows" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg ps "$(sha256sum "$plan" | cut -d' ' -f1)" --arg es "$( [[ -f "$ex" ]] && sha256sum "$ex" | cut -d' ' -f1 || echo none)" \
    '{artifact_type: "plan_tests", candidate_sha: $c, plan_sha256: $ps, execution_yaml_sha256: $es, tests: $r, run_at: $at, run_by: "aid-plan-fsm.sh plan-finalize --stage produce"}' > "${rd}/plan-tests.json"
}

aid_plan_tests_bad() {
  local rd="$1" cand="$2" f="${1}/plan-tests.json" row p tree="${3:-}" ex="${4:-}" plan="${5:-}"
  [[ -f "$f" ]] || { echo "no plan-tests.json — the close did not run the plan's nightly tests (plan-finalize --stage produce)"; return 1; }
  [[ "$(jq -r .run_by "$f")" == "aid-plan-fsm.sh plan-finalize --stage produce" ]] || { echo "plan-tests.json was not written by the close"; return 1; }
  # the close's own record of writing it (stage-writes.jsonl; its digest is verified by decide's integrity check)
  if [[ -n "$tree" ]]; then
    # the LAST record of plan-tests.json and of every log it names is the produce stage's, with today's digest
    local f2 last
    for f2 in plan-tests.json $(jq -r '.tests[].log // empty' "$f"); do
      last="$(jq -c -s --arg p "$f2" 'map(select(.path == $p)) | last // empty' "${rd}/stage-writes.jsonl" 2>/dev/null)"
      [[ -n "$last" && "$(jq -r .stage <<< "$last")" == produce \
         && "$(jq -r .sha256 <<< "$last")" == "sha256:$(sha256sum "${rd}/${f2}" 2>/dev/null | cut -d' ' -f1)" ]] \
        || { echo "${f2} has no record of the close's produce stage writing it as it is now (stage-writes.jsonl)"; return 1; }
    done
    # the plan and the configuration it ran under are the ones decided on now (their digests, Codex review)
    [[ "$(sha256sum "$plan" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .plan_sha256 "$f")" ]] || { echo "the plan changed after the close ran its tests — produce again"; return 1; }
    [[ "$( [[ -f "$ex" ]] && sha256sum "$ex" | cut -d' ' -f1 || echo none)" == "$(jq -r .execution_yaml_sha256 "$f")" ]] || { echo "execution.yaml changed after the close ran the plan's tests — produce again"; return 1; }
    # exactly the set the current plan and execution.yaml ask (Codex review of P117 E)
    local want got
    want="$(aid_plan_tests_expected "$tree" "$ex" "$plan" | jq -cS 'map({path, command, timeout_s}) | sort_by(.path)')"
    got="$(jq -cS '.tests | map({path, command, timeout_s: (.timeout_s // 600)}) | sort_by(.path)' "$f")"
    [[ "$want" == "$got" ]] || { echo "plan-tests.json ran $(jq -c 'map(.path)' <<< "$got"), the plan and execution.yaml now ask $(jq -c 'map(.path)' <<< "$want") — produce again"; return 1; }
  fi
  [[ "$(jq -r .candidate_sha "$f")" == "$cand" ]] || { echo "plan-tests.json is of candidate $(jq -r '.candidate_sha[:12]' "$f"), not ${cand:0:12}"; return 1; }
  while IFS= read -r row; do
    p="$(jq -r .path <<< "$row")"
    [[ "$(jq -r '.command // ""' <<< "$row")" != "" ]] || { echo "${p}: $(jq -r .reason <<< "$row")"; return 1; }
    [[ "$(jq -r .exit <<< "$row")" == 0 ]] || { echo "${p}: exit $(jq -r .exit <<< "$row") (log ${rd}/$(jq -r .log <<< "$row"))"; return 1; }
    [[ "$(sha256sum "${rd}/$(jq -r .log <<< "$row")" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .log_sha256 <<< "$row")" ]] \
      || { echo "${p}: its log changed after the run"; return 1; }
  done < <(jq -c '.tests[]' "$f")
  return 0
}
