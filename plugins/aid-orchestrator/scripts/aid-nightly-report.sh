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
TELEGRAM_LIB="${AID_TELEGRAM_LIB:-/opt/eco/services/scripts/lib/telegram-notify.sh}"

RUNNER_LOG=""; EXIT_CODE=0; LOG_URL=""; TESTS_DIR=""; NOTIFY=1
NIGHTLY_DIR="${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runner-log) RUNNER_LOG="${2:-}"; shift 2 ;;
    --exit-code)  EXIT_CODE="${2:-0}"; shift 2 ;;
    --log-url)    LOG_URL="${2:-}"; shift 2 ;;
    --tests-dir)  TESTS_DIR="${2:-}"; shift 2 ;;
    --dir)        NIGHTLY_DIR="${2:-}"; shift 2 ;;
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
failed=(); flaky=()
for name in ${reported_failures[@]+"${reported_failures[@]}"}; do
  path="$(suite_path "$name")" || { failed+=("$name"); continue; }
  if [[ "$path" == *.bats ]]; then
    bats "$path" >/dev/null 2>&1 && retry_ok=1 || retry_ok=0
  else
    bash "$path" >/dev/null 2>&1 && retry_ok=1 || retry_ok=0
  fi
  if [[ "$retry_ok" -eq 1 ]]; then
    flaky+=("$name")
    bash "$QUARANTINE_SH" add "$name" "" >/dev/null 2>&1 || true
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
quarantined_json="$(bash "$QUARANTINE_SH" list --json 2>/dev/null || echo '[]')"

# The night's portfolio cost, summed from the durations the run itself just
# refreshed — never a figure carried over from another machine or another day.
duration_ms=0
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  d="$(aid_durations_latest "$(basename "$suite")" 2>/dev/null)" || continue
  duration_ms=$(( duration_ms + d ))
done < <(aid_test_discover_suites "$TESTS_DIR")

escalating="$(jq --argjson limit "${AID_QUARANTINE_ESCALATE_DAYS:-14}" \
  '[.[] | select(.owner == "" and .age_days >= $limit)] | length' <<<"$quarantined_json")"
new_failures="$(jq '[.[] | select(.known | not)] | length' <<<"$failed_json")"

# ─── The artifact, written BEFORE anything is sent ──────────────────────────
write_artifact() {
  jq -n --arg date "$TODAY" --argjson suites_run "$suites_run" \
        --argjson passed "$suites_passed" --argjson failed "$failed_json" \
        --argjson flaky "$flaky_json" --argjson quarantined "$quarantined_json" \
        --argjson duration_ms "$duration_ms" --arg log_url "$LOG_URL" \
        --argjson exit_code "$EXIT_CODE" --argjson censored "$censored" \
        --argjson notified "$1" \
    '{date:$date, suites_run:$suites_run, passed:$passed, failed:$failed,
      flaky:$flaky, quarantined:$quarantined, duration_ms:$duration_ms,
      exit_code:$exit_code, censored:$censored, log_url:$log_url,
      notified:$notified}' > "$ARTIFACT" || return 1
  cp "$ARTIFACT" "$LATEST"
}
write_artifact false || { echo "aid-nightly-report: could not write '$ARTIFACT'" >&2; exit 2; }

# ─── One message, only when there is something new to say ───────────────────
notified=false
if [[ "$NOTIFY" -eq 1 ]] && { [[ "$new_failures" -gt 0 ]] || [[ "$escalating" -gt 0 ]]; }; then
  msg="$(printf 'AID nightly %s: %s failed, %s flaky, %s quarantined\n' \
    "$TODAY" "$(jq 'length' <<<"$failed_json")" "$(jq 'length' <<<"$flaky_json")" \
    "$(jq 'length' <<<"$quarantined_json")")"
  msg+="$(jq -r '.[] | "  - \(.suite)\(if .streak > 1 then " — \(.streak). night in a row" else "" end)"' <<<"$failed_json")"
  if [[ "$escalating" -gt 0 ]]; then
    msg+=$'\n'"$(jq -r --argjson limit "${AID_QUARANTINE_ESCALATE_DAYS:-14}" \
      '.[] | select(.owner == "" and .age_days >= $limit) | "  ! quarantined \(.age_days)d with no owner: \(.suite)"' \
      <<<"$quarantined_json")"
  fi
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
if [[ "$(date -u +%d)" == "01" ]]; then
  echo ""
  bash "$SCRIPT_DIR/aid-test-reaper.sh" --dir "$NIGHTLY_DIR" --tests-dir "$TESTS_DIR" \
    ${AID_CONTENT_SCAN:+--content-scan "$AID_CONTENT_SCAN"} || true
fi
exit 0
