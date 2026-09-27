#!/usr/bin/env bash
# =============================================================================
# aid-ui-serve.sh — make the /aid-ui studio page and the brand page
# reachable from the PM's laptop over the VPN.
#
#   studio <project>       the studio page (../lib/aid-ui-studio/server.py) on
#                          AID_UI_HOST:AID_UI_STUDIO_PORT for <project>; writes a
#                          fresh token to <project>/.aid-ui/studio.token before the
#                          start (the server embeds it in the page and asks it of
#                          every POST and GET /answer). Idempotent: our job alive,
#                          answering and serving the same (realpath) project -> print
#                          URL, exit 0 and keep the token (a restart would forget the
#                          unrecorded answers held in the server's memory).
#   brand <dir>            python3 -m http.server on AID_UI_HOST:AID_UI_BRAND_PORT
#                          only for a brand page dir: realpath ends in /docs/brand
#                          and it has index.html and tokens.css; refused when it
#                          holds anything but index.html, top-level *.css,
#                          assets/ and fonts/ (state.json, *.tmp, mktemp leftovers
#                          *.XXXXXX are named as internal);
#                          idempotent: our job alive, answering and serving the
#                          same (realpath) dir -> print URL, exit 0; else restart.
#   stop <studio|brand>    cancel that role's job, found under <jobs> or else
#                          through the pointer $STATE_DIR/<id> that start writes
#                          (line 1 jobs dir, line 2 project root). Pointer use:
#                          a known project ($AID_UI_PROJECT, else the git root of
#                          $PWD) other than the pointer's -> exit 1 naming both,
#                          nothing stopped; no known project -> stops it and
#                          prints whose server it was; no job of ours -> exit 0
#
# Both servers run as `aid-job.sh` jobs (the plugin's one process owner), so a
# stop cancels exactly that job's process group and nothing else. The job id
# is fixed (aid-ui-<role>-<port>); an old job dir under it is cancelled and
# moved aside as <id>.superseded-<epoch> before every start (the pattern of
# aid-run-gates.sh).
#
# <project> = $AID_UI_PROJECT, else $PWD. Jobs dir = $AID_UI_JOBS_DIR, else
# <project>/.aid-ui/jobs. Pointer dir = $AID_UI_STATE_DIR, else ~/.cache/aid-ui
# (one file per job id = per port: jobs dir and project of the job started last).
# Env: AID_UI_HOST (10.20.20.22), AID_UI_STUDIO_PORT (3915), AID_UI_BRAND_PORT (3916).
# Output: URL: <url> and JOB: <id>.
# Exit: 0 ok, 1 port in use / start failure, 2 usage or refused target.
# =============================================================================
set -euo pipefail

JOB_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aid-job.sh"
HOST="${AID_UI_HOST:-10.20.20.22}"
STUDIO_PORT="${AID_UI_STUDIO_PORT:-3915}"
STUDIO_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib/aid-ui-studio" && pwd)/server.py"
BRAND_PORT="${AID_UI_BRAND_PORT:-3916}"
PROJECT="${AID_UI_PROJECT:-$PWD}"
JOBS="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}"
STATE_DIR="${AID_UI_STATE_DIR:-$HOME/.cache/aid-ui}"
DEADLINE=28800   # 8 h, integer seconds as `aid-job.sh run --deadline` requires

usage() { echo "usage: aid-ui-serve.sh studio <project> | brand <dir> | stop <studio|brand>" >&2; exit 2; }
die() { echo "ERROR: aid-ui-serve.sh: $1" >&2; exit 1; }
refuse() { echo "ERROR: aid-ui-serve.sh: $1" >&2; exit 2; }

port_of() { [[ "$1" == studio ]] && echo "$STUDIO_PORT" || echo "$BRAND_PORT"; }
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
  mkdir -p "$JOBS" "$STATE_DIR"
  printf '%s\n%s\n' "$(realpath "$JOBS")" "$(realpath "$PROJECT")" > "$STATE_DIR/$id"
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
  studio)
    dir="$(realpath -e "$2" 2>/dev/null || true)"
    [[ -d "$dir" ]] || refuse "$2 is not a project directory"
    PROJECT="$dir"; JOBS="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}"
    id="$(job_id studio)"
    if alive "$id" && listening "$STUDIO_PORT" \
       && [[ "$(jq -r '.command as $c | $c[($c | index("--project")) + 1]' "$JOBS/$id/job.json")" == "$dir" ]]; then
      echo "URL: http://$HOST:$STUDIO_PORT/"; echo "JOB: $id"; exit 0
    fi
    mkdir -p "$dir/.aid-ui"
    tok="$dir/.aid-ui/studio.token"
    (umask 077; od -An -tx1 -N16 /dev/urandom | tr -d ' \n' > "$tok")
    start studio python3 "$STUDIO_PY" --project "$dir" --host "$HOST" --port "$STUDIO_PORT" --token-file "$tok"
    ;;
  brand)
    dir="$(realpath -e "$2" 2>/dev/null || true)"
    [[ "$dir" == */docs/brand && -f "$dir/index.html" && -f "$dir/tokens.css" ]] \
      || refuse "$2 is not a brand page (needs <project>/docs/brand with index.html and tokens.css); refusing to serve it"
    l="$(find "$dir" -mindepth 1 -type l -printf '%P' -quit)"
    [[ -z "$l" ]] || refuse "$dir/$l is a symlink; the brand page serves no symlinks (it could point outside docs/brand)"
    while IFS= read -r -d '' f; do
      case "$f" in
        state.json|*/state.json|*.tmp|*.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;;
        index.html|assets/*|fonts/*) continue ;;
        */*) ;;
        *.css) continue ;;
      esac
      refuse "$dir/$f must not be served (state.json must not be served, nor anything internal; the brand page serves only index.html, *.css, assets/, fonts/)"
    done < <(find "$dir" -mindepth 1 ! -type d -printf '%P\0')
    id="$(job_id brand)"
    if alive "$id" && listening "$BRAND_PORT" && [[ "$(jq -r '.command[-1]' "$JOBS/$id/job.json")" == "$dir" ]]; then
      echo "URL: http://$HOST:$BRAND_PORT/"; echo "JOB: $id"; exit 0
    fi
    start brand python3 -m http.server "$BRAND_PORT" --bind "$HOST" --directory "$dir"
    ;;
  stop)
    [[ "$2" == studio || "$2" == brand ]] || usage
    id="$(job_id "$2")"
    jobs="$JOBS"
    if [[ ! -f "$jobs/$id/job.json" ]]; then
      { IFS= read -r jobs; IFS= read -r owner; } 2>/dev/null < "$STATE_DIR/$id" || true
      [[ -n "${jobs:-}" && -f "$jobs/$id/job.json" ]] || exit 0
      if [[ -n "${AID_UI_PROJECT:-}" ]]; then here="$(realpath -m "$AID_UI_PROJECT")"
      else here="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"; fi
      [[ -z "$here" || "$here" == "${owner:-}" ]] \
        || die "the $2 server on port $(port_of "$2") belongs to project ${owner:-<unknown>}, not $here; refusing to stop it (run stop from that project)"
    fi
    bash "$JOB_SH" cancel --jobs-dir "$jobs" --id "$id" >/dev/null || die "cancel of $id failed"
    [[ -z "${owner+x}" ]] || echo "stopped the $2 server of project ${owner:-<unknown>}"
    ;;
  *) usage ;;
esac
