#!/usr/bin/env bash
# aid-test-parallel-pilot.sh — P072 Step 15.
#
# Runs one candidate lane twice — serially, then concurrently — in a disposable
# clone, and reports whether concurrency changed anything. It PROPOSES. It never
# writes the catalog, `execution.yaml`, or a scheduler mode.
#
# WHAT IS COMPARED
#   The exit code and terminal job state of both sides, AND the per-case result
#   sequence position by position — not names used as a lookup key. An
#   adversarial review built the case that breaks the weaker forms: two suites
#   each containing a case called "same", one of which fails only under
#   concurrency. Matching by name found the passing one, the verdict read
#   `match`, the exit code was never examined at all, and a lane whose parallel
#   run had FAILED was proposed.
#
# WHY A FAILURE IS NEVER RETRIED
#   Retrying until green is how a flaky lane gets promoted. One failing
#   repetition ends the pilot with `promotion: refused` and the index that
#   failed. The receipt records the attempt, because an absence would read as
#   "never tried" rather than "tried and refused".
#
# WHAT IT REFUSES BEFORE RUNNING ANYTHING
#   * the live checkout, and any linked worktree sharing its object store —
#     same rule and same exit code as the profiler;
#   * a command the audit's allowlist does not approve;
#   * a membership that is not entirely in the approved catalog.
#
# EVERY RUN STARTS FROM AN IDENTICAL, FRESH SNAPSHOT
#   Serial-then-parallel in one working tree lets the serial side WARM state
#   that the parallel side then finds ready, so a cold race disappears exactly
#   when it is being looked for. Each side of each repetition therefore runs in
#   its own copy of the reference root.
#
# LEAK CHECKS, AFTER EVERY RUN
#   A content digest of the whole snapshot — including files git ignores — is
#   compared against the reference. `git status` alone missed both an ignored
#   marker file and any change to a file that was already present. The
#   snapshot's parent is inventoried too.
#
#   What that still does NOT cover: a write to an arbitrary absolute path
#   elsewhere on the machine. Nothing here can watch the whole filesystem, so
#   that gap is covered by the resource map (Step 14), which reports such a
#   write as `shared` and keeps the unit out of a lane before a pilot is ever
#   run.
#
# Exit codes: 0 ok (see `promotion` for the verdict) · 2 usage · 3 catalog
#             · 10 non-disposable root · 11 command not allowlisted

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-audit-command-allowlist.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-command-allowlist.sh"
# shellcheck source=lib/aid-test-audit-config.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-config.sh"

_die() { echo "aid-test-parallel-pilot.sh: $2" >&2; exit "$1"; }

lane_id="" catalog_path="" execution_yaml="" output_dir="" audit_id=""
target_root="" project_root="" workers=2 repeat=1 deadline_s=1800
declare -a membership=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lane-id)       [[ $# -ge 2 ]] || _die 2 "--lane-id requires a value"; lane_id="$2"; shift 2 ;;
    --unit)          [[ $# -ge 2 ]] || _die 2 "--unit requires a value"; membership+=("$2"); shift 2 ;;
    --catalog)       [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --execution-yaml)[[ $# -ge 2 ]] || _die 2 "--execution-yaml requires a value"; execution_yaml="$2"; shift 2 ;;
    --output-dir)    [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --audit-id)      [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --target-root)   [[ $# -ge 2 ]] || _die 2 "--target-root requires a value"; target_root="$2"; shift 2 ;;
    --project-root)  [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --workers)       [[ $# -ge 2 ]] || _die 2 "--workers requires a value"; workers="$2"; shift 2 ;;
    --repeat)        [[ $# -ge 2 ]] || _die 2 "--repeat requires a value"; repeat="$2"; shift 2 ;;
    --deadline)      [[ $# -ge 2 ]] || _die 2 "--deadline requires a value"; deadline_s="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$lane_id" ]] || _die 2 "--lane-id is required"
[[ "${#membership[@]}" -gt 0 ]] || _die 2 "at least one --unit is required"
[[ -n "$catalog_path" && -f "$catalog_path" ]] || _die 2 "--catalog is required and must exist"
[[ -n "$output_dir" ]] || _die 2 "--output-dir is required"
[[ -n "$target_root" && -d "$target_root" ]] || _die 2 "--target-root is required and must exist"
[[ -n "$project_root" && -d "$project_root" ]] || _die 2 "--project-root is required and must exist"
[[ "$workers" =~ ^[0-9]+$ && "$workers" -ge 2 ]] || _die 2 "--workers must be an integer >= 2 (one worker is not concurrency)"
[[ "$repeat"  =~ ^[0-9]+$ && "$repeat"  -ge 1 ]] || _die 2 "--repeat must be a positive integer"
[[ "$deadline_s" =~ ^[0-9]+$ && "$deadline_s" -ge 1 ]] || _die 2 "--deadline must be a positive integer"

# ─── The disposable-root refusal ────────────────────────────────────────────
# Same rule and same exit code as the profiler: a pilot deliberately runs the
# same tests twice, concurrently, and checks afterwards whether anything leaked.
# Doing that in the checkout being audited is how a "measurement" becomes an
# outage.
_canon() { (cd "$1" && pwd -P); }
target_canon="$(_canon "$target_root")"
project_canon="$(_canon "$project_root")"
if [[ "$target_canon" == "$project_canon" ]]; then
  _die 10 "refusing to pilot against the live checkout ('$target_canon' is --project-root) — use a disposable clone"
fi
if git -C "$target_canon" rev-parse --git-common-dir >/dev/null 2>&1; then
  _common="$(cd "$target_canon" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  _project_common="$(cd "$project_canon" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)"
  if [[ "$_common" == "$_project_common" ]]; then
    _die 10 "refusing to pilot in a linked worktree of --project-root (shared git object store at '$_common') — a mutation there is not contained"
  fi
fi

# The disposable root must be a copy of the tree being audited, at the same
# revision. Without this the pilot happily measures an unrelated or stale
# repository that happens to contain the same paths, and reports the result as
# evidence about the audited one.
# `git rev-parse HEAD` in a repository with no commits prints "HEAD" on stdout
# AND fails, so `cmd || echo fallback` yields two lines. Capture first, decide
# after.
_head_of() { local o; if o="$(git -C "$1" rev-parse HEAD 2>/dev/null)"; then printf '%s' "$o"; else printf 'no-head'; fi; }
_tree_of() { local o; if o="$(git -C "$1" rev-parse "HEAD^{tree}" 2>/dev/null)"; then printf '%s' "$o"; else printf 'no-tree'; fi; }
project_head="$(_head_of "$project_canon")"; target_head="$(_head_of "$target_canon")"
project_tree="$(_tree_of "$project_canon")"; target_tree="$(_tree_of "$target_canon")"
if [[ "$project_head" != "no-head" || "$target_head" != "no-head" ]]; then
  if [[ "$project_head" != "$target_head" || "$project_tree" != "$target_tree" ]]; then
    _die 10 "the disposable root is not a snapshot of the audited tree (project HEAD ${project_head:0:12}/tree ${project_tree:0:12}, target HEAD ${target_head:0:12}/tree ${target_tree:0:12}) — evidence gathered from a different revision is not evidence about this one"
  fi
fi

[[ -n "$execution_yaml" ]] || execution_yaml="${project_root%/}/.aid-o/config/execution.yaml"
noise_ms="$(test_audit_decision_key pilot_noise_ms "$project_root" 2>/dev/null || echo 2000)"
[[ "$noise_ms" =~ ^[0-9]+$ ]] || noise_ms=2000

# ─── Can this runner actually run things concurrently? ──────────────────────
#
# Bats delegates `--jobs` to GNU parallel. Without it the flag degrades and the
# "parallel" run is serial — at which point a `safe_not_worthwhile` verdict
# would mean "concurrency was never attempted" while reading as "concurrency
# does not pay". That is precisely the silent downgrade this plan exists to
# remove, so it is detected and recorded rather than discovered later.
parallelism_available="true"
parallelism_note="bats --jobs delegates to GNU parallel, which is present"
if ! command -v parallel >/dev/null 2>&1; then
  parallelism_available="false"
  parallelism_note="GNU parallel is not installed, so bats --jobs cannot run cases concurrently — no comparison made here would be a comparison of concurrency"
fi

mkdir -p "${output_dir%/}/pilots"
receipt_path="${output_dir%/}/pilots/$(printf '%s' "$lane_id" | tr '/:' '__').json"

# ─── Membership resolves to catalog commands, never to invented ones ────────
catalog_json="$(yq -o=json '.' "$catalog_path")" || _die 3 "could not read the catalog"

declare -a bats_files=()
for unit in "${membership[@]}"; do
  u="$(jq -c --arg id "$unit" '.run_units[] | select(.run_unit_id == $id)' <<<"$catalog_json")"
  [[ -n "$u" ]] || _die 3 "run unit '$unit' is not in the catalog — a pilot never invents a command"
  [[ "$(jq -r '.runner' <<<"$u")" == "bats" ]] \
    || _die 2 "run unit '$unit' is not a bats unit — this pilot compares a bats pool, and mixing runners would compare two different things"
  cmd="$(jq -c '.command' <<<"$u")"
  aid_test_audit_check_allowed "full" "$cmd" "$execution_yaml" "$catalog_path" 2>/dev/null \
    || _die 11 "the command for '$unit' is not in the approved allowlist — refused before any process started"
  # The pool this pilot runs is `bats --timing [--jobs N] <files...>`, which is
  # a composition of the approved per-unit commands. That composition is only
  # faithful when each approved command is exactly `bats <one .bats file>`.
  # Taking the first .bats argument out of a longer approved command and
  # dropping the rest would pilot something the project does not run — the
  # dropped file could be the one that races.
  n_argv="$(jq -r '(.command.argv // []) | length' <<<"$u")"
  argv0="$(jq -r '(.command.argv // [])[0] // ""' <<<"$u")"
  f="$(jq -r '(.command.argv // [])[1] // ""' <<<"$u")"
  if [[ "$n_argv" -ne 2 || "$argv0" != "bats" || "$f" != *.bats ]]; then
    _die 2 "run unit '$unit' has approved command $(jq -c '.command.argv' <<<"$u"), which this pilot cannot represent exactly — it composes a pool only from units whose approved command is exactly [bats, <file>.bats], and refuses rather than piloting a different command than the project runs"
  fi
  # Fail-closed path validation, matching the lane runner's own rules.
  [[ "$f" != -* ]] || _die 2 "refusing a path that begins with '-': $f"
  case "$f" in *..*) _die 2 "refusing a path containing '..': $f" ;; esac
  [[ -f "${target_canon}/${f}" ]] || _die 3 "'$f' does not exist in the disposable root"
  bats_files+=("$f")
done

# Sorted membership, so a lane's identity does not depend on argument order.
mapfile -t membership < <(printf '%s\n' "${membership[@]}" | sort)
membership_sha="$(printf '%s\0' "${membership[@]}" | sha256sum | cut -d' ' -f1)"

# ─── Running one side ───────────────────────────────────────────────────────
#
# Through aid-job.sh, like every other supervised command here: process-group
# ownership, a durable terminal record, and a deadline that cannot be outlived.
jobs_dir="${output_dir%/}/pilot-jobs"
mkdir -p "$jobs_dir"
job_seq=0
# Unique per invocation: aid-job.sh refuses an id that already exists, so a
# second pilot of the same lane into the same output directory would fail to
# start rather than produce a second receipt.
job_run_tag="$$-${RANDOM}"

snap_root="${output_dir%/}/pilot-snapshots"
mkdir -p "$snap_root"

# A content digest of a tree, ignoring only git's own object store. Everything
# else counts, including files git ignores: an ignored marker file is exactly
# how one run warms state for the next, and `git status` cannot see it.
_tree_digest() {
  ( cd "$1" && find . -path ./.git -prune -o -type f -print0 2>/dev/null \
      | sort -z | xargs -0 -r sha256sum 2>/dev/null | sort )
}

reference_digest="$(_tree_digest "$target_canon")"

_parent_inventory() {
  ( cd "$(dirname "$1")" && ls -A1 2>/dev/null | sort )
}

# _run_side <label> <parallel:0|1> -> echoes a run object
#
# Every side runs in its OWN fresh copy of the reference root. Sharing one tree
# between the serial and parallel sides is what let a serial warm-up hide a
# cold concurrency race: the parallel run found the state already built and
# never took the path that races.
_run_side() {
  local label="$1" par="$2"
  job_seq=$(( job_seq + 1 ))
  local jid="pilot-${job_run_tag}-${job_seq}-${label}"
  local snap="${snap_root}/${job_run_tag}-${job_seq}-${label}"

  rm -rf "$snap"
  cp -a "$target_canon" "$snap"

  local before after escaped
  before="$(_parent_inventory "$snap")"

  local t0 t1
  t0=$(( $(date +%s%N) / 1000000 ))

  local -a argv=(bats --timing)
  [[ "$par" -eq 1 ]] && argv+=(--jobs "$workers")
  argv+=("${bats_files[@]}")

  ( cd "$snap" && bash "${SCRIPT_DIR}/aid-job.sh" run \
      --jobs-dir "$jobs_dir" --id "$jid" --label "pilot:${lane_id}:${label}" \
      --repo "$snap" --deadline "$deadline_s" --expect-p95 "$deadline_s" \
      -- "${argv[@]}" ) >/dev/null 2>&1 \
    || _die 1 "could not start the ${label} run through aid-job.sh"

  local collect="" rc=3 waited=0
  while (( waited <= deadline_s + 60 )); do
    set +e
    collect="$(bash "${SCRIPT_DIR}/aid-job.sh" collect --jobs-dir "$jobs_dir" --id "$jid" 2>/dev/null)"
    rc=$?
    set -e
    [[ "$rc" -ne 3 ]] && break
    sleep 2; waited=$(( waited + 2 ))
  done
  t1=$(( $(date +%s%N) / 1000000 ))

  local state exit_code
  state="$(jq -r '.state // "lost"' <<<"${collect:-null}" 2>/dev/null || echo lost)"
  exit_code="$(jq -r '.exit_code // 1' <<<"${collect:-null}" 2>/dev/null || echo 1)"
  [[ "$exit_code" =~ ^-?[0-9]+$ ]] || exit_code=1

  # Per-case results in TAP order. Order is preserved because the comparison
  # is positional: two cases sharing a name are two facts, not one.
  local results
  results="$(awk '
    /^(ok|not ok) / {
      st = ($0 ~ /^not ok /) ? "failed" : "passed"
      if ($0 ~ / # skip/) st = "skipped"
      line = $0
      sub(/^(not )?ok +[0-9]+ +/, "", line)
      sub(/ # skip.*$/, "", line)
      sub(/ in [0-9]+ms$/, "", line)
      gsub(/\\/, "\\\\", line); gsub(/"/, "\\\"", line)
      printf "%s{\"name\":\"%s\",\"status\":\"%s\"}", (n++ ? "," : ""), line, st
    }
  ' "${jobs_dir}/${jid}/stdout.log" 2>/dev/null)"
  results="[${results}]"

  # What changed in the snapshot, against the reference every side starts from.
  # This sees ignored files and edits to files that were already there — both
  # of which `git status --short` misses.
  local after_digest changed
  after_digest="$(_tree_digest "$snap")"
  # `diff` exits 1 when it finds differences, and under `pipefail` that took
  # down the whole pilot — the leak detector killing the run it was inspecting.
  # Differences are the expected outcome here, so the status is not a failure.
  local raw_changes
  raw_changes="$( { diff <(printf '%s\n' "$reference_digest") <(printf '%s\n' "$after_digest") || true; } \
                   | sed -n 's/^[<>] *//p' | awk '{ $1=""; sub(/^ +/, ""); print }' | sort -u )"
  changed="$(printf '%s' "$raw_changes" | jq -Rsc 'split("\n") | map(select(length > 0))')"

  after="$(_parent_inventory "$snap")"
  escaped="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
              | grep -v "^$(basename "$snap")$" || true)"
  escaped="$(printf '%s' "$escaped" | jq -Rsc 'split("\n") | map(select(length > 0))')"

  rm -rf "$snap"

  jq -nc --argjson d "$(( t1 - t0 ))" --argjson rc "$exit_code" --arg st "$state" \
    --argjson res "$results" --argjson dirty "$changed" --argjson esc "$escaped" \
    '{duration_ms:$d, exit_code:$rc, job_state:$st, results:$res,
      dirty_paths:$dirty, escaped_paths:$esc}'
}

# ─── Repetitions ────────────────────────────────────────────────────────────
reps_file="$(mktemp)"; : > "$reps_file"
trap 'rm -f "$reps_file"' EXIT

promotion="proposed"
reason=""
failing_rep="null"
benefit="null"
worst_serial=0
worst_parallel=0

for (( i = 1; i <= repeat; i++ )); do
  serial="$(_run_side "serial-$i" 0)"
  parallel="$(_run_side "parallel-$i" 1)"

  diffs="$(jq -nc --argjson s "$serial" --argjson p "$parallel" '
    [ # A run that did not finish cleanly is a refusal in its own right. The
      # first version compared only case results, so a parallel run that
      # exited non-zero could still be reported as a match.
      ( if $s.exit_code != 0 then "the serial run exited " + ($s.exit_code|tostring) else empty end ),
      ( if $p.exit_code != 0 then "the concurrent run exited " + ($p.exit_code|tostring) else empty end ),
      ( if $s.job_state != "terminal_pass" then "the serial job ended in state " + $s.job_state else empty end ),
      ( if $p.job_state != "terminal_pass" then "the concurrent job ended in state " + $p.job_state else empty end ),

      ( if ($s.results | length) != ($p.results | length)
        then "case count differs: serial " + (($s.results|length)|tostring)
             + ", concurrent " + (($p.results|length)|tostring)
        else empty end ),

      # Positional, not by name. Two cases sharing a name are two facts; using
      # the name as a lookup key found the passing one and hid the failing one.
      ( [ range(0; ([($s.results|length), ($p.results|length)] | min)) as $i
          | ($s.results[$i]) as $a | ($p.results[$i]) as $b
          | select($a.name != $b.name or $a.status != $b.status)
          | "position " + (($i+1)|tostring) + ": serial \"" + $a.name + "\" " + $a.status
            + ", concurrent \"" + $b.name + "\" " + $b.status ][] ),

      ( if ($s.dirty_paths | length) > 0
        then "the serial run changed its snapshot: " + ($s.dirty_paths | join(", "))
        else empty end ),
      ( if ($p.dirty_paths | length) > 0
        then "the concurrent run changed its snapshot: " + ($p.dirty_paths | join(", "))
        else empty end ),
      ( if ($s.escaped_paths | length) > 0
        then "the serial run wrote outside its snapshot: " + ($s.escaped_paths | join(", "))
        else empty end ),
      ( if ($p.escaped_paths | length) > 0
        then "the concurrent run wrote outside its snapshot: " + ($p.escaped_paths | join(", "))
        else empty end ) ]')"

  n_diff="$(jq 'length' <<<"$diffs")"
  verdict="match"; [[ "$n_diff" -gt 0 ]] && verdict="mismatch"

  jq -nc --argjson i "$i" --argjson s "$serial" --argjson p "$parallel" \
    --arg v "$verdict" --argjson d "$diffs" \
    '{index:$i, serial:$s, parallel:$p, verdict:$v, differences:$d}' >> "$reps_file"

  sd="$(jq -r '.duration_ms' <<<"$serial")"; pd="$(jq -r '.duration_ms' <<<"$parallel")"
  [[ "$sd" -gt "$worst_serial" ]] && worst_serial="$sd"
  [[ "$pd" -gt "$worst_parallel" ]] && worst_parallel="$pd"

  if [[ "$verdict" == "mismatch" ]]; then
    # No retry. Failure keeps units serial; retrying until green is how a
    # flaky lane gets promoted.
    promotion="refused"
    failing_rep="$i"
    reason="repetition ${i} of ${repeat} differed between the serial and concurrent runs: $(jq -r 'join("; ")' <<<"$diffs")"
    break
  fi
done

if [[ "$parallelism_available" != "true" ]]; then
  # Refused, not `safe_not_worthwhile`: nothing was tested concurrently, so
  # there is no safety finding here at all.
  promotion="refused"
  failing_rep=1
  reason="$parallelism_note"
elif [[ "$promotion" != "refused" ]]; then
  benefit=$(( worst_serial - worst_parallel ))
  if [[ "${#membership[@]}" -eq 1 ]]; then
    # Concurrency cannot help a single unit; recording the measured equality is
    # more useful than proposing a lane of one.
    promotion="safe_not_worthwhile"
    reason="a lane of one unit: nothing to run concurrently, and the measured difference (${benefit}ms) is an artefact of running the same file twice"
  elif [[ "$benefit" -lt "$noise_ms" ]]; then
    promotion="safe_not_worthwhile"
    reason="every repetition matched, so the lane is safe, but the measured benefit of ${benefit}ms is within the ${noise_ms}ms noise threshold — not worth the concurrency"
  else
    reason="all ${repeat} repetition(s) matched per case, the clone stayed clean, and the concurrent run was ${benefit}ms faster (serial ${worst_serial}ms vs parallel ${worst_parallel}ms at ${workers} workers)"
  fi
fi

reps_json="$(jq -sc '.' "$reps_file")"

# A last check before the receipt is written: a proposal must carry as many
# matching repetitions as were asked for. The schema enforces this too, but a
# producer that can emit an artifact its own reader rejects is a producer that
# will be worked around.
if [[ "$promotion" == "proposed" ]]; then
  n_reps="$(jq 'length' <<<"$reps_json")"
  if [[ "$n_reps" -ne "$repeat" ]]; then
    promotion="refused"; failing_rep="$(( n_reps + 1 ))"
    reason="only ${n_reps} of ${repeat} repetitions completed — a proposal must rest on every repetition that was asked for"
  fi
fi

jq -nc \
  --arg lane "$lane_id" --arg root "$target_canon" --arg aid "$audit_id" \
  --argjson mem "$(printf '%s\n' "${membership[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --arg msha "$membership_sha" \
  --argjson w "$workers" --argjson r "$repeat" \
  --arg promo "$promotion" --arg why "$reason" \
  --argjson reps "$reps_json" \
  --argjson benefit "$benefit" --argjson noise "$noise_ms" \
  --argjson failing "$failing_rep" \
  --argjson paravail "$([[ "$parallelism_available" == "true" ]] && echo true || echo false)" \
  --arg paranote "$parallelism_note" \
  '{schema_version:"aid-test-parallel-pilot-v1", lane_id:$lane,
    audit_id:(if $aid == "" then null else $aid end),
    target_root:$root, membership:$mem, membership_sha256:$msha,
    workers:$w, repeat:$r, promotion:$promo, reason:$why,
    benefit_ms:$benefit, noise_threshold_ms:$noise,
    failing_repetition:$failing, repetitions:$reps,
    parallelism: {available:$paravail, note:$paranote}}' \
  > "$receipt_path"

printf '%s\n' "$receipt_path"
