#!/usr/bin/env bats
# aid-tier: t0
# test-gates-measure.bats — WHY THIS FILE EXISTS: gates-measure.sh is the
# record every P097 removal cites, so its counting rules are pinned here over
# a synthetic fixture tree (never the real projects): three reports in one
# project, a status-less row counted as legacy_row, a re-run counted once,
# an unreadable report named, a project without evidence listed with zeros,
# and --as-of excluding a newer report.

setup() {
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  MEASURE="$PLUGIN_DIR/scripts/tests/gates-measure.sh"
  ROOT="$BATS_TEST_TMPDIR/projects"
  P="$ROOT/proj"
  mkdir -p "$P/.aid-o/config" "$ROOT/empty/.aid-o/config"
  git -C "$P" init -q && git -C "$P" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  SHA="$(git -C "$P" rev-parse HEAD)"
  cat >"$P/.aid-o/config/execution.yaml" <<'YAML'
gates:
  a: {command: "true", required: true, required_when: "*.py exists"}
  b: {command: "true", required: false}
gate_profiles:
  quick: {include: [a]}
YAML
  _report() { # dir run_id mtime_date sha gates_json
    mkdir -p "$1"
    jq -n --arg run "$2" --arg sha "$4" --argjson gates "$5" \
      '{run_id: $run, profile: "quick", profile_source: "cli_flag", overall: "pass", revision: {head_sha: $sha}, gates: $gates}' >"$1/gates_report.json"
    touch -d "$3" "$1/gates_report.json"
  }
  E="$P/.aid-o/work/evidence"
  _report "$E/E-1/R-1/gates" R-1 2026-09-10 "$SHA" '{"a":{"result":"pass","runtime_baseline":{"policy_result":"none"}},"b":{"result":"fail","reason":null},"_execution_ledger":{"path":"x","dispatched":0}}'
  _report "$E/E-2/R-2/gates" R-2 2026-09-12 "deadbeef" '{"a":{"result":"job_timeout","reason":"job_timeout"},"b":{"result":"profile_excluded","reason":"profile_excluded"}}'
  _report "$E/E-2/R-2.rerun/gates" R-2 2026-09-13 "$SHA" '{"a":{"result":"pass"},"b":{"result":"skip"}}'
  _report "$E/E-3/R-3/gates" R-3 2026-09-25 "$SHA" '{"a":{"result":"pass"},"b":{"result":"pass"}}'
  _report "$E/E-4/R-4/gates" R-4 2026-09-11 "$SHA" '{}'
  mkdir -p "$E/E-5/R-5/gates"; echo '{not json' >"$E/E-5/R-5/gates/gates_report.json"; touch -d 2026-09-11 "$E/E-5/R-5/gates/gates_report.json"
  mkdir -p "$E/E-6/R-6/gates"; echo '{}' >"$E/E-6/R-6/gates/gates-report.json"
}

run_measure() { run "$MEASURE" --projects-root "$ROOT" --since 30 --as-of "$1"; [ "$status" -eq 0 ]; OUT="$output"; }

@test "counts reports, runs (re-run once, newest) and rows by status; status-less row is legacy_row" {
  run_measure 2026-09-21
  [ "$(jq '.projects.proj.reports' <<<"$OUT")" -eq 4 ]
  [ "$(jq '.projects.proj.runs' <<<"$OUT")" -eq 3 ]
  [ "$(jq -c '.projects.proj.rows.by_status' <<<"$OUT")" = '{"fail":1,"legacy_row":1,"pass":2,"skip":1}' ]
  [ "$(jq -c '.projects.proj.rows.legacy_row_keys' <<<"$OUT")" = '{"dispatched,path":1}' ]
  [ "$(jq '.projects.proj.timeouts_hit' <<<"$OUT")" -eq 0 ]
  [ "$(jq -c '.projects.proj.profiles' <<<"$OUT")" = '[{"profile":"quick","profile_source":"cli_flag","runs":3}]' ]
  [ "$(jq -c '.projects.proj.runtime_baseline.policy_result' <<<"$OUT")" = '{"none":1}' ]
}

@test "unreadable report is named, empty gates listed, other spelling counted, config layers read" {
  run_measure 2026-09-21
  [ "$(jq -r '.projects.proj.unreadable[0]' <<<"$OUT")" = "$P/.aid-o/work/evidence/E-5/R-5/gates/gates_report.json" ]
  [ "$(jq -r '.projects.proj.empty_reports[0]' <<<"$OUT")" = "$P/.aid-o/work/evidence/E-4/R-4/gates/gates_report.json" ]
  [ "$(jq '.projects.proj.other_names' <<<"$OUT")" -eq 1 ]
  [ "$(jq -c '.projects.proj.config | [.gates, .gate_profiles, .required_when, .services]' <<<"$OUT")" = '[2,["quick"],["*.py exists"],0]' ]
  [ "$(jq '.totals.unreadable' <<<"$OUT")" -eq 1 ]
}

@test "project without evidence is listed with zeros" {
  run_measure 2026-09-21
  [ "$(jq -c '.projects.empty | [.reports, .runs, .rows.total]' <<<"$OUT")" = '[0,0,0]' ]
}

@test "--as-of includes the newer report once the window moves" {
  run_measure 2026-09-30
  [ "$(jq '.projects.proj.runs' <<<"$OUT")" -eq 4 ]
  [ "$(jq '.projects.proj.rows.by_status.pass' <<<"$OUT")" -eq 4 ]
}

@test "sample keeps only wan/acta runs whose sha resolves; sample_excluded counts the rest" {
  mv "$P" "$ROOT/wan"
  run_measure 2026-09-21
  [ "$(jq '.sample | length' <<<"$OUT")" -eq 3 ]
  [ "$(jq '.projects.wan.sample_excluded' <<<"$OUT")" -eq 0 ]
  [ "$(jq -c '.sample[] | select(.run_id == "R-1") | [.sha_source, .rows]' <<<"$OUT")" = '["report.revision.head_sha",{"a":"pass","b":"fail"}]' ]
  # The unresolvable sha is on the older R-2 report, which the re-run rule already drops;
  # make the newest one unresolvable to see the exclusion.
  jq '.revision.head_sha = "deadbeef"' "$ROOT/wan/.aid-o/work/evidence/E-2/R-2.rerun/gates/gates_report.json" >"$BATS_TEST_TMPDIR/r.json"
  cp "$BATS_TEST_TMPDIR/r.json" "$ROOT/wan/.aid-o/work/evidence/E-2/R-2.rerun/gates/gates_report.json"
  touch -d 2026-09-13 "$ROOT/wan/.aid-o/work/evidence/E-2/R-2.rerun/gates/gates_report.json"
  run_measure 2026-09-21
  [ "$(jq '.sample | length' <<<"$OUT")" -eq 2 ]
  [ "$(jq '.projects.wan.sample_excluded' <<<"$OUT")" -eq 1 ]
}

@test "usage errors exit 2" {
  run "$MEASURE" --projects-root "$ROOT" --as-of yesterday
  [ "$status" -eq 2 ]
  run "$MEASURE" --projects-root /nonexistent
  [ "$status" -eq 2 ]
}

@test "--line-count lists the runner and its libraries" {
  run "$MEASURE" --line-count
  [ "$status" -eq 0 ]
  [ "$(jq '.files["scripts/aid-run-gates.sh"] > 1000' <<<"$output")" = true ]
  [ "$(jq '.files["scripts/lib/aid-service.sh"] > 0' <<<"$output")" = true ]
}
