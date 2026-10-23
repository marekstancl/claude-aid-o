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
    --plan) PLAN="${2:-}"; shift 2 ;;
    --project-dir) PROJECT="${2:-}"; shift 2 ;;
    --kolo) KOLO="${2:-}"; shift 2 ;;
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

# pid alive and still the process we started (start time from /proc/<pid>/stat field 22)
_alive_as() {  # <pid> <starttime> <cmd substring>
  local pid="$1" st="$2" want="$3" now
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/stat" ]] || return 1
  now="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)"
  [[ "$now" == "$st" ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "$want"
}
_starttime() { awk '{print $22}' "/proc/$1/stat" 2>/dev/null; }

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
    local cmd; cmd="$(jq -r '.cmd // ""' "$p")"
    read -r pid st pg < <(jq -r '[.pid, .starttime, .pgid] | map(tostring) | join(" ")' "$p")
    if _alive_as "$pid" "$st" "$cmd" && [[ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" == "$pg" ]]; then
      kill -- "-$pg" && echo "prototype group ${pg} stopped"
    else echo "prototype: the recorded process (pid ${pid}, group ${pg}) is not the one we started — nothing stopped"; fi
    rm -f "$p"
  fi
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
