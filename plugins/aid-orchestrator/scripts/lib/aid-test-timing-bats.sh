#!/usr/bin/env bash
# aid-test-timing-bats.sh — P072 Step 11.
#
# Per-test timing for the Bats runner, version-gated and parsed from a RECORDED
# interface rather than from decorative terminal output.
#
# GROUNDED, NOT ASSUMED. `aid-test-adapter-contract.sh` already establishes the
# convention that a runner capability is checked against the installed version
# rather than presumed (its `adapter_supports_list_mode` records that Bats
# 1.8.2 has no `--list`). The same discipline applies here. Against the
# installed Bats 1.8.2, `bats --timing` emits TAP with the duration appended:
#
#   1..5
#   ok 1 passing in 67ms
#   not ok 2 failing in 65ms
#   ok 3 skipped in 12ms # skip not today
#   ok 4 name with in the middle in 16ms
#   ok 5 ends in 42ms in 19ms
#
# Three facts that shape the parser, each observed rather than guessed:
#   * a SKIP carries its duration BEFORE the `# skip` directive;
#   * a test NAME may contain " in " — so the duration is anchored at the end
#     of the line, never taken from the first match;
#   * a name may itself end in something like "42ms", so the LAST ` in NNNms`
#     is the duration. `ok 5 ends in 42ms in 19ms` is 19ms, not 42ms.
#
# Bats itself rejects duplicate test names within a file, so name collisions
# inside one suite cannot occur and the parser does not need to defend a case
# the runner makes impossible.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (aid-test-adapter-contract.sh header convention).

# bats_timing_version — echoes the installed Bats semantic version, or empty.
bats_timing_version() {
  command -v bats >/dev/null 2>&1 || return 1
  bats --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# bats_timing_supported [version] — 0 when this version exposes `--timing`.
#
# 1.2.0 is the first release carrying it. A version this cannot parse is
# treated as UNSUPPORTED rather than assumed-capable: a fabricated per-test
# figure from a flag that was never honoured is worse than no figure, because
# the profiler would then attribute cost with confidence it has not earned.
bats_timing_supported() {
  local v="${1:-}"
  [[ -n "$v" ]] || v="$(bats_timing_version)" || return 1
  [[ -n "$v" ]] || return 1
  local major minor
  major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major > 1 )) && return 0
  (( major == 1 && minor >= 2 ))
}

# bats_timing_can_time_argv <argv0> — 0 when `--timing` may be inserted after
# argv0, i.e. argv0 IS the Bats runner.
#
# The scar this closes (P081 Step 1): `--timing` is a flag of the RUNNER. For a
# shell-form command what actually runs is `bash -c '<string>'`, whose argv[0]
# is `bash`, and inserting the flag there produced `bash --timing -c …` — a
# per-case breakdown request that could only ever fail. Every caller that
# inserts the flag asks here first, so a second caller cannot re-derive it.
bats_timing_can_time_argv() {
  local argv0="${1:-}"
  [[ -n "$argv0" ]] || return 1
  [[ "${argv0##*/}" == "bats" ]]
}

# bats_timing_parse <tap_output> <run_unit_id>
#   Emits ONE JSON object describing the run:
#     {run_unit_id, bats_version, planned, cases:[…], truncated, parsed_lines}
#
#   Every case carries {ordinal, name, status, duration_ms}. `truncated` is
#   true when the TAP plan announced more cases than were seen — a run killed
#   at its deadline reports the prefix it really observed and says so, rather
#   than padding to look complete.
bats_timing_parse() {
  local out="$1" run_unit_id="${2:-}" version="${3:-}"
  [[ -n "$version" ]] || version="$(bats_timing_version || true)"

  local tmp; tmp="$(mktemp)" || return 1
  printf '%s\n' "$out" > "$tmp"

  local planned
  planned="$(grep -oE '^1\.\.([0-9]+)' "$tmp" | head -1 | cut -d. -f3)"
  [[ -n "$planned" ]] || planned=0

  local cases_file; cases_file="$(mktemp)" || { rm -f "$tmp"; return 1; }
  local line status ordinal rest name duration
  while IFS= read -r line; do
    case "$line" in
      "ok "*)      status="passed" ;;
      "not ok "*)  status="failed" ;;
      *)           continue ;;
    esac

    rest="${line#not ok }"; rest="${rest#ok }"
    ordinal="${rest%% *}"
    [[ "$ordinal" =~ ^[0-9]+$ ]] || continue
    rest="${rest#* }"

    # A skip directive follows the duration, so strip it FIRST — otherwise the
    # duration is no longer at the end of the line and the anchor fails.
    if [[ "$rest" == *" # skip"* ]]; then
      status="skipped"
      rest="${rest%% # skip*}"
    elif [[ "$rest" == *" # SKIP"* ]]; then
      status="skipped"
      rest="${rest%% # SKIP*}"
    fi

    # LAST ` in NNNms` at end of line is the duration. A name may contain
    # " in ", and may itself end in something like "42ms".
    if [[ "$rest" =~ ^(.*)\ in\ ([0-9]+)ms$ ]]; then
      name="${BASH_REMATCH[1]}"
      duration="${BASH_REMATCH[2]}"
    else
      # No timing on this line: the runner did not honour --timing, or this
      # is an untimed line. Recorded with a null duration rather than a zero,
      # which would read as "instantaneous".
      name="$rest"
      duration="null"
    fi

    jq -nc --argjson ord "$ordinal" --arg n "$name" --arg s "$status" \
           --argjson d "$duration" \
           '{ordinal:$ord, name:$n, status:$s, duration_ms:$d}' >> "$cases_file"
  done < "$tmp"

  local seen; seen="$(wc -l < "$cases_file" | tr -d ' ')"
  local truncated="false"
  [[ "$planned" -gt 0 && "$seen" -lt "$planned" ]] && truncated="true"

  jq -sc --arg id "$run_unit_id" --arg v "$version" \
         --argjson planned "$planned" --arg trunc "$truncated" \
    '{run_unit_id:$id, bats_version:$v, planned:$planned,
      truncated:($trunc == "true"), parsed_lines:length, cases:.}' "$cases_file"
  local rc=$?
  rm -f "$tmp" "$cases_file"
  return $rc
}

# bats_timing_capability_json — what this runner can and cannot report, as a
# record the profiler can cite. A capability claim belongs in the evidence,
# not in a comment.
bats_timing_capability_json() {
  local v; v="$(bats_timing_version || true)"
  local supported="false"
  bats_timing_supported "$v" && supported="true"
  jq -nc --arg v "$v" --arg s "$supported" \
    '{runner:"bats", version:$v, per_test_timing:($s == "true"),
      setup_teardown_attribution:false,
      note:"Bats reports one duration per test case. It does NOT separate setup, body and teardown, so a profile built on it attributes to a single body_plus_fixture bucket rather than splitting on a guess."}'
}
