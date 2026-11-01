#!/usr/bin/env bash
# =============================================================================
# aid-companion.sh — the visual companion as a ready-made kit. The agent writes
# the variants (real code in a copy of the app) and three data files; this does
# everything else. One directory per plan: <state root>/.aid-o/work/companion/<P>/.
#
#   up       start the companion server for the plan (slot 3930-3949, reachable
#            over the VPN), or reuse its own running one from the same plugin
#            version; prints the PM's address
#   proto    copy ui.dir into <P>/proto (outside the repo), start ui.dev_cmd on a
#            free loopback port in its own process group, wait for ui.ready_path
#   shots    capture every shot of <P>/shots.json on every viewport the project
#            owes, over <P>/mocks.json; fails on an API call without a mock
#   show     check <P>/navrh.json, build navrh-<kolo>.html from the fixed template,
#            check the page itself (fits, controls reachable, images present),
#            write proposal.json; prints the PM's address
#   answers  the PM's latest choices and notes for a round (--kolo N, --history)
#   down     stop this plan's server and its verified prototype group
#
# Usage: aid-companion.sh <step> --plan <P> [--project-dir <root>] [step options]
# answers.jsonl is the agent's input, never proof of a PM choice (anyone with
# the file can write it); a gate stands on the PM card (aid_pm_card_check).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$PLUGIN_ROOT/lib/brainstorm-server"
VERSION="$(jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo unknown)"
# shellcheck source=lib/aid-roots.sh
source "$SCRIPT_DIR/lib/aid-roots.sh"

die() { echo "aid-companion: $*" >&2; exit 1; }

step="${1:-}"; [[ -n "$step" ]] || die "usage: aid-companion.sh up|proto|shots|show|answers|down --plan <P> [--project-dir <root>]"
shift
PLAN=""; PROJECT=""; KOLO=""; HISTORY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; PLAN="${2:-}"; shift 2 ;;
    --project-dir) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; PROJECT="${2:-}"; shift 2 ;;
    --kolo) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; KOLO="${2:-}"; shift 2 ;;
    --history) HISTORY=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$PLAN" =~ ^P[0-9]+$ ]] || die "--plan <P> is required and looks like P110 (got '${PLAN}')"
PROJECT="$(cd "${PROJECT:-.}" && git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository; pass --project-dir <project root>"
ROOT="$(aid_state_root "$PROJECT")" || die "no AID state root for ${PROJECT}"
DIR="$ROOT/.aid-o/work/companion/$PLAN"
mkdir -p "$DIR"
export AID_COMPANION_DIR="$DIR" AID_COMPANION_PLAN="$PLAN" AID_COMPANION_PROJECT="$PROJECT" AID_COMPANION_STATE="$ROOT" AID_PLUGIN_ROOT="$PLUGIN_ROOT"

# start time = field 22 of /proc/<pid>/stat, counted AFTER the name in parentheses: the name may hold spaces
# (`npm exec vite`), so a plain field count reads the wrong field (as kit-proto.mjs does: split at ") ")
_starttime() { [[ "$1" =~ ^[0-9]+$ ]] || return 1; sed -E 's/^.*\) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }
# pid alive and still the process we started
_alive_as() {  # <pid> <starttime> <cmd substring>
  local pid="$1" st="$2" want="$3"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/stat" && "$(_starttime "$pid")" == "$st" ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$want"
}

url_host() {
  if [[ -n "${AID_COMPANION_URL_HOST:-}" ]]; then printf '%s' "$AID_COMPANION_URL_HOST"; return; fi
  local ip; ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -vE '^(127\.|::1|$|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -1)"
  printf '%s' "${ip:-localhost}"
}

cmd_up() {
  local rec="$DIR/server.json" pid st ver port
  if [[ -s "$rec" ]]; then
    read -r pid st ver port < <(jq -r '[.pid, .starttime, .version, .port] | map(tostring) | join(" ")' "$rec")
    if _alive_as "$pid" "$st" "$SERVER_DIR/index.js" || _alive_as "$pid" "$st" "index.js"; then
      if [[ "$ver" == "$VERSION" ]]; then
        jq -c '. + {reused: true}' "$rec"; return 0
      fi
      kill "$pid" 2>/dev/null || true
      echo "aid-companion: stopped the server of plugin ${ver}; starting ${VERSION}" >&2
    fi
  fi
  local out host; host="$(url_host)"
  # AID_COMPANION_BIND=127.0.0.1 (tests): a loopback server on a random port, never a VPN slot a PM uses
  out="$(bash "$SERVER_DIR/start-server.sh" --project-dir "$ROOT" --plan "$PLAN" --kit --screen-dir "$DIR" \
           --host "${AID_COMPANION_BIND:-0.0.0.0}" --url-host "$host")" || true
  jq -e '.type == "server-started"' >/dev/null 2>&1 <<< "$out" || die "the server did not start: ${out}"
  pid="$(cat "$DIR/.server.pid")"
  jq -c --arg v "$VERSION" --argjson pid "$pid" --arg st "$(_starttime "$pid")" \
     '{type, url, port, screen_dir, pid: $pid, starttime: $st, version: $v, reused: false}' <<< "$out" | tee "$rec"
}

cmd_down() {
  local rec="$DIR/server.json" p="$DIR/proto.json" pid st pg
  if [[ -s "$rec" ]]; then
    read -r pid st < <(jq -r '[.pid, .starttime] | map(tostring) | join(" ")' "$rec")
    if _alive_as "$pid" "$st" "index.js"; then kill "$pid" && echo "server ${pid} stopped"
    else echo "server: not running as recorded (pid ${pid}) — nothing stopped"; fi
    rm -f "$rec"
  fi
  if [[ -s "$p" ]]; then
    local port; read -r pid st pg port < <(jq -r '[.pid, .starttime, .pgid, .port] | map(tostring) | join(" ")' "$p")
    if _proto_ours "$pid" "$st" "$pg"; then
      _stop_group "$pid" "$st" "$pg" "$port" || return 1
      echo "prototype group ${pg} stopped"
    else
      echo "prototype: the recorded process (pid ${pid}, group ${pg}) is not the one we started — nothing stopped"
      # the record goes only when nothing of it is left: no member of the group, the port closed
      local left; left="$(_group_or_port_alive "$pg" "$port")" || {
        echo "prototype: ${left:-cannot tell whether group ${pg} or port ${port} is still in use} — the record stays in ${p}; stop it by hand" >&2; return 1; }
    fi
    rm -f "$p"
  fi
}

# the prototype is the group the kit spawned: its leader (pgid == pid, both > 1) with the recorded start time. Not the
# program's name: `npx vite` runs as `npm exec vite` (WAN P119 31. 10. 2026: down stopped nothing).
_proto_ours() {  # <pid> <starttime> <pgid>
  local pid="$1" st="$2" pg="$3"
  [[ "$pid" =~ ^[0-9]+$ && "$pg" =~ ^[0-9]+$ ]] && (( pid > 1 && pg == pid )) || return 1
  [[ -r "/proc/$pid/stat" && "$(_starttime "$pid")" == "$st" ]] || return 1
  [[ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" == "$pg" ]]
}
# "" (and 0) when group <pgid> has no member and <port> is closed; else 1 with what is left, or why it cannot tell
_group_or_port_alive() {  # <pgid> <port>
  local pg="$1" port="$2" rc=0 out
  [[ "$pg" =~ ^[0-9]+$ && "$port" =~ ^[0-9]+$ ]] || { echo "the record names no valid group or port"; return 1; }
  out="$(pgrep -g "$pg" 2>/dev/null)" || rc=$?
  (( rc == 0 )) && { echo "group ${pg} still has processes ($(tr '\n' ' ' <<< "$out"))"; return 1; }
  (( rc == 1 )) || { echo "pgrep failed (exit ${rc})"; return 1; }
  rc=0; out="$(ss -ltnH "sport = :$port" 2>/dev/null)" || rc=$?
  (( rc == 0 )) || { echo "ss failed (exit ${rc})"; return 1; }
  [[ -z "$out" ]] || { echo "port ${port} is still open"; return 1; }
}
# TERM to the group, up to 5 s for it to empty, then KILL; done only when the group is gone and its port closed.
# A signal goes only to a group that still has members: while one lives, the kernel keeps the group's number, so it
# cannot be another group's; with the leader alive its start time is checked again right before each signal.
# ponytail: a group that empties and is reborn under the same number between pgrep and kill is not excluded (bash
# has no pidfd); the window is microseconds on a number the kernel just freed.
_signal_group() {  # <sig> <pid> <starttime> <pgid>
  local sig="$1" pid="$2" st="$3" pg="$4"
  pgrep -g "$pg" >/dev/null 2>&1 || return 0
  if [[ -e "/proc/$pid" ]]; then [[ "$(_starttime "$pid")" == "$st" ]] || return 1; fi
  kill "-$sig" -- "-$pg" 2>/dev/null || true
}
_stop_group() {  # <pid> <starttime> <pgid> <port>
  local pid="$1" st="$2" pg="$3" port="$4" i left
  _signal_group TERM "$pid" "$st" "$pg" || { echo "prototype: the leader ${pid} changed under us — nothing more signalled" >&2; return 1; }
  for i in $(seq 50); do pgrep -g "$pg" >/dev/null 2>&1 || break; sleep 0.1; done
  if pgrep -g "$pg" >/dev/null 2>&1; then
    _signal_group KILL "$pid" "$st" "$pg" || { echo "prototype: the leader ${pid} changed under us — nothing more signalled" >&2; return 1; }
    for i in $(seq 20); do pgrep -g "$pg" >/dev/null 2>&1 || break; sleep 0.1; done
  fi
  left="$(_group_or_port_alive "$pg" "$port")" || {
    echo "prototype: ${left} after TERM and KILL — the record stays in ${DIR}/proto.json; stop it by hand" >&2; return 1; }
}

cmd_answers() {
  local f="$DIR/answers.jsonl"
  [[ -s "$f" ]] || { echo "no answers yet (${f})"; return 0; }
  local k="${KOLO:-$(jq -s 'map(.kolo // 0) | max' "$f")}"
  if (( HISTORY )); then   # every event of every round; --kolo narrows it to one
    if [[ -n "$KOLO" ]]; then jq -c --argjson k "$k" 'select((.kolo // 0) == $k)' "$f"; else cat "$f"; fi; return 0
  fi
  jq -s --argjson k "$k" '
    map(select((.kolo // 0) == $k)) as $e
    | { kolo: $k,
        volby: ($e | map(select(.type == "choice")) | group_by(.bod) | map({(.[-1].bod | tostring): .[-1].volba}) | add // {}),
        poznamky: ($e | map(select(.type == "note")) | group_by(.bod) | map({(.[-1].bod | tostring): .[-1].text}) | add // {}),
        odeslano: ($e | map(select(.type == "confirm")) | last // null),
        upozorneni: "podklad pro agenta, ne důkaz volby PM" }' "$f"
}

# the node steps: the project's viewports and `ui` settings, and the browser tools of lib/ui-fidelity
# (installed once, pinned by its lockfile, under the same lock and marker as aid-ui-tool.sh)
node_step() {
  local cfg="$ROOT/.aid-o/config/project.yaml" lib="$PLUGIN_ROOT/lib/ui-fidelity" want marker
  AID_COMPANION_UI="$( [[ -f "$cfg" ]] && yq -o=json '.ui // {}' "$cfg" 2>/dev/null || echo '{}')"
  AID_COMPANION_VIEWPORTS="desktop 1280 720"
  [[ "$(jq -r '.responsive // true' <<< "$AID_COMPANION_UI")" == false ]] || AID_COMPANION_VIEWPORTS+=",mobile 390 844"
  export AID_COMPANION_UI AID_COMPANION_VIEWPORTS
  marker="$lib/node_modules/.aid-installed"; want="$(sha256sum "$lib/package-lock.json" | cut -d' ' -f1)"
  exec 9>"$lib/.aid-install.lock"; flock 9
  if [[ ! -f "$marker" || "$(cat "$marker")" != "$want" ]]; then
    echo "aid-companion: installing the browser tools in $lib (npm ci, once)" >&2
    (cd "$lib" && npm ci --no-audit --no-fund >&2) || { rm -rf "$lib/node_modules"; die "npm ci failed in $lib"; }
    printf '%s\n' "$want" > "$marker"
  fi
  flock -u 9; exec 9>&-
  [[ -n "${CHROME:-}" ]] || CHROME="$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort -V | tail -1 || true)"
  export CHROME
  exec node "$SERVER_DIR/kit.mjs" "$1"
}

case "$step" in
  up) cmd_up ;;
  down) cmd_down ;;
  answers) cmd_answers ;;
  proto|shots|show) node_step "$step" ;;
  *) die "unknown step '${step}' (up|proto|shots|show|answers|down)" ;;
esac
