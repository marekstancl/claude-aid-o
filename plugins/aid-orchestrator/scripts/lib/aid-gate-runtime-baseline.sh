#!/usr/bin/env bash
# =============================================================================
# aid-gate-runtime-baseline.sh — Gate runtime baseline library (P063 EPIC,
# "Gate Runtime Baselines", Step 1/4).
#
# WHY: AID runs gates with static, human-guessed `timeout_seconds` values that
# never update as reality diverges (see .aid-o/plans/P063-gate-runtime-baselines.md
# Stakeholder Brief — `bats_all` and `shell_pipeline_smoke` both drifted badly
# from their configured timeouts for months before anyone traced it by hand).
# This library owns ALL baseline-file read/write/derive logic — every other
# consumer (the `aid-run-gates.sh` integration hook, the repeated-timeout
# policy check, the CLI) calls into it rather than re-deriving parsing/
# percentile logic independently.
#
# ── SCOPE (this file only) ──────────────────────────────────────────────────
# This is Step 1 of 4. It implements the full schema, percentile formula,
# exit-code-2 exclusion contract (caller-side — see below), concurrency
# (flock + atomic tmp-file + validate + mv), and sourceable-safe conventions.
# It does NOT wire itself into aid-run-gates.sh (Step 2), does NOT implement
# the repeated-timeout FSM precondition (Step 3), and does NOT ship a CLI
# (Step 4 — `aid-gate-runtime-report.sh`). It also does NOT implement the
# `.git/info/exclude` gitignore-backfill helper (Step 2's job) — see the
# `# TODO(Step 2)` comment at its call site inside gate_baseline_update below.
#
# ── BASELINE FILE ────────────────────────────────────────────────────────────
# Default path: .aid-o/metrics/gate-runtime-baselines.yaml (relative to the
# CURRENT WORKING DIRECTORY at call time — matches aid-run-gates.sh/aid-fsm.sh's
# own bare-CWD project-root convention, since this library is sourced directly
# into those scripts' shell, not invoked with an explicit project-root flag).
# Override via AID_GATE_BASELINE_FILE (used by this file's own bats suite to
# point at an isolated per-test tmp file without requiring a git checkout).
# Lock sidecar: "<baseline_file>.lock" (matches aid-emit-dispatch.sh's
# lock-on-sidecar precedent, NOT the data file itself — see that file's own
# H11 rationale: locking the data file itself races against the atomic mv
# that rotates its inode on every write).
#
# Schema (see plan's Architecture section for the authoritative version):
#   gates:
#     <gate_name>:
#       command_fingerprint, command_template, last_resolved_command,
#       samples_count, non_censored_samples_count, recent_samples[] (FIFO,
#       max 20, newest last: duration_ms, exit_code, timeout_seconds,
#       censored, recorded_at), p50_ms, p90_ms, p95_ms, max_ms,
#       last_duration_ms, last_exit_code, last_attempt_result, policy_result,
#       last_timeout_seconds, timeout_recommended_seconds, run_mode_recommended,
#       retryable, operator_action, last_updated, series_reset_at
#
# `gate_name` (NOT a hash) is the top-level lookup key — a fingerprint cannot
# be reversed back into a lookup key, and `gate_name` is the durable identity
# every caller already has on hand (the loop variable in aid-run-gates.sh's
# per-gate loop). `command_fingerprint` lives INSIDE each entry purely as the
# series-reset comparison value.
#
# Percentile formula (nearest-rank, precise): for percentile P in {50,90,95}
# over the non_censored_samples_count-sized, ascending-sorted sample set of
# size N: index = ceil(P/100 * N) - 1, 0-indexed, clamped to [0, N-1].
# max_ms is simply the largest non-censored sample. Implemented in jq (see
# `nearest_rank` in the update filter below) — N is always small (<=20), so
# jq's double-precision arithmetic is exact for every P/N combination this
# library ever computes.
#
# ── INJECTION SAFETY (design note — resolves the plan's "yq injection
# safety" requirement via a DIFFERENT, equally-safe mechanism) ───────────────
# The plan's Architecture section names the env-var + `strenv()` binding
# pattern (aid-plan-close-check.sh:260-267) for text values written into
# `yq -i` expressions with gate_name/command_template/etc. interpolated into
# the expression STRING. This library never does that: every read and write
# goes through a "whole document as JSON" round-trip — `yq -o=json '.' <file>`
# to read, arbitrary manipulation via jq's `--arg`/`--argjson` value binding
# (never raw string interpolation into a jq or yq PROGRAM, exactly the
# pattern already proven safe at aid-emit-dispatch.sh's `jq -nc --arg`
# pending-ledger construction), then `yq -p=json -o=yaml '.' <<<"$doc"` to
# serialize back to YAML for the atomic write. Because no gate_name/
# command_template/resolved_command value is EVER concatenated into a yq or
# jq EXPRESSION string (only ever bound as a `--arg`/`--argjson` VALUE), there
# is no yq-expression-injection surface here to begin with — `strenv()` would
# have nothing to protect that `--arg` binding doesn't already protect.
#
# ── CONCURRENCY / ATOMIC WRITES ──────────────────────────────────────────────
# gate_baseline_update / gate_baseline_mark_policy_block (the only two
# writers):
#   1. flock -w 5 (5s wait, fail OPEN — never block the real gate result on a
#      metrics write) on the sidecar lock file.
#   2. Read the current file; if `yq -e .` fails (malformed), preserve it as
#      `<file>.corrupt.<unix-ts>` and treat as absent (fresh series) — never
#      silently discard.
#   3. Apply the update to an in-memory JSON copy.
#   4. Write to `<file>.tmp.$$`, validate with `yq -e .`, atomically `mv` over
#      the real path.
#   5. Release the lock (subshell + fd-per-lockfile scope exit — matches
#      aid-emit-dispatch.sh:136-139).
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` (matches aid-gate-profile.sh:142-146,
# aid-cache-preflight.sh:54-56, aid-delivery-profile.sh:33-34,
# aid-review-signals.sh:14-16). `aid-run-gates.sh` sources libraries directly
# into its own `set -euo pipefail` shell — an unguarded non-zero return here
# would abort its entire run_all_gates() per-gate loop. Every fallible call
# (every yq/jq invocation) is individually guarded; every public function
# returns 0 even on internal failure (fail open, warn to stderr).
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced (the real, intended usage — matches aid-gate-profile.sh):
#     source .../lib/aid-gate-runtime-baseline.sh
#     gate_baseline_update "$gate_name" "$command_template" "$resolved_command" \
#       "$exit_code" "$duration_ms" "$timeout_seconds"
#   Standalone (debugging / bats convenience — mirrors aid-gate-profile.sh's
#   own dispatch idiom):
#     bash aid-gate-runtime-baseline.sh fingerprint <gate_name> <command_template>
#     bash aid-gate-runtime-baseline.sh update <gate_name> <command_template> \
#       <resolved_command> <exit_code> <duration_ms> <timeout_seconds>
#     bash aid-gate-runtime-baseline.sh policy-check <gate_name> <current_timeout_seconds> [k]
#     bash aid-gate-runtime-baseline.sh mark-policy-block <gate_name> <operator_action>
#     bash aid-gate-runtime-baseline.sh recommend-timeout <gate_name>
#     bash aid-gate-runtime-baseline.sh recommend-run-mode <gate_name>
#     bash aid-gate-runtime-baseline.sh show <gate_name>
#     bash aid-gate-runtime-baseline.sh report-json <gate_name>
# =============================================================================

# ─── Paths ───────────────────────────────────────────────────────────────────

# _gbr_baseline_file — echoes the baseline file path (CWD-relative default,
# AID_GATE_BASELINE_FILE override for tests/callers that need isolation).
_gbr_baseline_file() {
  echo "${AID_GATE_BASELINE_FILE:-.aid-o/metrics/gate-runtime-baselines.yaml}"
}

# _gbr_lock_file — sidecar lock path for the CURRENT baseline file.
_gbr_lock_file() {
  echo "$(_gbr_baseline_file).lock"
}

_gbr_warn() {
  echo "WARN: aid-gate-runtime-baseline.sh: $*" >&2
}

# _gbr_require_deps — yq + jq must both be present. Returns 1 (never crashes)
# if either is missing; callers treat that as "skip, warn, fail open/null".
_gbr_require_deps() {
  command -v yq >/dev/null 2>&1 || { _gbr_warn "yq not found on PATH"; return 1; }
  command -v jq >/dev/null 2>&1 || { _gbr_warn "jq not found on PATH"; return 1; }
  return 0
}

# ─── Doc read helpers ────────────────────────────────────────────────────────

# _gbr_read_doc_json_writer <file> — READ-PATH used ONLY by the two writers
# (gate_baseline_update / gate_baseline_mark_policy_block), which already hold
# the flock. On malformed YAML, quarantines the file as <file>.corrupt.<ts>
# (never silently discarded) and returns "{}" (fresh series). Always echoes
# valid JSON on stdout; never returns non-zero.
_gbr_read_doc_json_writer() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo '{}'
    return 0
  fi
  if ! yq -e '.' "$file" >/dev/null 2>&1; then
    local ts corrupt
    ts=$(date +%s)
    corrupt="${file}.corrupt.${ts}"
    if mv "$file" "$corrupt" 2>/dev/null; then
      _gbr_warn "malformed baseline file quarantined as $corrupt — starting a fresh series"
    else
      _gbr_warn "malformed baseline file at $file could not be quarantined (mv failed) — starting a fresh series anyway"
    fi
    echo '{}'
    return 0
  fi
  yq -o=json '.' "$file" 2>/dev/null || echo '{}'
}

# _gbr_read_doc_json_readonly <file> — READ-PATH used by read-only accessors
# (gate_baseline_policy_check, gate_baseline_show, gate_baseline_report_json,
# gate_baseline_recommend_*). Deliberately does NOT quarantine a malformed
# file itself (no flock held here — that rename is reserved for the guarded
# writer path so two concurrent readers never race on the same rename).
# Treats a malformed/absent file as "{}" either way.
_gbr_read_doc_json_readonly() {
  local file="$1"
  [[ -f "$file" ]] || { echo '{}'; return 0; }
  if ! yq -e '.' "$file" >/dev/null 2>&1; then
    _gbr_warn "baseline file $file appears malformed (read-only access) — treating as absent for this read; the next write will quarantine it"
    echo '{}'
    return 0
  fi
  yq -o=json '.' "$file" 2>/dev/null || echo '{}'
}

# _gbr_get_entry_json <gate_name> — echoes gates.<gate_name> as JSON, or the
# JSON literal `null` if absent/unreadable. Read-only path.
_gbr_get_entry_json() {
  local gate_name="$1"
  local file doc_json
  file=$(_gbr_baseline_file)
  doc_json=$(_gbr_read_doc_json_readonly "$file")
  jq -c --arg gn "$gate_name" '.gates[$gn] // null' <<<"$doc_json" 2>/dev/null || echo "null"
}

# ─── Recommendation arithmetic (pure functions — no I/O) ────────────────────
# Shared by gate_baseline_update (fed freshly-computed values) AND
# gate_baseline_recommend_timeout/run_mode (fed values re-read from disk) so
# the formula lives in exactly one place.

# _gbr_calc_timeout_rec <p95_ms|null> <non_censored_count> — echoes the
# recommended timeout in seconds, or nothing if non_censored_count < 3.
_gbr_calc_timeout_rec() {
  local p95_ms="$1" nc="${2:-0}"
  [[ "$p95_ms" == "null" || -z "$p95_ms" ]] && return 0
  [[ "$nc" =~ ^[0-9]+$ ]] || return 0
  (( nc < 3 )) && return 0
  [[ "$p95_ms" =~ ^-?[0-9]+$ ]] || return 0
  local p95_ms_x15 floor_ms timeout_recommended_ms timeout_recommended_seconds
  p95_ms_x15=$(( p95_ms * 3 / 2 ))
  floor_ms=$(( p95_ms + 60000 ))
  timeout_recommended_ms=$(( p95_ms_x15 > floor_ms ? p95_ms_x15 : floor_ms ))
  timeout_recommended_seconds=$(( (timeout_recommended_ms + 999) / 1000 ))
  echo "$timeout_recommended_seconds"
}

# _gbr_calc_run_mode_rec <p95_ms|null> <non_censored_count> — echoes
# "background"/"foreground", or nothing if non_censored_count < 5.
_gbr_calc_run_mode_rec() {
  local p95_ms="$1" nc="${2:-0}"
  [[ "$p95_ms" == "null" || -z "$p95_ms" ]] && return 0
  [[ "$nc" =~ ^[0-9]+$ ]] || return 0
  (( nc < 5 )) && return 0
  [[ "$p95_ms" =~ ^-?[0-9]+$ ]] || return 0
  if (( p95_ms > 600000 )); then
    echo "background"
  else
    echo "foreground"
  fi
}

# _gbr_ms_to_human <ms> — coarse human-readable duration for gate_baseline_show.
_gbr_ms_to_human() {
  local ms="$1"
  [[ -z "$ms" || "$ms" == "null" ]] && { echo "n/a"; return 0; }
  [[ "$ms" =~ ^-?[0-9]+$ ]] || { echo "n/a"; return 0; }
  if (( ms < 60000 )); then
    echo "$(( (ms + 999) / 1000 ))s"
  else
    echo "$(( (ms + 59999) / 60000 ))m"
  fi
}

# ─── 1. gate_baseline_fingerprint ───────────────────────────────────────────
# gate_baseline_fingerprint <gate_name> <command_template>
#   echoes "sha256:<first 12 hex chars>" of sha256sum("<gate_name>:<command_template>").
gate_baseline_fingerprint() {
  local gate_name="$1" command_template="$2"
  if ! command -v sha256sum >/dev/null 2>&1; then
    _gbr_warn "sha256sum not found — cannot compute fingerprint"
    return 1
  fi
  local h
  h=$(printf '%s' "${gate_name}:${command_template}" | sha256sum 2>/dev/null | cut -c1-12)
  if [[ -z "$h" ]]; then
    _gbr_warn "fingerprint computation failed for gate '$gate_name'"
    return 1
  fi
  echo "sha256:${h}"
}

# ─── 2. gate_baseline_update ────────────────────────────────────────────────
# gate_baseline_update <gate_name> <command_template> <resolved_command> \
#                      <exit_code> <duration_ms> <timeout_seconds>
gate_baseline_update() {
  local gate_name="$1" command_template="$2" resolved_command="$3" \
        exit_code="$4" duration_ms="$5" timeout_seconds="$6"

  if [[ -z "$gate_name" ]]; then
    _gbr_warn "gate_baseline_update: gate_name is required — skipping write"
    return 0
  fi
  if [[ ! "$exit_code" =~ ^-?[0-9]+$ || ! "$duration_ms" =~ ^[0-9]+$ || ! "$timeout_seconds" =~ ^[0-9]+$ ]]; then
    _gbr_warn "gate_baseline_update: exit_code/duration_ms/timeout_seconds must be integers (gate '$gate_name') — skipping write"
    return 0
  fi
  _gbr_require_deps || return 0

  local fingerprint
  fingerprint=$(gate_baseline_fingerprint "$gate_name" "$command_template") || {
    _gbr_warn "gate_baseline_update: could not compute fingerprint for '$gate_name' — skipping write"
    return 0
  }

  local file lockfile
  file=$(_gbr_baseline_file)
  lockfile=$(_gbr_lock_file)

  mkdir -p "$(dirname "$file")" 2>/dev/null || {
    _gbr_warn "gate_baseline_update: could not create $(dirname "$file") — skipping write"
    return 0
  }

  # TODO(Step 2): call gate_baseline_ensure_gitignored here — lazy, one-time-
  # per-clone .git/info/exclude backfill for already-initialized existing
  # projects (brand-new projects already get `.aid-o/metrics/` via shipped
  # defaults/.gitignore). Step 2 owns that helper's implementation; this is
  # its integration point.

  touch "$lockfile" 2>/dev/null

  (
    flock -w 5 200 || {
      _gbr_warn "gate_baseline_update: lock timeout (5s) on $lockfile — skipping this sample write (fail open)"
      exit 0
    }

    local doc_json
    doc_json=$(_gbr_read_doc_json_writer "$file")

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

    local existing_entry
    existing_entry=$(jq -c --arg gn "$gate_name" '.gates[$gn] // null' <<<"$doc_json" 2>/dev/null)
    [[ -z "$existing_entry" ]] && existing_entry="null"

    local existing_fp
    existing_fp=$(jq -r 'if . == null then "" else (.command_fingerprint // "") end' <<<"$existing_entry" 2>/dev/null)

    local reset_json="false"
    [[ "$existing_fp" != "$fingerprint" ]] && reset_json="true"

    local last_attempt_result censored_json
    case "$exit_code" in
      124) last_attempt_result="timeout"; censored_json="true" ;;
      0)   last_attempt_result="pass"; censored_json="false" ;;
      *)   last_attempt_result="fail"; censored_json="false" ;;
    esac

    # Base recent_samples window: empty on reset, else the existing window.
    local base_samples_json
    if [[ "$reset_json" == "true" ]]; then
      base_samples_json="[]"
    else
      base_samples_json=$(jq -c '.recent_samples // []' <<<"$existing_entry" 2>/dev/null)
      [[ -z "$base_samples_json" ]] && base_samples_json="[]"
    fi

    local new_sample_json
    new_sample_json=$(jq -nc \
      --argjson duration_ms "$duration_ms" \
      --argjson exit_code "$exit_code" \
      --argjson timeout_seconds "$timeout_seconds" \
      --argjson censored "$censored_json" \
      --arg recorded_at "$now" \
      '{duration_ms: $duration_ms, exit_code: $exit_code, timeout_seconds: $timeout_seconds, censored: $censored, recorded_at: $recorded_at}')

    # Append + FIFO-evict to a max-20 window (bounded WINDOW, not lifetime).
    local samples_json
    samples_json=$(jq -c --argjson s "$new_sample_json" \
      '(. + [$s]) | if length > 20 then .[-20:] else . end' \
      <<<"$base_samples_json")

    # Percentiles + window counts, over the non-censored subset only.
    local computed_json
    computed_json=$(jq -c '
      def nearest_rank(P; arr):
        (arr|length) as $n
        | if $n == 0 then null
          else
            ((( (P/100*$n) | ceil) - 1)) as $idx0
            | (if $idx0 < 0 then 0 elif $idx0 > ($n-1) then ($n-1) else $idx0 end) as $idx
            | arr[$idx]
          end;
      (map(select(.censored==false))) as $nc
      | ($nc | map(.duration_ms) | sort) as $durs
      | {
          samples_count: length,
          non_censored_samples_count: ($nc|length),
          p50_ms: nearest_rank(50; $durs),
          p90_ms: nearest_rank(90; $durs),
          p95_ms: nearest_rank(95; $durs),
          max_ms: (if ($durs|length) > 0 then ($durs|last) else null end)
        }
    ' <<<"$samples_json")

    local p95_for_rec nc_for_rec
    p95_for_rec=$(jq -r '.p95_ms // "null"' <<<"$computed_json")
    nc_for_rec=$(jq -r '.non_censored_samples_count' <<<"$computed_json")

    local timeout_rec run_mode_rec timeout_rec_json run_mode_rec_json
    timeout_rec=$(_gbr_calc_timeout_rec "$p95_for_rec" "$nc_for_rec")
    run_mode_rec=$(_gbr_calc_run_mode_rec "$p95_for_rec" "$nc_for_rec")
    timeout_rec_json="null"
    [[ -n "$timeout_rec" ]] && timeout_rec_json="$timeout_rec"
    run_mode_rec_json="null"
    [[ -n "$run_mode_rec" ]] && run_mode_rec_json="\"$run_mode_rec\""

    # Build the final entry. policy_result/retryable/operator_action are
    # RUN-SCOPED STATE, not a permanent label — they describe whether a
    # policy block is CURRENTLY active, not whether one ever happened. Every
    # gate_baseline_update call (i.e. every new attempt, per aid-run-gates.sh's
    # per-attempt call site) therefore RESETS them unconditionally to their
    # cleared defaults ("none"/true/null), regardless of what $existing carried.
    # gate_baseline_mark_policy_block is the ONLY function that ever flips them
    # to an active block — it runs strictly AFTER this function within the
    # same attempt's processing (aid-run-gates.sh: gate_baseline_update first,
    # then gate_baseline_policy_check against the just-written samples, then
    # gate_baseline_mark_policy_block only if that check says "block"). This
    # is what makes a past block clear itself the moment a gate's own next
    # attempt runs — on a pass, on a command_template edit (fingerprint reset,
    # handled the same way since $reset no longer matters for these three
    # fields), or on a raised timeout_seconds that stops re-triggering the
    # policy check. History is NOT lost: recent_samples (the censored/timeout
    # trail) is untouched here and only cleared by an actual fingerprint reset,
    # so a past block remains reconstructable from the sample window even
    # though the live retryable/policy_result flags move on.
    local entry_json
    entry_json=$(jq -nc \
      --arg fingerprint "$fingerprint" \
      --arg command_template "$command_template" \
      --arg resolved_command "$resolved_command" \
      --argjson recent_samples "$samples_json" \
      --argjson computed "$computed_json" \
      --argjson duration_ms "$duration_ms" \
      --argjson exit_code "$exit_code" \
      --argjson timeout_seconds "$timeout_seconds" \
      --arg last_attempt_result "$last_attempt_result" \
      --argjson existing "$existing_entry" \
      --argjson reset "$reset_json" \
      --arg now "$now" \
      --argjson timeout_recommended_seconds "$timeout_rec_json" \
      --argjson run_mode_recommended "$run_mode_rec_json" \
      '{
        command_fingerprint: $fingerprint,
        command_template: $command_template,
        last_resolved_command: $resolved_command,
        samples_count: $computed.samples_count,
        non_censored_samples_count: $computed.non_censored_samples_count,
        recent_samples: $recent_samples,
        p50_ms: $computed.p50_ms,
        p90_ms: $computed.p90_ms,
        p95_ms: $computed.p95_ms,
        max_ms: $computed.max_ms,
        last_duration_ms: $duration_ms,
        last_exit_code: $exit_code,
        last_attempt_result: $last_attempt_result,
        policy_result: "none",
        last_timeout_seconds: $timeout_seconds,
        timeout_recommended_seconds: $timeout_recommended_seconds,
        run_mode_recommended: $run_mode_recommended,
        retryable: true,
        operator_action: null,
        last_updated: $now,
        series_reset_at: (if $reset then $now else ($existing.series_reset_at // null) end)
      }')

    local updated_doc
    updated_doc=$(jq -c --arg gn "$gate_name" --argjson entry "$entry_json" '.gates[$gn] = $entry' <<<"$doc_json")

    # Atomic write: tmp file -> validate -> mv. A crash/kill between the tmp
    # write and the mv leaves the REAL file exactly as it was (never a torn
    # write) — this is the actual mechanism AC12 exercises.
    local tmp="${file}.tmp.$$"
    if ! yq -p=json -o=yaml '.' <<<"$updated_doc" > "$tmp" 2>/dev/null; then
      _gbr_warn "gate_baseline_update: failed to serialize updated baseline (gate '$gate_name') — aborting this write, real file untouched"
      rm -f "$tmp" 2>/dev/null
      exit 0
    fi
    if ! yq -e '.' "$tmp" >/dev/null 2>&1; then
      _gbr_warn "gate_baseline_update: tmp file $tmp failed to validate — aborting this write, real file untouched"
      rm -f "$tmp" 2>/dev/null
      exit 0
    fi
    if ! mv "$tmp" "$file" 2>/dev/null; then
      _gbr_warn "gate_baseline_update: mv of $tmp over $file failed — real file retains its pre-write content"
      exit 0
    fi
  ) 200>"$lockfile"

  return 0
}

# ─── 3. gate_baseline_policy_check ──────────────────────────────────────────
# gate_baseline_policy_check <gate_name> <current_timeout_seconds> [k=3]
#   echoes "block" iff the last k recent_samples entries are ALL censored AND
#   each entry's own timeout_seconds >= current_timeout_seconds; else "no-block".
#   Read-only — never writes policy_result/retryable itself.
gate_baseline_policy_check() {
  local gate_name="$1" current_timeout_seconds="$2" k="${3:-3}"

  if [[ -z "$gate_name" || ! "$current_timeout_seconds" =~ ^[0-9]+$ || ! "$k" =~ ^[0-9]+$ ]]; then
    _gbr_warn "gate_baseline_policy_check: invalid arguments — failing open (no-block)"
    echo "no-block"
    return 0
  fi
  _gbr_require_deps || { echo "no-block"; return 0; }

  local entry_json
  entry_json=$(_gbr_get_entry_json "$gate_name")
  if [[ -z "$entry_json" || "$entry_json" == "null" ]]; then
    echo "no-block"
    return 0
  fi

  local result
  result=$(jq -r --argjson k "$k" --argjson cur "$current_timeout_seconds" '
    (.recent_samples // []) as $s
    | ($s[-$k:]) as $last_k
    | if ($last_k|length) < $k then "no-block"
      elif (all($last_k[]; .censored == true and .timeout_seconds >= $cur)) then "block"
      else "no-block"
      end
  ' <<<"$entry_json" 2>/dev/null)

  echo "${result:-no-block}"
}

# ─── 4. gate_baseline_mark_policy_block ─────────────────────────────────────
# gate_baseline_mark_policy_block <gate_name> <operator_action>
#   SECOND write to the SAME entry gate_baseline_update already wrote for this
#   attempt — called ONLY when gate_baseline_policy_check just returned
#   "block". Same flock/atomic-write discipline as gate_baseline_update.
gate_baseline_mark_policy_block() {
  local gate_name="$1" operator_action="$2"

  if [[ -z "$gate_name" ]]; then
    _gbr_warn "gate_baseline_mark_policy_block: gate_name is required — skipping write"
    return 0
  fi
  _gbr_require_deps || return 0

  local file lockfile
  file=$(_gbr_baseline_file)
  lockfile=$(_gbr_lock_file)

  mkdir -p "$(dirname "$file")" 2>/dev/null || {
    _gbr_warn "gate_baseline_mark_policy_block: could not create $(dirname "$file") — skipping write"
    return 0
  }
  touch "$lockfile" 2>/dev/null

  (
    flock -w 5 200 || {
      _gbr_warn "gate_baseline_mark_policy_block: lock timeout (5s) on $lockfile — skipping this write (fail open)"
      exit 0
    }

    local doc_json
    doc_json=$(_gbr_read_doc_json_writer "$file")

    if ! jq -e --arg gn "$gate_name" '.gates[$gn] != null' <<<"$doc_json" >/dev/null 2>&1; then
      _gbr_warn "gate_baseline_mark_policy_block: no existing entry for gate '$gate_name' — nothing to mark, skipping"
      exit 0
    fi

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

    local updated_doc
    updated_doc=$(jq -c \
      --arg gn "$gate_name" \
      --arg oa "$operator_action" \
      --arg now "$now" \
      '.gates[$gn].policy_result = "timeout_policy_block"
       | .gates[$gn].retryable = false
       | .gates[$gn].operator_action = $oa
       | .gates[$gn].last_updated = $now' \
      <<<"$doc_json")

    local tmp="${file}.tmp.$$"
    if ! yq -p=json -o=yaml '.' <<<"$updated_doc" > "$tmp" 2>/dev/null; then
      _gbr_warn "gate_baseline_mark_policy_block: failed to serialize updated baseline (gate '$gate_name') — aborting this write, real file untouched"
      rm -f "$tmp" 2>/dev/null
      exit 0
    fi
    if ! yq -e '.' "$tmp" >/dev/null 2>&1; then
      _gbr_warn "gate_baseline_mark_policy_block: tmp file $tmp failed to validate — aborting this write, real file untouched"
      rm -f "$tmp" 2>/dev/null
      exit 0
    fi
    if ! mv "$tmp" "$file" 2>/dev/null; then
      _gbr_warn "gate_baseline_mark_policy_block: mv of $tmp over $file failed — real file retains its pre-write content"
      exit 0
    fi
  ) 200>"$lockfile"

  return 0
}

# ─── 5. gate_baseline_recommend_timeout ─────────────────────────────────────
# gate_baseline_recommend_timeout <gate_name> — echoes the recommended
# timeout_seconds, or nothing (empty stdout) if non_censored_samples_count < 3
# or the gate has no entry yet.
gate_baseline_recommend_timeout() {
  local gate_name="$1"
  _gbr_require_deps || return 0
  local entry_json
  entry_json=$(_gbr_get_entry_json "$gate_name")
  [[ "$entry_json" == "null" ]] && return 0
  local p95_ms nc
  p95_ms=$(jq -r '.p95_ms // "null"' <<<"$entry_json")
  nc=$(jq -r '.non_censored_samples_count // 0' <<<"$entry_json")
  _gbr_calc_timeout_rec "$p95_ms" "$nc"
}

# ─── 6. gate_baseline_recommend_run_mode ────────────────────────────────────
# gate_baseline_recommend_run_mode <gate_name> — echoes "foreground"/
# "background", or nothing if non_censored_samples_count < 5 or no entry yet.
gate_baseline_recommend_run_mode() {
  local gate_name="$1"
  _gbr_require_deps || return 0
  local entry_json
  entry_json=$(_gbr_get_entry_json "$gate_name")
  [[ "$entry_json" == "null" ]] && return 0
  local p95_ms nc
  p95_ms=$(jq -r '.p95_ms // "null"' <<<"$entry_json")
  nc=$(jq -r '.non_censored_samples_count // 0' <<<"$entry_json")
  _gbr_calc_run_mode_rec "$p95_ms" "$nc"
}

# ─── 7. gate_baseline_show ───────────────────────────────────────────────────
# gate_baseline_show <gate_name> — human-readable one-line summary, e.g.:
#   "bats_all [fp:a1b2c3d4, last sample 2026-07-12T09:15:00Z]: p95 34m, recommended background, timeout 50m"
# or an explicit "insufficient data" message when thresholds aren't met.
gate_baseline_show() {
  local gate_name="$1"
  if ! _gbr_require_deps; then
    echo "${gate_name}: unavailable (yq/jq not found)"
    return 0
  fi

  local entry_json
  entry_json=$(_gbr_get_entry_json "$gate_name")
  if [[ "$entry_json" == "null" ]]; then
    echo "${gate_name}: insufficient data (no runs recorded yet)"
    return 0
  fi

  local fp fp_short last_sample_at p95_ms nc timeout_rec run_mode_rec
  fp=$(jq -r '.command_fingerprint // ""' <<<"$entry_json")
  fp_short="${fp#sha256:}"
  fp_short="${fp_short:0:8}"
  last_sample_at=$(jq -r '(.recent_samples // [])[-1].recorded_at // "n/a"' <<<"$entry_json")
  p95_ms=$(jq -r '.p95_ms // "null"' <<<"$entry_json")
  nc=$(jq -r '.non_censored_samples_count // 0' <<<"$entry_json")

  if [[ "$p95_ms" == "null" ]]; then
    echo "${gate_name} [fp:${fp_short}, last sample ${last_sample_at}]: insufficient data (no non-censored samples yet)"
    return 0
  fi

  timeout_rec=$(_gbr_calc_timeout_rec "$p95_ms" "$nc")
  run_mode_rec=$(_gbr_calc_run_mode_rec "$p95_ms" "$nc")

  local p95_human timeout_human run_mode_txt
  p95_human=$(_gbr_ms_to_human "$p95_ms")
  if [[ -n "$timeout_rec" ]]; then
    timeout_human=$(_gbr_ms_to_human $(( timeout_rec * 1000 )))
  else
    timeout_human="insufficient data"
  fi
  run_mode_txt="${run_mode_rec:-insufficient data}"

  echo "${gate_name} [fp:${fp_short}, last sample ${last_sample_at}]: p95 ${p95_human}, recommended ${run_mode_txt}, timeout ${timeout_human}"
}

# ─── 8. gate_baseline_report_json ───────────────────────────────────────────
# gate_baseline_report_json <gate_name> — echoes the additive JSON object for
# gates_report.json's runtime_baseline field (Step 2 consumes this directly).
gate_baseline_report_json() {
  local gate_name="$1"
  if ! _gbr_require_deps; then
    echo '{"samples_count":0,"non_censored_samples_count":0,"p95_ms":null,"timeout_recommended_seconds":null,"run_mode_recommended":null,"data_sufficient":false,"last_attempt_result":null,"policy_result":"none","retryable":true,"operator_action":null}'
    return 0
  fi

  local entry_json
  entry_json=$(_gbr_get_entry_json "$gate_name")
  if [[ "$entry_json" == "null" ]]; then
    jq -nc '{
      samples_count: 0, non_censored_samples_count: 0, p95_ms: null,
      timeout_recommended_seconds: null, run_mode_recommended: null,
      data_sufficient: false, last_attempt_result: null, policy_result: "none",
      retryable: true, operator_action: null
    }'
    return 0
  fi

  jq -c '{
    samples_count: (.samples_count // 0),
    non_censored_samples_count: (.non_censored_samples_count // 0),
    p95_ms: (.p95_ms // null),
    timeout_recommended_seconds: (.timeout_recommended_seconds // null),
    run_mode_recommended: (.run_mode_recommended // null),
    data_sufficient: ((.non_censored_samples_count // 0) >= 3),
    last_attempt_result: (.last_attempt_result // null),
    policy_result: (.policy_result // "none"),
    retryable: (if (.retryable == null) then true else .retryable end),
    operator_action: (.operator_action // null)
  }' <<<"$entry_json"
}

# ── Standalone dispatch (skipped when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    fingerprint)
      gate_baseline_fingerprint "${2:-}" "${3:-}"
      ;;
    update)
      gate_baseline_update "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
      ;;
    policy-check)
      gate_baseline_policy_check "${2:-}" "${3:-}" "${4:-3}"
      ;;
    mark-policy-block)
      gate_baseline_mark_policy_block "${2:-}" "${3:-}"
      ;;
    recommend-timeout)
      gate_baseline_recommend_timeout "${2:-}"
      ;;
    recommend-run-mode)
      gate_baseline_recommend_run_mode "${2:-}"
      ;;
    show)
      gate_baseline_show "${2:-}"
      ;;
    report-json)
      gate_baseline_report_json "${2:-}"
      ;;
    *)
      echo "Usage: aid-gate-runtime-baseline.sh {fingerprint <gate_name> <command_template> | update <gate_name> <command_template> <resolved_command> <exit_code> <duration_ms> <timeout_seconds> | policy-check <gate_name> <current_timeout_seconds> [k] | mark-policy-block <gate_name> <operator_action> | recommend-timeout <gate_name> | recommend-run-mode <gate_name> | show <gate_name> | report-json <gate_name>}" >&2
      exit 1
      ;;
  esac
fi
