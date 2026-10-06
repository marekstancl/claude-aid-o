#!/bin/bash
# Stop the brainstorm server and clean up
# Usage: stop-server.sh <screen_dir>
#
# Kills the server process. Only deletes session directory if it's
# under /tmp (ephemeral). Persistent directories (.superpowers/) are
# kept so mockups can be reviewed later.

SCREEN_DIR="$1"

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
    kill "$pid" 2>/dev/null && { rm -f "$pf"; stopped=$((stopped + 1)); }
  done
  jq -nc --argjson n "$stopped" --argjson h "$HOURS" --arg s "${skipped% }" '{status: "stale-stopped", stopped: $n, older_than_hours: $h} + (if $s != "" then {left_running_not_a_companion: $s} else {} end)'
  exit 0
fi

if [[ -z "$SCREEN_DIR" ]]; then
  echo '{"error": "Usage: stop-server.sh <screen_dir> | --stale [hours] --project-dir <root>"}'
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
