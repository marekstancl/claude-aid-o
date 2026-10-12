#!/bin/bash
# Stop the brainstorm server and clean up
# Usage: stop-server.sh <screen_dir>
#
# Kills the server process. Only deletes session directory if it's
# under /tmp (ephemeral). Persistent directories (.superpowers/) are
# kept so mockups can be reviewed later.

SCREEN_DIR="$1"

# --list [--project-dir <root>] (2.114.0): every running companion of this
# plugin (or of one project): pid, port, plan, project, screen_dir, age, kept —
# one JSON line each — so "co mi běží?" has an answer and a specific one can
# be stopped by its screen_dir.
if [[ "$SCREEN_DIR" == "--list" ]]; then
  shift; ROOT=""
  while [[ $# -gt 0 ]]; do case "$1" in --project-dir) ROOT="$2"; shift 2 ;; *) echo "{\"error\": \"Unknown argument: $1\"}"; exit 1 ;; esac; done
  for pid in $(pgrep -f 'node index.js' 2>/dev/null); do
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"; [[ "$cwd" == */brainstorm-server ]] || continue
    env_of() { tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n "s/^$1=//p" | head -1; }
    sdir="$(env_of BRAINSTORM_DIR)"; [[ -z "$ROOT" || "$sdir" == "$ROOT"/* ]] || continue
    port="$(ss -ltnp 2>/dev/null | grep "pid=$pid," | grep -oE ':[0-9]+ ' | head -1 | tr -d ': ')"
    kept=false; [[ -f "$sdir/.keep" ]] && kept=true
    jq -nc --argjson pid "$pid" --arg port "${port:-?}" --arg plan "$(env_of BRAINSTORM_PLAN)" --arg proj "$(env_of BRAINSTORM_PROJECT)" \
       --arg sdir "$sdir" --arg age "$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')" --argjson kept "$kept" --arg url "http://$(env_of BRAINSTORM_URL_HOST):${port:-?}" \
       '{pid: $pid, port: $port, plan: (if $plan == "" then null else $plan end), project: (if $proj == "" then null else $proj end), url: $url, screen_dir: $sdir, running: $age, kept: $kept}'
  done
  exit 0
fi

# --stale [hours] --project-dir <root> (2.114.0): stop the forgotten companions
# of ONE project — a .server.pid under <root>/.aid-o/work/companion/*/ whose
# process is older than N hours (default 24) AND is a `node index.js` of a
# brainstorm-server directory (this plugin or its installed cache). Nothing else
# is ever killed; a PID the file names that runs something else is left and
# named. On eco-dev twelve companions ran 1–48 days and held the AID ports.
if [[ "$SCREEN_DIR" == "--stale" ]]; then
  shift; HOURS=24; ROOT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-dir) ROOT="$2"; shift 2 ;;
      [0-9]*) HOURS="$1"; shift ;;
      *) echo "{\"error\": \"Unknown argument: $1\"}"; exit 1 ;;
    esac
  done
  [[ -n "$ROOT" && -d "$ROOT" ]] || { echo '{"error": "Usage: stop-server.sh --stale [hours] --project-dir <project root>"}'; exit 1; }
  stopped=0; skipped=""
  for pf in "$ROOT"/.aid-o/work/companion/*/.server.pid; do
    [[ -f "$pf" ]] || continue
    pid="$(cat "$pf" 2>/dev/null)"; [[ "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null || { rm -f "$pf"; continue; }
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"; cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"
    if [[ "$cmd" != *"node index.js"* || "$cwd" != */brainstorm-server ]]; then skipped="${skipped}${pid} (${cmd%% *} in ${cwd}); "; continue; fi
    age_s="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"; [[ "$age_s" =~ ^[0-9]+$ ]] || continue
    (( age_s >= HOURS * 3600 )) || continue
    # a kept companion (the PM pressed Držet) is left alone until the 60-day cap
    [[ -f "$(dirname "$pf")/.keep" ]] && (( age_s < 60 * 24 * 3600 )) && { skipped="${skipped}${pid} (kept by the PM, $(dirname "$pf")); "; continue; }
    kill "$pid" 2>/dev/null && { rm -f "$pf"; stopped=$((stopped + 1)); }
  done
  jq -nc --argjson n "$stopped" --argjson h "$HOURS" --arg s "${skipped% }" '{status: "stale-stopped", stopped: $n, older_than_hours: $h} + (if $s != "" then {left_running_not_a_companion: $s} else {} end)'
  exit 0
fi

if [[ -z "$SCREEN_DIR" ]]; then
  echo '{"error": "Usage: stop-server.sh <screen_dir> | --list [--project-dir <root>] | --stale [hours] --project-dir <root>"}'
  exit 1
fi

PID_FILE="${SCREEN_DIR}/.server.pid"

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE")
  kill "$pid" 2>/dev/null
  rm -f "$PID_FILE" "${SCREEN_DIR}/.server.log"

  # Only delete ephemeral /tmp directories
  if [[ "$SCREEN_DIR" == /tmp/* ]]; then
    rm -rf "$SCREEN_DIR"
  fi

  echo '{"status": "stopped"}'
else
  echo '{"status": "not_running"}'
fi
