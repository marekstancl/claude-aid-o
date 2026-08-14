#!/usr/bin/env bash
# =============================================================================
# aid-nightly-report.sh — turn a nightly portfolio run into a durable result
# and, on red, one message (P081 Step 7).
#
# A FILE FIRST, A MESSAGE SECOND. The artifact is written before anything is
# sent, so a lost, muted or misconfigured Telegram channel never means a lost
# result. The standard demands the second surface for exactly that reason, and
# `/aid-status` reads this same file.
#
# WHERE THE ARTIFACT LIVES, AND WHY NOT `.aid-o/`: the CI job runs in the
# self-hosted runner's own `_work` checkout, so `aid_state_root()` there
# resolves to that checkout — and `.gitignore` ignores `**/.aid-o/`, so a file
# written under it in CI can never be read from the PM's checkout. The second
# surface would render nothing forever and look exactly like a healthy fresh
# project. The artifact therefore lives on a shared HOST path:
#   ${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}/<date>.json
# plus a `latest.json` pointer.
#
# THE ASSUMPTION THIS MAKES, stated rather than hidden: the self-hosted runner
# and the checkout that reads the result are the SAME HOST (both `eco-dev`
# here — `.github/workflows/*.yml` pin `runs-on: [self-hosted, eco-dev]` and
# the repository lives there). A host path is not magic: uploading the file as
# a GitHub artifact does NOT materialise it on anyone's machine. A project
# whose runner is elsewhere must point `AID_NIGHTLY_DIR` at something both
# sides can genuinely see — a shared mount, or a fetch step — before the
# second surface means anything.
#
# FLAKY IS ITS OWN STATE. Every failing suite is retried EXACTLY ONCE. Pass on
# the retry ⇒ recorded `flaky` and quarantined (see aid-test-quarantine.sh),
# not counted as a failure. Fail again ⇒ a real failure.
#
# RED IS REPORTED ONCE, THEN COUNTED. A failure already in last night's
# artifact increments a streak instead of sending another message; the message
# goes out when something is NEW, or when a quarantine entry has aged past its
# deadline with no owner. A green night sends nothing at all.
#
# Usage:
#   aid-nightly-report.sh --runner-log <file> [--exit-code N] [--log-url URL]
#                         [--tests-dir DIR] [--dir DIR] [--no-notify]
#
# Exit codes: 0 = the artifact was written (whatever the night's colour),
#             2 = usage / the artifact could not be written.
#
# **Last Updated:** 2026-08-10
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-tier.sh
source "$SCRIPT_DIR/lib/aid-test-tier.sh"
# shellcheck source=lib/aid-test-durations.sh
source "$SCRIPT_DIR/lib/aid-test-durations.sh"

QUARANTINE_SH="$SCRIPT_DIR/aid-test-quarantine.sh"
ESCALATE_DAYS="${AID_QUARANTINE_ESCALATE_DAYS:-14}"
TELEGRAM_LIB="${AID_TELEGRAM_LIB:-/opt/eco/services/scripts/lib/telegram-notify.sh}"

# The retry re-invokes the RUNNER (see the retry block below). Overridable so
# a fixture can supply a stub — the seam exists for tests, not for production.
RUNNER="${AID_NIGHTLY_RUNNER:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests/run-all-tests.sh}"
RUNNER_LOG=""; EXIT_CODE=0; LOG_URL=""; TESTS_DIR=""; NOTIFY=1
# Merge-path tier budgets, in seconds, from the ecosystem test standard.
# Measured, never summed: a tier's budget is verified by a REAL RUN, because
# the runner's ~2 s per-suite overhead makes a sum of suite times a lie.
T0_SECONDS=""; T1_SECONDS=""
T0_BUDGET_S="${AID_T0_BUDGET_S:-120}"; T1_BUDGET_S="${AID_T1_BUDGET_S:-600}"
NIGHTLY_DIR="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner-log) [[ $# -ge 2 ]] || { echo "aid-nightly-report: --runner-log needs a value" >&2; exit 2; }
                  RUNNER_LOG="$2"; shift 2 ;;
    --t0-seconds) T0_SECONDS="${2:-}"; shift 2 ;;
    --t1-seconds) T1_SECONDS="${2:-}"; shift 2 ;;
    --exit-code) [[ $# -ge 2 ]] || { echo "aid-nightly-report: --exit-code needs a value" >&2; exit 2; }
                 EXIT_CODE="$2"; shift 2 ;;
                 # NOTE: an EMPTY or non-numeric value is handled below, not
                 # here — it is the normal shape after a portfolio TIMEOUT.
    --log-url) [[ $# -ge 2 ]] || { echo "aid-nightly-report: --log-url needs a value" >&2; exit 2; }
               LOG_URL="$2"; shift 2 ;;
    --tests-dir) [[ $# -ge 2 ]] || { echo "aid-nightly-report: --tests-dir needs a value" >&2; exit 2; }
                 TESTS_DIR="$2"; shift 2 ;;
    --dir) [[ $# -ge 2 ]] || { echo "aid-nightly-report: --dir needs a value" >&2; exit 2; }
           NIGHTLY_DIR="$2"; shift 2 ;;
    --no-notify)  NOTIFY=0; shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "aid-nightly-report: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$RUNNER_LOG" && -f "$RUNNER_LOG" ]] || {
  echo "aid-nightly-report: --runner-log must name an existing file" >&2; exit 2; }
[[ -n "$TESTS_DIR" ]] || TESTS_DIR="$(aid_test_default_tests_dir)"
export AID_NIGHTLY_DIR="$NIGHTLY_DIR"

mkdir -p "$NIGHTLY_DIR" 2>/dev/null || {
  echo "aid-nightly-report: cannot create '$NIGHTLY_DIR' — the result would have nowhere durable to live" >&2
  exit 2; }

TODAY="$(date -u +%Y-%m-%d)"
ARTIFACT="$NIGHTLY_DIR/$TODAY.json"
LATEST="$NIGHTLY_DIR/latest.json"

# ─── What the run said ──────────────────────────────────────────────────────
suites_run="$(sed -nE 's/^[[:space:]]*Suites:[[:space:]]+[0-9]+\/([0-9]+) passed.*/\1/p' "$RUNNER_LOG" | tail -1)"
suites_passed="$(sed -nE 's/^[[:space:]]*Suites:[[:space:]]+([0-9]+)\/[0-9]+ passed.*/\1/p' "$RUNNER_LOG" | tail -1)"
[[ "$suites_run" =~ ^[0-9]+$ ]] || suites_run=0
[[ "$suites_passed" =~ ^[0-9]+$ ]] || suites_passed=0

# The summary block is the runner's own end marker. Its absence with suite
# output present means the job was cut short — a partial result that says so,
# never a green one.
censored=false
if ! grep -q '^  Summary$' "$RUNNER_LOG" && grep -q '^Suite [0-9]' "$RUNNER_LOG"; then
  censored=true
fi

mapfile -t reported_failures < <(
  sed -nE '/^[[:space:]]*Failed suites:/,/^$/ s/^[[:space:]]+- (.+)$/\1/p' "$RUNNER_LOG")

# A non-zero exit with nothing named is still a failure — of the runner itself.
# An empty or non-numeric exit code is what a TIMED-OUT portfolio step leaves
# behind: the step never reaches its `echo "exit_code=$?" >> $GITHUB_OUTPUT`,
# and `continue-on-error: true` hides the timeout, so this script was handed an
# empty string. It then died in jq and wrote NOTHING — three consecutive nights
# (2026-08-12/13/14) produced 0-byte artifacts and no alert, because the very
# thing that reports a bad night is what crashed. A reporter that cannot
# survive its own worst input is not a reporter.
#
# So: an unusable exit code becomes an EXPLICIT unknown. The night is reported
# as failed — a portfolio that did not tell us how it ended did not pass — and
# the reason is named rather than inferred.
EXIT_CODE_KNOWN=1
if [[ ! "$EXIT_CODE" =~ ^[0-9]+$ ]]; then
  EXIT_CODE_KNOWN=0
  echo "aid-nightly-report: exit code '${EXIT_CODE}' is not a number — treating the night as FAILED with reason 'runner did not report (timeout?)'." >&2
  EXIT_CODE=1
fi

if [[ "$EXIT_CODE" -ne 0 && "${#reported_failures[@]}" -eq 0 ]]; then
  reported_failures=("(runner)")
fi

# ─── suite_path <suite_name> — the file behind a reported name ──────────────
# The runner reports names with the extension stripped, so both candidates are
# checked. A name that resolves to no file cannot be retried and is treated as
# a hard failure rather than optimistically as flaky.
suite_path() {
  local name="$1" p
  for p in "$TESTS_DIR/bats/$name.bats" "$TESTS_DIR/$name.sh"; do
    [[ -f "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

# ─── Retry once: flaky and failed are different states ──────────────────────
failed=(); flaky=(); quarantine_write_failed=false
for name in ${reported_failures[@]+"${reported_failures[@]}"}; do
  path="$(suite_path "$name")" || { failed+=("$name"); continue; }
  # THE RETRY MUST USE THE RUNNER, NOT A BARE INVOCATION. Re-running `bats
  # "$path"` directly re-runs the suite under different conditions than the
  # run that failed: a different cwd, no `--include-delegated`, none of the
  # runner's fd-3 discipline and none of its exported AID_* environment. A
  # suite that fails ONLY under runner conditions therefore passes standalone,
  # is filed as flaky instead of failed, drops out of `failed[]` entirely, and
  # the night reports GREEN while a real regression sits in the tree. A green
  # that is not green destroys trust in every other green, so the retry
  # re-invokes the runner for that one suite.
  if [[ -x "$RUNNER" ]]; then
    "$RUNNER" --only "$name" >/dev/null 2>&1 && retry_ok=1 || retry_ok=0
  elif [[ "$path" == *.bats ]]; then
    # No runner reachable: a bare re-run cannot distinguish flaky from
    # runner-conditional, so treat the suite as FAILED rather than laundering
    # it into a silent quarantine.
    echo "aid-nightly-report: runner not executable at '$RUNNER' — '$name' stays FAILED rather than being retried under different conditions" >&2
    retry_ok=0
  else
    echo "aid-nightly-report: runner not executable at '$RUNNER' — '$name' stays FAILED rather than being retried under different conditions" >&2
    retry_ok=0
  fi
  if [[ "$retry_ok" -eq 1 ]]; then
    flaky+=("$name")
    # A quarantine that was not written is a suite that will never age and
    # never escalate — the artifact would show it flaky tonight and forget it
    # tomorrow. Say so rather than swallowing the write.
    if ! bash "$QUARANTINE_SH" add "$name" "" >/dev/null 2>&1; then
      echo "aid-nightly-report: '$name' is flaky but could NOT be quarantined — it will not age or escalate until this is fixed" >&2
      quarantine_write_failed=true
    fi
  else
    failed+=("$name")
  fi
done

# ─── Streaks, read from last night before today's file replaces it ──────────
prev_failed_json='[]'
if [[ -f "$LATEST" ]]; then
  prev_failed_json="$(jq -c '[.failed[]? | {suite, streak}]' "$LATEST" 2>/dev/null)" || prev_failed_json='[]'
fi

failed_json="$(printf '%s\n' ${failed[@]+"${failed[@]}"} \
  | jq -Rc 'select(length > 0)' \
  | jq -sc --argjson prev "$prev_failed_json" '
      map(. as $s
        | ($prev | map(select(.suite == $s)) | first) as $before
        | {suite: $s,
           streak: (if $before then ($before.streak + 1) else 1 end),
           known: ($before != null)})')"

flaky_json="$(printf '%s\n' ${flaky[@]+"${flaky[@]}"} | jq -Rc 'select(length > 0)' | jq -sc '.')"
# An unreadable quarantine record is NOT an empty one. Defaulting to `[]` would
# hide every overdue entry and report a clean night.
quarantine_unreadable=false
if ! quarantined_json="$(bash "$QUARANTINE_SH" list --json 2>/dev/null)"; then
  quarantine_unreadable=true
  quarantined_json='[]'
  echo "aid-nightly-report: the quarantine record could not be read — overdue entries cannot be reported tonight" >&2
fi

# The night's portfolio cost, summed from the durations the run itself just
# refreshed — never a figure carried over from another machine or another day.
duration_ms=0
while IFS=$'\t' read -r _ d; do
  duration_ms=$(( duration_ms + d ))
done < <(aid_durations_by_suite "$TESTS_DIR")

# An ownerless overdue entry escalates the night it crosses the deadline and
# then once a week — not every single night. A daily repeat of the same
# sentence is how a channel gets muted, which costs the streak counting its
# whole point.
# Selected ONCE. Counting the set with one filter and printing it with a second
# copy of the same filter is how a message stops matching the count that decided
# to send it.
escalating_json="$(jq -c --argjson limit "$ESCALATE_DAYS" \
  '[.[] | select(.owner == "" and .age_days >= $limit
                 and ((.age_days - $limit) % 7 == 0))]' <<<"$quarantined_json")"
escalating="$(jq 'length' <<<"$escalating_json")"
new_failures="$(jq '[.[] | select(.known | not)] | length' <<<"$failed_json")"

# A message that was never delivered leaves the failure "known" but UNREPORTED.
# Without this, a red night that coincided with a broken Telegram token stays
# silent forever afterwards, because every later night sees a known failure.
prev_undelivered=false
if [[ -f "$LATEST" ]] \
   && [[ "$(jq -r '.notified' "$LATEST" 2>/dev/null)" == "false" ]] \
   && [[ "$(jq -r '.failed | length' "$LATEST" 2>/dev/null)" != "0" ]]; then
  prev_undelivered=true
fi

# ─── Merge-path budgets ─────────────────────────────────────────────────────
# The gap nobody was watching. Between 2026-08-11 and 08-14 the merge path grew
# from 42 suites / 13 min to 72 / 18 min, both tiers over budget — every new
# suite correctly tagged, every one lint-clean, and no surface anywhere looking
# at the SUM. The standard demanded budgets; enforcement was a one-off campaign
# nobody re-ran. This is that surface.
#
# It REPORTS and never fails the job: an over-budget tier is not a broken test,
# and a gate that stops work over it gets routed around (the lesson the
# quarantined advisory gate already taught this project).
budget_json='null'
_over_budget=""
if [[ "$T0_SECONDS" =~ ^[0-9]+$ || "$T1_SECONDS" =~ ^[0-9]+$ ]]; then
  _t0="${T0_SECONDS:-null}"; [[ "$_t0" =~ ^[0-9]+$ ]] || _t0=null
  _t1="${T1_SECONDS:-null}"; [[ "$_t1" =~ ^[0-9]+$ ]] || _t1=null
  budget_json="$(jq -nc --argjson t0 "$_t0" --argjson t1 "$_t1" \
                       --argjson t0b "$T0_BUDGET_S" --argjson t1b "$T1_BUDGET_S" \
    '{t0_seconds:$t0, t0_budget_s:$t0b, t0_over:(($t0//0) > $t0b),
      t1_seconds:$t1, t1_budget_s:$t1b, t1_over:(($t1//0) > $t1b),
      merge_path_seconds:(($t0//0)+($t1//0)),
      merge_path_budget_s:$t1b,
      merge_path_over:((($t0//0)+($t1//0)) > $t1b)}')"
  [[ "$_t0" != null && "$_t0" -gt "$T0_BUDGET_S" ]] && \
    _over_budget="${_over_budget}T0 ${_t0}s (rozpočet ${T0_BUDGET_S}s); "
  [[ "$_t1" != null && "$_t1" -gt "$T1_BUDGET_S" ]] && \
    _over_budget="${_over_budget}T1 ${_t1}s (rozpočet ${T1_BUDGET_S}s); "
else
  # Not measured is NOT within budget. Say so, the way the runner watchdog does.
  echo "aid-nightly-report: tier durations were not supplied — the merge-path budget check DID NOT RUN (this is not a pass)." >&2
fi

# ─── The artifact, written BEFORE anything is sent ──────────────────────────
write_artifact() {
  jq -n --arg date "$TODAY" --argjson suites_run "$suites_run" \
        --argjson passed "$suites_passed" --argjson failed "$failed_json" \
        --argjson flaky "$flaky_json" --argjson quarantined "$quarantined_json" \
        --argjson duration_ms "$duration_ms" --arg log_url "$LOG_URL" \
        --argjson exit_code "$EXIT_CODE" --argjson censored "$censored" \
        --argjson notified "$1" --argjson quarantine_unreadable "$quarantine_unreadable" \
        --argjson quarantine_write_failed "$quarantine_write_failed" \
        --argjson merge_path_budget "$budget_json" \
    '{date:$date, suites_run:$suites_run, passed:$passed, failed:$failed,
      merge_path_budget:$merge_path_budget,
      flaky:$flaky, quarantined:$quarantined, duration_ms:$duration_ms,
      exit_code:$exit_code, censored:$censored, log_url:$log_url,
      quarantine_unreadable:$quarantine_unreadable,
      quarantine_write_failed:$quarantine_write_failed,
      notified:$notified}' > "$ARTIFACT" || return 1
  cp "$ARTIFACT" "$LATEST" || return 1
}
write_artifact false || { echo "aid-nightly-report: could not write '$ARTIFACT'" >&2; exit 2; }

# ─── One message, only when there is something new to say ───────────────────
notified=false
# An over-budget merge path is a reason to speak, alongside a new failure: it
# is the signal that was missing while the path grew from 13 to 18 minutes
# unnoticed. It is deduplicated with everything else — the same fingerprint
# rules — so a budget that stays over does not become nightly noise.
if [[ "$NOTIFY" -eq 1 ]] \
   && { [[ "$new_failures" -gt 0 ]] || [[ "$escalating" -gt 0 ]] \
        || [[ -n "$_over_budget" ]] || [[ "$prev_undelivered" == "true" ]]; }; then
  msg="$(printf 'AID nightly %s: %s failed, %s flaky, %s quarantined\n' \
    "$TODAY" "$(jq 'length' <<<"$failed_json")" "$(jq 'length' <<<"$flaky_json")" \
    "$(jq 'length' <<<"$quarantined_json")")"
  msg+="$(jq -r '.[] | "  - \(.suite)\(if .streak > 1 then " — \(.streak). night in a row" else "" end)"' <<<"$failed_json")"
  if [[ "$escalating" -gt 0 ]]; then
    msg+=$'\n'"$(jq -r '.[] | "  ! quarantined \(.age_days)d with no owner: \(.suite)"' \
      <<<"$escalating_json")"
  fi
  [[ "$quarantine_unreadable" == "true" ]] && msg+=$'\n'"  ! the quarantine record is unreadable"
  [[ -n "$_over_budget" ]] && msg+=$'\n'"  ! merge cesta pres rozpocet: ${_over_budget%; }"
  [[ -n "$LOG_URL" ]] && msg+=$'\n'"$LOG_URL"

  if [[ -f "$TELEGRAM_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$TELEGRAM_LIB"
    if send_telegram_alert "$msg"; then
      notified=true
    else
      # rc 2 is "credentials not configured" — a silent skip by contract. The
      # miss is recorded in the artifact rather than swallowed.
      echo "aid-nightly-report: the alert was not delivered; the result is still in $ARTIFACT" >&2
    fi
  else
    echo "aid-nightly-report: no Telegram helper at '$TELEGRAM_LIB' — the result is still in $ARTIFACT" >&2
  fi
  write_artifact "$notified" || exit 2
fi

echo "aid-nightly-report: $ARTIFACT ($(jq 'length' <<<"$failed_json") failed, $(jq 'length' <<<"$flaky_json") flaky, notified=$notified)"

# ─── Once a month, what could go ─────────────────────────────────────────────
# Attached to the report rather than mailed separately: the reaper's list is a
# proposal a PM reads beside the night's result, and a separate channel is a
# channel that gets muted. It proposes only — nothing here deletes anything.
# ONE caller. The nightly workflow briefly had a step of its own gated on the
# same date, so on the 1st the reaper ran twice and wrote its artifact twice.
# The list belongs here, beside the night's result — a proposal in a separate
# channel is a channel that gets muted.
if [[ "$(date -u +%d)" == "01" ]]; then
  echo ""
  bash "$SCRIPT_DIR/aid-test-reaper.sh" --dir "$NIGHTLY_DIR" --tests-dir "$TESTS_DIR" || true
fi
exit 0
