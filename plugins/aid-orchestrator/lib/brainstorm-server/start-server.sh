#!/bin/bash
# Start the brainstorm server and output connection info
# Usage: start-server.sh [--project-dir <path> --plan <P-id>] [--host <bind-host>] [--url-host <display-host>]
#                        [--port <N>] [--foreground] [--background]
#
# Outputs one JSON line ({"type":"server-started", ...}) on success, {"error": ...} on refusal.
# Each session gets its own directory to avoid conflicts.
#
# Output: one JSON line. In --foreground the server's own server-started line is
# the output and the reachability check does not run (the server owns the
# terminal); the slot and range rules above apply before it starts.
#
# Options:
#   --project-dir <path>  Store session files under <path>/.aid-o/work/companion/
#                         instead of /tmp. Files persist after server stops.
#                         REQUIRES --plan (2.114.0): the companion of a brainstorm
#                         knows which run it serves.
#   --plan <P-id>         The brainstorm run (.aid-o/work/brainstorm/<id>/state.yaml).
#                         The run must say whether it is a screen of an existing
#                         application (topic_kind ui|other); a UI run must have its
#                         proposal basis built from the application (proposal.json,
#                         lib/aid-ui-proposal.sh) — the server then composes
#                         "today → proposal" over the real screenshot itself.
#   --host <bind-host>    Host/interface to bind (default: 127.0.0.1).
#                         Use 0.0.0.0 in remote/containerized environments.
#   --url-host <host>     Hostname shown in returned URL JSON.
#   --port <N>            Fixed port. Off loopback it must be in the AID range
#                         3900-3999 (the VPN passes it; a random high port does not —
#                         an operational fact of eco-dev, not a property of this code).
#                         Without --port, a non-loopback bind takes the first free
#                         companion slot (AID_COMPANION_PORTS, default "3910 3912");
#                         a loopback bind keeps a random high port.
#   --foreground          Run server in the current terminal (no backgrounding).
#   --background          Force background mode (overrides Codex auto-foreground).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse arguments
PROJECT_DIR=""
PLAN_ID=""
FOREGROUND="false"
FORCE_BACKGROUND="false"
BIND_HOST="127.0.0.1"
URL_HOST=""
PORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --plan)        PLAN_ID="$2"; shift 2 ;;
    --host)        BIND_HOST="$2"; shift 2 ;;
    --url-host)    URL_HOST="$2"; shift 2 ;;
    --port)        PORT="$2"; shift 2 ;;
    --foreground|--no-daemon) FOREGROUND="true"; shift ;;
    --background|--daemon)    FORCE_BACKGROUND="true"; shift ;;
    *) echo "{\"error\": \"Unknown argument: $1\"}"; exit 1 ;;
  esac
done

fail() { echo "{\"error\": $(printf '%s' "$1" | jq -Rs .)}"; exit 1; }

if [[ -z "$URL_HOST" ]]; then
  if [[ "$BIND_HOST" == "127.0.0.1" || "$BIND_HOST" == "localhost" ]]; then
    URL_HOST="localhost"
  else
    URL_HOST="$BIND_HOST"
  fi
fi

# ── the brainstorm run this companion serves (2.114.0) ───────────────────────
# A companion in a project is a companion of a brainstorm. The run says whether
# it is a screen of an existing application; "other" carries the PM's reason
# (the design page shows it). A UI run has its basis built from the application
# BEFORE anything is drawn — the server composes the page over it.
BASIS=""
if [[ -n "$PROJECT_DIR" ]]; then
  [[ -n "$PLAN_ID" ]] || fail "--project-dir needs --plan <P-id>: the companion of a brainstorm names its run (the standalone demo uses no --project-dir and lives in /tmp)"
  [[ "$PLAN_ID" =~ ^P[0-9]+$ ]] || fail "--plan must look like P108 (got '$PLAN_ID')"
  STATE_DIR="$PROJECT_DIR/.aid-o/work/brainstorm/$PLAN_ID"
  STATE="$STATE_DIR/state.yaml"
  [[ -r "$STATE" ]] || fail "no brainstorm run $PLAN_ID at $STATE — start it: aid-brainstorm-state.sh init $PLAN_ID --scope <scope> [--topic-kind ui|other]"
  TOPIC_KIND="$(sed -n 's/^topic_kind: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$STATE" | head -1)"
  if [[ -z "$TOPIC_KIND" ]]; then
    fail "$PLAN_ID does not say whether this is a screen of an existing application. Say it first: aid-brainstorm-state.sh topic-kind $PLAN_ID ui   (or: topic-kind $PLAN_ID other --reason \"<why no screen of the application is involved>\")"
  fi
  if [[ "$TOPIC_KIND" == "ui" ]]; then
    PROPOSAL="$STATE_DIR/proposal.json"
    # shellcheck source=../../scripts/lib/aid-ui-proposal.sh
    source "$PLUGIN_ROOT/scripts/lib/aid-ui-proposal.sh" || fail "cannot load $PLUGIN_ROOT/scripts/lib/aid-ui-proposal.sh"
    if ! basis_err="$(aid_ui_proposal_basis_check "$PROPOSAL" "$PROJECT_DIR" 2>&1)"; then
      fail "$PLAN_ID is a UI topic and has no proposal basis built from the application (${basis_err:-no proposal.json}). Build it first: source \$AID_PLUGIN_PATH/scripts/lib/aid-ui-proposal.sh && aid_ui_proposal_build $PROJECT_DIR $STATE_DIR --screen <url of the real screen> --fixture-data <mocks.json> --brief <brief.md>   — then start the companion again; it composes today → proposal over the real screenshot itself"
    fi
    BASIS="$PROPOSAL"
  fi
fi

# ── the port (2.114.0) ───────────────────────────────────────────────────────
port_busy() {  # <host> <port> — a listener answers
  local h="$1"; [[ "$h" == "0.0.0.0" || "$h" == "localhost" ]] && h="127.0.0.1"
  (exec 3<>"/dev/tcp/$h/$2") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}
port_holder() {  # <port> — who listens, for the refusal: pid, command, age, and the stop command when it is a companion
  local pid cmd age sdir out=""
  for pid in $(ss -ltnp "sport = :$1" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u); do
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-60)"; age="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
    sdir="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^BRAINSTORM_DIR=//p' | head -1)"
    out="${out}pid ${pid} (${cmd:-?}, running ${age:-?})"
    [[ -n "$sdir" ]] && out="${out} — a companion: stop it with lib/brainstorm-server/stop-server.sh ${sdir}"
    out="${out}; "
  done
  printf '%s' "${out:-no listener found by ss}"
}
# every slot comes from the AID range; a configured slot outside it is a misconfiguration, not a way around the rule
for slot in ${AID_COMPANION_PORTS:-3910 3912}; do
  [[ "$slot" =~ ^[0-9]+$ ]] && (( slot >= 3900 && slot <= 3999 )) || fail "AID_COMPANION_PORTS has '$slot', which is not a port in the AID range 3900-3999"
done
LOOPBACK=0; [[ "$BIND_HOST" == "127.0.0.1" || "$BIND_HOST" == "localhost" || "$BIND_HOST" == "::1" ]] && LOOPBACK=1
if [[ -n "$PORT" ]]; then
  [[ "$PORT" =~ ^[0-9]+$ ]] || fail "--port takes a number (got '$PORT')"
  if (( ! LOOPBACK )) && (( PORT < 3900 || PORT > 3999 )); then
    fail "port $PORT is outside the AID range 3900-3999; off loopback the PM reaches only project ports through the VPN (a random high port gave ERR_CONNECTION twice on 6. 10. 2026). Use a companion slot (${AID_COMPANION_PORTS:-3910 3912}) or --port <3900-3999>"
  fi
  if port_busy "$BIND_HOST" "$PORT"; then
    fail "port $PORT is in use by: $(port_holder "$PORT") Forgotten companions of a project: stop-server.sh --stale 24 --project-dir <root>; or pick another --port"
  fi
elif (( ! LOOPBACK )); then
  for slot in ${AID_COMPANION_PORTS:-3910 3912}; do
    port_busy "$BIND_HOST" "$slot" || { PORT="$slot"; break; }
  done
  if [[ -z "$PORT" ]]; then
    holders=""; for slot in ${AID_COMPANION_PORTS:-3910 3912}; do holders="${holders}${slot}: $(port_holder "$slot"); "; done
    fail "every companion slot is in use (${holders% }). A running session is never taken over: stop a forgotten one with lib/brainstorm-server/stop-server.sh <screen_dir>, or stop-server.sh --stale 24 --project-dir <root>, or run this one with --port <another 3900-3999 port>"
  fi
fi

# Codex environments may reap detached/background processes. Prefer foreground by default.
if [[ -n "${CODEX_CI:-}" && "$FOREGROUND" != "true" && "$FORCE_BACKGROUND" != "true" ]]; then
  FOREGROUND="true"
fi

# Generate unique session directory
SESSION_ID="$$-$(date +%s)"

if [[ -n "$PROJECT_DIR" ]]; then
  SCREEN_DIR="${PROJECT_DIR}/.aid-o/work/companion/${SESSION_ID}"
else
  SCREEN_DIR="/tmp/brainstorm-${SESSION_ID}"
fi

PID_FILE="${SCREEN_DIR}/.server.pid"
LOG_FILE="${SCREEN_DIR}/.server.log"

# Create fresh session directory
mkdir -p "$SCREEN_DIR"

cd "$SCRIPT_DIR" || fail "cannot enter $SCRIPT_DIR"

# A plugin update replaces this directory without node_modules (2.114.0, AID
# 2.111 → 2.113: the first companion after the update died with "Cannot find
# module 'express'" behind "failed to start within 5 seconds"). Install them
# here, say so in the log; a failed install prints the exact command.
if [[ ! -d "${SCRIPT_DIR}/node_modules/express" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) node_modules missing — running npm install in ${SCRIPT_DIR}" >> "$LOG_FILE"
  if ! npm install --no-audit --no-fund >> "$LOG_FILE" 2>&1; then
    echo "{\"error\": \"dependencies missing and npm install failed (see $LOG_FILE); run: cd $SCRIPT_DIR && npm install\"}"
    exit 1
  fi
fi

SERVER_ENV=(BRAINSTORM_DIR="$SCREEN_DIR" BRAINSTORM_HOST="$BIND_HOST" BRAINSTORM_URL_HOST="$URL_HOST")
[[ -n "$PORT" ]] && SERVER_ENV+=(BRAINSTORM_PORT="$PORT")
[[ -n "$BASIS" ]] && SERVER_ENV+=(BRAINSTORM_BASIS="$BASIS")

# Foreground mode for environments that reap detached/background processes.
if [[ "$FOREGROUND" == "true" ]]; then
  echo "$$" > "$PID_FILE"
  env "${SERVER_ENV[@]}" node index.js
  exit $?
fi

# Start server, capturing output to log file
# Use nohup to survive shell exit; disown to remove from job table
nohup env "${SERVER_ENV[@]}" node index.js >> "$LOG_FILE" 2>&1 &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null
echo "$SERVER_PID" > "$PID_FILE"

# Wait for server-started message (check log file)
for i in {1..50}; do
  if grep -q "server-started" "$LOG_FILE" 2>/dev/null; then
    # Verify server is still alive after a short window (catches process reapers)
    alive="true"
    for _ in {1..20}; do
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        alive="false"
        break
      fi
      sleep 0.1
    done
    if [[ "$alive" != "true" ]]; then
      echo "{\"error\": \"Server started but was killed. Retry in a persistent terminal with: $SCRIPT_DIR/start-server.sh${PROJECT_DIR:+ --project-dir $PROJECT_DIR}${PLAN_ID:+ --plan $PLAN_ID} --host $BIND_HOST --url-host $URL_HOST${PORT:+ --port $PORT} --foreground\"}"
      exit 1
    fi
    started="$(grep "server-started" "$LOG_FILE" | head -1)"
    # The printed address answers from this host, or the start is a failure, not a URL.
    url="$(jq -r '.url // empty' <<< "$started" 2>/dev/null)"
    if [[ -n "$url" ]] && command -v curl >/dev/null 2>&1 && ! curl -fsS -m 3 -o /dev/null "$url/" 2>/dev/null; then
      kill "$SERVER_PID" 2>/dev/null; rm -f "$PID_FILE"
      echo "{\"error\": \"server started but $url/ does not answer from this host (bind $BIND_HOST, url-host $URL_HOST) — check --host/--url-host; nothing is left running\"}"
      exit 1
    fi
    jq -c --arg b "$BIND_HOST" --arg u "$URL_HOST" --arg h "open the URL from the PM's machine (VPN); off loopback the port is a companion slot from the AID range so the VPN passes it" \
       --arg basis "$BASIS" '. + {bind_host: $b, url_host: $u, hint: $h} + (if $basis != "" then {basis: $basis} else {} end)' <<< "$started" 2>/dev/null || echo "$started"
    exit 0
  fi
  sleep 0.1
done

# Timeout - server didn't start
echo "{\"error\": \"Server failed to start within 5 seconds (see $LOG_FILE)\"}"
exit 1
