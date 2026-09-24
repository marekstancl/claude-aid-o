#!/usr/bin/env bash
# aid-tier: t2
# test-execution-yaml-readers.sh — every key the execution.yaml composer writes
# has a reader (P097 Step 4).
#
# WHY THIS FILE EXISTS: 2.102.0 found eight keys the composer had written for
# months that nothing read (required_when, gate_profile_defaults, baseline_*,
# ...). A key with no reader is a promise the runtime never keeps. This test
# composes execution.yaml for every shipped stack and, for each key path the
# composer writes — top-level keys, `gates.*.<key>`, `gate_profiles.*.<key>` —
# demands a READER EXPRESSION somewhere under scripts/ outside tests/, the
# shipped templates and the writer library itself (lib/aid-init-execution-yaml.sh,
# whose own yq calls on the keys it writes or removes do not count).
#
# A reader expression is `.<key>`, `["<key>"]` or `'<key>'` on a non-comment
# line of a *.sh file, the third form only on a line that also invokes yq or
# jq — never a bare substring, so `description` or `required` in prose or in
# an error message does not count. A top-level key must be read at the START
# of a yq/jq program (`'.key`, `".key`, `| .key`) on a line that also names
# an execution.yaml source (`$execution_yaml`, `$_exec_yaml`,
# `.aid-o/config/execution.yaml`, ...: the substring `exec`), so `.command`
# inside `.gates[$g].command`, or a top-level `.command` read from a job file,
# does not vouch for a top-level execution.yaml key named `command`.
#
# HONEST LIMIT: this proves a reader expression exists, not that the value
# changes a decision, and not that the expression is applied to execution.yaml
# rather than to another file with the same key (e.g. `version`). The second
# half — value changes decision — is what Step 8's replay and the edge matrix
# cover for the keys that matter.
#
# Two fixtures prove the test is not vacuous: a dead key with an exotic name
# and a dead key named `command` (which has plenty of nested readers) both
# turn it red.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$PLUGIN_DIR}"
WRITER="${PLUGIN_DIR}/scripts/lib/aid-init-execution-yaml.sh"

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail+1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass+1)); }

for dep in jq yq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The scanned reader corpus: every *.sh under scripts/, minus tests and the writer.
mapfile -t CORPUS < <(find "${PLUGIN_DIR}/scripts" -name '*.sh' -not -path '*/tests/*' \
  -not -path "$WRITER" | sort)

# has_reader <key> <top|nested> — 0 when a reader expression exists.
has_reader() {
  local key="$1" scope="$2" re
  local k; k="$(printf '%s' "$key" | sed 's/[][\.*^$\/]/\\&/g')"
  if [[ "$scope" == top ]]; then
    # start of a program: '.key  ".key  (.key  | .key   (a preceding quote, paren or pipe)
    # (a backslash-escaped quote is an inner path segment, `.gates.\"x\".key`)
    re="(^|[^\\\\])(['\"(]|\\|[[:space:]]*)\\.${k}([^A-Za-z0-9_]|\$)|\\[\"${k}\"\\]"
  else
    re="\\.${k}([^A-Za-z0-9_]|\$)|\\[\"${k}\"\\]"
  fi
  local ctx='.'
  [[ "$scope" == top ]] && ctx='[Ee][Xx][Ee][Cc]'
  grep -hE "$re" "${CORPUS[@]}" 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -E "$ctx" | grep -q . && return 0
  grep -hE "'${k}'" "${CORPUS[@]}" 2>/dev/null | grep -vE '^[[:space:]]*#' | grep -E '\b(yq|jq)\b' | grep -q .
}

# check_file <execution.yaml> — prints each key path without a reader; 0 when none.
check_file() {
  local f="$1" j missing=0 k
  j="$(yq -o=json '.' "$f")"
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    has_reader "$k" top || { echo "    no reader for top-level key: ${k}"; missing=1; }
  done < <(jq -r 'keys_unsorted[]' <<<"$j")
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    has_reader "$k" nested || { echo "    no reader for gates.*.${k}"; missing=1; }
  done < <(jq -r '[.gates // {} | .[] | select(type == "object") | keys[]] | unique[]' <<<"$j")
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    has_reader "$k" nested || { echo "    no reader for gate_profiles.*.${k}"; missing=1; }
  done < <(jq -r '[.gate_profiles // {} | .[] | select(type == "object") | keys[]] | unique[]' <<<"$j")
  return $missing
}

echo "TEST: the composer's output (every shipped stack) has a reader for every key it writes"
mkdir -p "$WORK/proj"
# shellcheck disable=SC1090
source "$WRITER"
mapfile -t STACKS < <(ls "${PLUGIN_DIR}/defaults/execution-stacks" | sed 's/\.yaml$//')
if compose_execution_yaml "$WORK/proj" "$WORK/proj/execution.yaml" "${STACKS[@]}" >/dev/null 2>&1 \
   && check_file "$WORK/proj/execution.yaml"; then
  pass_msg "composed for [${STACKS[*]}]: every written key has a reader"
else
  fail_msg "a key the composer writes has no reader (listed above)"
fi

echo "TEST: non-vacuity — a dead key with an exotic name turns the check red"
cp "$WORK/proj/execution.yaml" "$WORK/exotic.yaml"
printf '\nzz_orphan_knob_p097: 1\n' >> "$WORK/exotic.yaml"
if check_file "$WORK/exotic.yaml" >"$WORK/exotic.out" 2>&1; then
  fail_msg "the exotic dead key was not reported"
elif grep -q 'top-level key: zz_orphan_knob_p097' "$WORK/exotic.out"; then
  pass_msg "zz_orphan_knob_p097 reported as unread"
else
  fail_msg "check went red for another reason: $(cat "$WORK/exotic.out")"
fi

echo "TEST: non-vacuity — a dead TOP-LEVEL key named 'command' turns the check red despite nested .command readers"
cp "$WORK/proj/execution.yaml" "$WORK/command.yaml"
printf '\ncommand: "true"\n' >> "$WORK/command.yaml"
if check_file "$WORK/command.yaml" >"$WORK/command.out" 2>&1; then
  fail_msg "the top-level dead key 'command' was not reported (a nested .command reader vouched for it)"
elif grep -q 'top-level key: command' "$WORK/command.out"; then
  pass_msg "top-level 'command' reported as unread"
else
  fail_msg "check went red for another reason: $(cat "$WORK/command.out")"
fi

echo "Results: ${pass}/$((pass+fail)) passed, ${fail} failed"
(( fail == 0 ))
