#!/usr/bin/env bats
# aid-tier: t0
#
# `required_when` was in all 14 gates of all 5 shipped stack templates, and in
# every project /aid-init ever created — and aid-run-gates.sh never read it.
# It read `required` alone, defaulting false, so a failing pytest/ruff/mypy/
# eslint/tsc wrote `result: fail` and left `overall: pass`. Two live consumers
# were in that state, both with configs byte-identical to what AID generated
# for them. (2026-09-02.)

setup() {
  PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${PLUGIN_ROOT}/scripts/lib/aid-gate-applicability.sh"
  RUNNER="${PLUGIN_ROOT}/scripts/aid-run-gates.sh"
  ROOT="${BATS_TEST_TMPDIR}/proj"
  mkdir -p "$ROOT/.aid-o/config" "$ROOT/src"
  git -C "$ROOT" init -q .
  YAML="$ROOT/.aid-o/config/execution.yaml"
}

_gate() {  # _gate <name> <command> <key: value>...
  local name="$1" cmd="$2"; shift 2
  printf '  %s:\n    command: "%s"\n' "$name" "$cmd" >> "$YAML"
  local kv; for kv in "$@"; do printf '    %s\n' "$kv" >> "$YAML"; done
}
_begin() { printf 'gates:\n' > "$YAML"; }
_req() { aid_gate_required "$YAML" "$1" "$ROOT" | tr '\t' ' '; }

# ─── precedence ────────────────────────────────────────────────────────────

@test "an explicit required: true wins over a required_when that does not match" {
  _begin; _gate g "exit 1" 'required: true' 'required_when: "*.nothing exists"'
  [ "$(_req g)" = "true explicit" ]
}

@test "an explicit required: false wins over a required_when that does match" {
  # yq's `//` is an alternative over FALSY values, so reading `.required // ""`
  # made an explicit `false` vanish — and this is the one line a project writes
  # when it means a gate to stay advisory on purpose.
  printf 'x = 1\n' > "$ROOT/src/a.py"
  _begin; _gate g "exit 1" 'required: false' 'required_when: "*.py exists"'
  [ "$(_req g)" = "false explicit" ]
}

@test "neither key keeps the pre-2026-09 default" {
  _begin; _gate g "exit 1"
  [ "$(_req g)" = "false legacy_default" ]
}

# ─── the grammar ───────────────────────────────────────────────────────────

@test "always makes a gate required regardless of the tree" {
  _begin; _gate g "exit 1" 'required_when: always'
  [ "$(_req g)" = "true required_when" ]
}

@test "a glob matches at any depth" {
  mkdir -p "$ROOT/lib/nested"; printf 'x = 1\n' > "$ROOT/lib/nested/a.py"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  [ "$(_req g)" = "true required_when" ]
}

@test "OR is satisfied by either side, and needs neither both" {
  printf 'x\n' > "$ROOT/src/a.tsx"
  _begin; _gate g "exit 1" 'required_when: "*.ts OR *.tsx exists"'
  [ "$(_req g)" = "true required_when" ]
}

@test "a clause with a slash also names a directory" {
  mkdir -p "$ROOT/frontend/e2e"; printf 'x\n' > "$ROOT/frontend/e2e/spec.ts"
  _begin; _gate g "exit 1" 'required_when: "frontend/e2e exists"'
  [ "$(_req g)" = "true required_when" ]
}

@test "nothing matching makes the gate not applicable, not required" {
  _begin; _gate g "exit 1" 'required_when: "*.rs exists"'
  [ "$(_req g)" = "false not_applicable" ]
}

@test "'always exists' asks for a FILE called always and is not the always keyword" {
  _begin; _gate g "exit 1" 'required_when: "always exists"'
  [ "$(_req g)" = "false not_applicable" ]
  printf 'x\n' > "$ROOT/always"
  [ "$(_req g)" = "true required_when" ]
}

# ─── what the tree offers ──────────────────────────────────────────────────

@test "an untracked but unignored file activates the gate" {
  printf 'x = 1\n' > "$ROOT/src/fresh.py"   # never committed
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  [ "$(_req g)" = "true required_when" ]
}

@test "an ignored dependency artifact does not activate it" {
  printf 'node_modules/\n' > "$ROOT/.gitignore"
  mkdir -p "$ROOT/node_modules"; printf 'x = 1\n' > "$ROOT/node_modules/dep.py"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  [ "$(_req g)" = "false not_applicable" ]
}

@test "evaluation is rooted at the project, not at the caller's cwd" {
  printf 'x = 1\n' > "$ROOT/src/a.py"
  mkdir -p "$ROOT/empty/deeper"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  local out
  out="$(cd "$ROOT/empty/deeper" && aid_gate_required "$YAML" g "$ROOT" | tr '\t' ' ')"
  [ "$out" = "true required_when" ]
}

# ─── malformed input is refused, never read as false ───────────────────────

@test "malformed expressions are refused with a reason, one shape at a time" {
  local expr
  for expr in '""' '"*.py"' '"*.py or *.ts exists"' '"*.py AND *.ts exists"' '"a b exists"'; do
    _begin; _gate g "exit 1" "required_when: ${expr}"
    run aid_gate_required "$YAML" g "$ROOT"
    [ "$status" -eq 2 ]
  done
}

@test "a non-string required_when is refused" {
  _begin
  printf '  g:\n    command: "exit 1"\n    required_when:\n      - always\n' >> "$YAML"
  run aid_gate_required "$YAML" g "$ROOT"
  [ "$status" -eq 2 ]
}

@test "a non-boolean required is refused" {
  _begin; _gate g "exit 1" 'required: "yes"'
  run aid_gate_required "$YAML" g "$ROOT"
  [ "$status" -eq 2 ]
}

# ─── end to end through the runner ─────────────────────────────────────────

# Run FROM the project, because that is where a real run happens — and
# because the applicability root and the gate commands must see the same
# tree. The runner derives both from the invoking checkout, so a test that
# ran from this repository would judge a fixture gate against THIS
# repository's files (which do contain *.py, and duly turned a
# "nothing to check" case into a blocking one).
_run_all() {
  mkdir -p "$ROOT/.aid-o/work/evidence/E-001-1_1/$1"
  run env -u AID_QUIET bash -c "cd '$ROOT' && bash '$RUNNER' run-all '$YAML' E-001-1_1 '$1' --report-file '$ROOT/report-$1.json'"
}

@test "an applicable gate that fails blocks the run" {
  printf 'x = 1\n' > "$ROOT/src/a.py"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  _run_all R-1
  [ "$status" -ne 0 ]
  [ "$(jq -r .overall "$ROOT/report-R-1.json")" = "fail" ]
  [ "$(jq -r '.gates.g.required' "$ROOT/report-R-1.json")" = "true" ]
  [ "$(jq -r '.gates.g.required_source' "$ROOT/report-R-1.json")" = "required_when" ]
}

@test "a gate with nothing to check does not block, even failing" {
  # The whole point of the key: a brand-new project gets pytest and mypy
  # written on day one, before any test or src/ exists. Blocking there would
  # turn 'there is nothing here yet' into 'you may not proceed'.
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  _run_all R-2
  [ "$status" -eq 0 ]
  [ "$(jq -r .overall "$ROOT/report-R-2.json")" = "pass" ]
  [ "$(jq -r '.gates.g.result' "$ROOT/report-R-2.json")" = "fail" ]
  [ "$(jq -r '.gates.g.required_source' "$ROOT/report-R-2.json")" = "not_applicable" ]
}

@test "a malformed expression refuses before any gate command runs" {
  local marker="${BATS_TEST_TMPDIR}/ran"
  _begin
  _gate a_gate "touch ${marker}" 'required: true'
  _gate b_gate "exit 0" 'required_when: "*.py or *.ts exists"'
  _run_all R-3
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
  [[ "$output" == *"required_when"* ]]
}

@test "the refusal names the clause, not just 'unreadable'" {
  # The reason lives in a variable the runner must not read through $(...):
  # a command substitution's subshell would take it along and leave the
  # project staring at a refusal with no cause.
  _begin; _gate g "exit 0" 'required_when: "*.py or *.ts exists"'
  _run_all R-4
  [[ "$output" == *"*.py or *.ts"* ]]
}

# ─── the cases the implementation review added ─────────────────────────────

@test "a malformed required_when is refused even when required: is present" {
  # Returning on sight of `required:` would leave a broken expression on an
  # explicitly advisory gate unvalidated forever — the one place nobody would
  # ever be told about it.
  _begin; _gate g "exit 1" 'required: false' 'required_when: "*.py or *.ts exists"'
  run aid_gate_required "$YAML" g "$ROOT"
  [ "$status" -eq 2 ]
}

@test "a quoted boolean is not a boolean" {
  # `yq -r` prints `true` for the boolean and for the string alike, so only the
  # tag can tell them apart.
  _begin; _gate g "exit 1" 'required: "true"'
  run aid_gate_required "$YAML" g "$ROOT"
  [ "$status" -eq 2 ]
  _begin; _gate g "exit 1" 'required: "false"'
  run aid_gate_required "$YAML" g "$ROOT"
  [ "$status" -eq 2 ]
}

@test "a filename containing a newline cannot invent a path" {
  # git ls-files is line-delimited by default; splitting its output on
  # newlines turns one such file into two paths that do not exist — which can
  # flip a gate to not-applicable and hand back a green run.
  printf 'x\n' > "$ROOT/src/we"$'\n'"ird.rs"
  _begin; _gate g "exit 1" 'required_when: "*.rs exists"'
  [ "$(_req g)" = "true required_when" ]

  # And the invented half must not satisfy a different glob.
  _begin; _gate h "exit 1" 'required_when: "ird.rs exists"'
  [ "$(_req h)" = "false not_applicable" ]
}

@test "applicability is a start-of-run snapshot: a gate that creates a file cannot wake a later one" {
  # The contract is deterministic-by-snapshot, and this is the case it costs:
  # `maker` writes late.py, and `checker` — already resolved before any gate
  # ran — stays non-applicable for this run. Stated here so the limit is a
  # measured behaviour rather than a comment nobody re-reads.
  _begin
  _gate maker "touch '$ROOT/src/late.py'" 'required: false'
  _gate checker "exit 1" 'required_when: "*.py exists"'
  _run_all R-7
  [ "$status" -eq 0 ]
  [ "$(jq -r .overall "$ROOT/report-R-7.json")" = "pass" ]
  [ "$(jq -r '.gates.checker.required_source' "$ROOT/report-R-7.json")" = "not_applicable" ]
  [ -f "$ROOT/src/late.py" ]
}

@test "each run takes its own snapshot" {
  # The library caches by root. Relying on that alone would let a SECOND
  # run_all_gates in the same shell and cwd answer from the first run's tree.
  # run_all_gates therefore takes the snapshot itself, every time.
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  _run_all R-8
  [ "$status" -eq 0 ]
  [ "$(jq -r '.gates.g.required_source' "$ROOT/report-R-8.json")" = "not_applicable" ]

  printf 'x = 1\n' > "$ROOT/src/appeared.py"
  _run_all R-9
  [ "$status" -ne 0 ]
  [ "$(jq -r '.gates.g.required_source' "$ROOT/report-R-9.json")" = "required_when" ]
}

@test "applicability follows the directory the gate commands run in" {
  # The runner resolves against $PWD, the same place run_gate's `bash -c`
  # executes. Judging against the whole repository while a command sees one
  # subdirectory would let a gate be required on files it cannot reach.
  printf 'x = 1\n' > "$ROOT/src/a.py"
  mkdir -p "$ROOT/other"; printf 'x\n' > "$ROOT/other/b.txt"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  local out
  out="$(cd "$ROOT/other" && aid_gate_snapshot_candidates "$PWD" && aid_gate_required "$YAML" g "$PWD" | tr '\t' ' ')"
  [ "$out" = "false not_applicable" ]
}

@test "a restored failing row blocks when required_when made the gate required" {
  # The restore path used to read `.required // false` — leaving exactly the
  # gates this change makes blocking non-blocking, on the branch that runs no
  # command and gets the least scrutiny.
  printf 'x = 1\n' > "$ROOT/src/a.py"
  _begin; _gate g "exit 1" 'required_when: "*.py exists"'
  _run_all R-5
  [ "$status" -ne 0 ]
  [ "$(jq -r '.gates.g.required' "$ROOT/report-R-5.json")" = "true" ]
}

@test "every row carries the requirement, including ones that never ran" {
  printf 'x = 1\n' > "$ROOT/src/a.py"
  _begin
  printf '  nocmd:\n    required_when: "*.py exists"\n' >> "$YAML"
  _run_all R-6
  [ "$(jq -r '.gates.nocmd.result' "$ROOT/report-R-6.json")" = "skip" ]
  [ "$(jq -r '.gates.nocmd.required' "$ROOT/report-R-6.json")" = "true" ]
  [ "$(jq -r '.gates.nocmd.required_source' "$ROOT/report-R-6.json")" = "required_when" ]
}
