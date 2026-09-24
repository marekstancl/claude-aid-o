#!/usr/bin/env bash
# =============================================================================
# aid-ui-serve.sh — make Impeccable's decision page and the /aid-ui brand page
# reachable from the PM's laptop over the VPN.
#
#   forward <local-port>   socat AID_UI_HOST:AID_UI_FORWARD_PORT -> 127.0.0.1:<local-port>
#   brand <dir>            python3 -m http.server on AID_UI_HOST:AID_UI_BRAND_PORT
#                          (idempotent: alive and answering -> print URL, exit 0)
#   stop <forward|brand>   cancel that role's job; no job of ours -> exit 0
#
# Both servers run as `aid-job.sh` jobs (the plugin's one process owner), so a
# stop cancels exactly that job's process group and nothing else. The job id
# is fixed (aid-ui-<role>-<port>); an old job dir under it is cancelled and
# moved aside as <id>.superseded-<epoch> before every start (the pattern of
# aid-run-gates.sh).
#
# <project> = $AID_UI_PROJECT, else $PWD. Jobs dir = $AID_UI_JOBS_DIR, else
# <project>/.aid-ui/jobs.
# Env: AID_UI_HOST (10.20.20.22), AID_UI_FORWARD_PORT (3915), AID_UI_BRAND_PORT (3916).
# Output: URL: <url> and JOB: <id>.
# Exit: 0 ok, 1 port in use / start failure, 2 usage.
# =============================================================================
set -euo pipefail

JOB_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aid-job.sh"
HOST="${AID_UI_HOST:-10.20.20.22}"
FWD_PORT="${AID_UI_FORWARD_PORT:-3915}"
BRAND_PORT="${AID_UI_BRAND_PORT:-3916}"
PROJECT="${AID_UI_PROJECT:-$PWD}"
JOBS="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}"
DEADLINE=28800   # 8 h, integer seconds as `aid-job.sh run --deadline` requires

usage() { echo "usage: aid-ui-serve.sh forward <local-port> | brand <dir> | stop <forward|brand>" >&2; exit 2; }
die() { echo "ERROR: aid-ui-serve.sh: $1" >&2; exit 1; }

port_of() { [[ "$1" == forward ]] && echo "$FWD_PORT" || echo "$BRAND_PORT"; }
job_id() { echo "aid-ui-$1-$(port_of "$1")"; }
listening() { [[ -n "$(ss -ltnH "sport = :$1" 2>/dev/null)" ]]; }
alive() {   # our job dir exists and its process is still running
  [[ -f "$JOBS/$1/job.json" ]] || return 1
  local st; st="$(bash "$JOB_SH" status --jobs-dir "$JOBS" --id "$1" 2>/dev/null)" || return 1
  [[ "$st" == running || "$st" == started ]]
}

supersede() {
  local id="$1" dir="$JOBS/$1"
  [[ -d "$dir" ]] || return 0
  if alive "$id"; then
    bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null \
      || die "old job $id could not be stopped; refusing to start a second copy"
  fi
  mv "$dir" "$dir.superseded-$(date -u +%s)" || die "could not move aside $dir"
}

start() {   # start <role> <cmd...>
  local role="$1" port; shift
  port="$(port_of "$role")"
  local id; id="$(job_id "$role")"
  supersede "$id"
  if listening "$port"; then
    die "port $port in use by: $(ss -ltnpH "sport = :$port" | tr -s ' ')"
  fi
  mkdir -p "$JOBS"
  local out
  out="$(bash "$JOB_SH" run --jobs-dir "$JOBS" --id "$id" --label "aid-ui $role" \
    --repo "$PROJECT" --deadline "$DEADLINE" -- "$@" 2>&1)" || die "aid-job.sh run failed: $out"
  local i
  for i in $(seq 1 50); do
    listening "$port" && { echo "URL: http://$HOST:$port/"; echo "JOB: $id"; return 0; }
    alive "$id" || break
    sleep 0.1
  done
  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null 2>&1 || true
  die "$role server did not start on $HOST:$port: $(tail -n 5 "$JOBS/$id/stdout.log" 2>/dev/null)"
}

[[ $# -eq 2 ]] || usage
case "$1" in
  forward)
    [[ "$2" =~ ^[0-9]+$ ]] || usage
    start forward socat "TCP-LISTEN:$FWD_PORT,bind=$HOST,reuseaddr,fork" "TCP:127.0.0.1:$2"
    ;;
  brand)
    [[ -d "$2" ]] || usage
    id="$(job_id brand)"
    if alive "$id" && listening "$BRAND_PORT"; then
      echo "URL: http://$HOST:$BRAND_PORT/"; echo "JOB: $id"; exit 0
    fi
    start brand python3 -m http.server "$BRAND_PORT" --bind "$HOST" --directory "$(cd "$2" && pwd)"
    ;;
  stop)
    [[ "$2" == forward || "$2" == brand ]] || usage
    id="$(job_id "$2")"
    [[ -f "$JOBS/$id/job.json" ]] || exit 0
    bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null || die "cancel of $id failed"
    ;;
  *) usage ;;
esac
