#!/usr/bin/env bats
# test-aid-test-timing-bats.bats — P072 Step 11.
#
# The parser is tested against RECORDED output, not by invoking bats: a parser
# that can only be exercised by running the runner is a parser nobody can test
# against the shapes that matter (a truncated run, a skip, a name that looks
# like a duration).
#
# Every fixture below was captured from the installed Bats 1.8.2, not invented.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-timing-bats.sh"
}

teardown() { teardown_test_evidence_dir; }

# Recorded from: bats --timing on a 5-case file (Bats 1.8.2).
_recorded() {
  cat <<'TAP'
1..5
ok 1 passing in 67ms
not ok 2 failing in 65ms
# (in test file /tmp/x/e.bats, line 2)
#   `@test "failing" { sleep 0.05; false; }' failed
ok 3 skipped in 12ms # skip not today
ok 4 name with in the middle in 16ms
ok 5 ends in 42ms in 19ms
TAP
}

_parse() { bats_timing_parse "$(_recorded)" "bats:tests/e" "1.8.2"; }

@test "the installed bats version is detected" {
  run bats_timing_version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "the installed version supports --timing" {
  run bats_timing_supported
  [ "$status" -eq 0 ]
}

@test "a version below 1.2.0 is treated as unsupported, not assumed capable" {
  # A fabricated per-test figure from a flag that was never honoured is worse
  # than no figure: the profiler would attribute cost with confidence it has
  # not earned.
  run bats_timing_supported "1.1.0"
  [ "$status" -ne 0 ]
  run bats_timing_supported "1.2.0"
  [ "$status" -eq 0 ]
  run bats_timing_supported "2.0.0"
  [ "$status" -eq 0 ]
}

@test "an unparseable version string is unsupported rather than optimistic" {
  run bats_timing_supported "not-a-version"
  [ "$status" -ne 0 ]
}

@test "every case is parsed with its ordinal, name, status and duration" {
  run bash -c "$(declare -f _recorded); source '$PLUGIN_DIR/scripts/lib/aid-test-timing-bats.sh'; bats_timing_parse \"\$(_recorded)\" 'bats:tests/e' '1.8.2' | jq -c '[.cases[] | {ordinal, status, duration_ms}]'"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"ordinal":1,"status":"passed","duration_ms":67},{"ordinal":2,"status":"failed","duration_ms":65},{"ordinal":3,"status":"skipped","duration_ms":12},{"ordinal":4,"status":"passed","duration_ms":16},{"ordinal":5,"status":"passed","duration_ms":19}]' ]
}

@test "a SKIP carries its duration BEFORE the directive, and is still timed" {
  # `ok 3 skipped in 12ms # skip not today` — stripping the directive first is
  # what keeps the duration at the end of the line where the anchor expects it.
  local doc; doc="$(_parse)"
  [ "$(jq -r '.cases[2].status' <<<"$doc")" = "skipped" ]
  [ "$(jq -r '.cases[2].duration_ms' <<<"$doc")" = "12" ]
  [ "$(jq -r '.cases[2].name' <<<"$doc")" = "skipped" ]
}

@test "a name containing ' in ' does not have its duration taken from the name" {
  local doc; doc="$(_parse)"
  [ "$(jq -r '.cases[3].name' <<<"$doc")" = "name with in the middle" ]
  [ "$(jq -r '.cases[3].duration_ms' <<<"$doc")" = "16" ]
}

@test "a name ENDING in something like '42ms' yields the LAST duration, not the name's" {
  # `ok 5 ends in 42ms in 19ms` is 19ms. Taking the first match would report
  # the test name back as its runtime.
  local doc; doc="$(_parse)"
  [ "$(jq -r '.cases[4].name' <<<"$doc")" = "ends in 42ms" ]
  [ "$(jq -r '.cases[4].duration_ms' <<<"$doc")" = "19" ]
}

@test "a complete run is not marked truncated" {
  local doc; doc="$(_parse)"
  [ "$(jq -r '.truncated' <<<"$doc")" = "false" ]
  [ "$(jq -r '.planned' <<<"$doc")" = "5" ]
  [ "$(jq -r '.cases | length' <<<"$doc")" = "5" ]
}

@test "a run killed at its deadline reports the prefix it saw and says truncated" {
  # The honest shape of a profiling run that hit its budget: what was observed,
  # plus the fact that more was planned. Padding to look complete is the
  # failure this whole capability exists to remove.
  local partial doc
  partial=$'1..5\nok 1 passing in 67ms\nok 2 second in 20ms'
  doc="$(bats_timing_parse "$partial" "bats:tests/e" "1.8.2")"
  [ "$(jq -r '.truncated' <<<"$doc")" = "true" ]
  [ "$(jq -r '.planned' <<<"$doc")" = "5" ]
  [ "$(jq -r '.cases | length' <<<"$doc")" = "2" ]
}

@test "output with no TAP plan is not falsely marked truncated" {
  local doc; doc="$(bats_timing_parse $'ok 1 a in 5ms' "bats:x" "1.8.2")"
  [ "$(jq -r '.planned' <<<"$doc")" = "0" ]
  [ "$(jq -r '.truncated' <<<"$doc")" = "false" ]
}

@test "an untimed line records a NULL duration, never a zero" {
  # Zero would read as "instantaneous"; null reads as "not measured", which is
  # what actually happened.
  local doc; doc="$(bats_timing_parse $'1..1\nok 1 no timing here' "bats:x" "1.8.2")"
  [ "$(jq -r '.cases[0].duration_ms' <<<"$doc")" = "null" ]
  [ "$(jq -r '.cases[0].name' <<<"$doc")" = "no timing here" ]
}

@test "non-TAP noise between cases is ignored, not miscounted" {
  # The failing case's diagnostic lines start with '#'.
  local doc; doc="$(_parse)"
  [ "$(jq -r '.parsed_lines' <<<"$doc")" = "5" ]
}

@test "the emitted document records the runner version it was produced under" {
  local doc; doc="$(_parse)"
  [ "$(jq -r '.bats_version' <<<"$doc")" = "1.8.2" ]
  [ "$(jq -r '.run_unit_id' <<<"$doc")" = "bats:tests/e" ]
}

@test "the capability record states plainly what bats cannot report" {
  # Bats gives one duration per case and does NOT split setup/body/teardown.
  # Saying so is what stops a later profile from attributing to buckets it
  # cannot actually distinguish.
  run bats_timing_capability_json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.per_test_timing' <<<"$output")" = "true" ]
  [ "$(jq -r '.setup_teardown_attribution' <<<"$output")" = "false" ]
  [[ "$(jq -r '.note' <<<"$output")" == *"does NOT separate setup"* ]]
}

@test "LIVE: the recorded fixture still matches what the installed bats emits" {
  # The fixture is only trustworthy while it describes reality. If a bats
  # upgrade changes the timing format, this fails here rather than silently
  # producing null durations in a profile.
  local d="$TEST_TMPDIR/live"; mkdir -p "$d"
  {
    printf '@test "alpha" { true; }\n'
    printf '@test "beta" { true; }\n'
  } > "$d/live.bats"

  local out; out="$(bats --timing "$d/live.bats" 2>&1 || true)"
  [[ "$out" =~ ok\ 1\ alpha\ in\ [0-9]+ms ]]

  local doc; doc="$(bats_timing_parse "$out" "bats:live" "$(bats_timing_version)")"
  [ "$(jq -r '.cases | length' <<<"$doc")" = "2" ]
  [ "$(jq -r '.truncated' <<<"$doc")" = "false" ]
  [ "$(jq -r '[.cases[] | select(.duration_ms == null)] | length' <<<"$doc")" = "0" ]
}
