#!/usr/bin/env bash
# =============================================================================
# aid-ui-serve.sh — make Impeccable's decision page and the /aid-ui brand page
# reachable from the PM's laptop over the VPN.
#
#   forward <local-port>   HTTP reverse proxy (python3 stdlib, $PROXY_PY below)
#                          AID_UI_HOST:AID_UI_FORWARD_PORT -> 127.0.0.1:<local-port>.
#                          Impeccable answers 403 unless Host, Origin and Referer
#                          say 127.0.0.1:<local-port>, so the proxy rewrites them,
#                          but only for requests addressed to the proxy itself:
#                          Host must be AID_UI_HOST:AID_UI_FORWARD_PORT and Origin/
#                          Referer, when sent, must name http://<that>; anything
#                          else gets 403 and never reaches Impeccable (CSRF guard);
#                          the response streams back chunk by chunk (long-poll/SSE).
#                          only when every process listening on <local-port> is
#                          Impeccable: its command line contains `impeccable`
#                          (hard-coded, no override). Guards against exposing an
#                          unrelated local service on the VPN. A refusal names
#                          only the pid and /proc/<pid>/comm, never the cmdline
#                          (it can carry secrets).
#                          ponytail: ceiling = a local process started with
#                          `impeccable` in its argv passes; a real check would ask
#                          Impeccable's own endpoint who it is.
#   brand <dir>            python3 -m http.server on AID_UI_HOST:AID_UI_BRAND_PORT
#                          only for a brand page dir: realpath ends in /docs/brand
#                          and it has state.json and index.html;
#                          idempotent: our job alive, answering and serving the
#                          same (realpath) dir -> print URL, exit 0; else restart.
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
# Exit: 0 ok, 1 port in use / start failure, 2 usage or refused target.
# =============================================================================
set -euo pipefail

JOB_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aid-job.sh"
HOST="${AID_UI_HOST:-10.20.20.22}"
FWD_PORT="${AID_UI_FORWARD_PORT:-3915}"
BRAND_PORT="${AID_UI_BRAND_PORT:-3916}"
PROJECT="${AID_UI_PROJECT:-$PWD}"
JOBS="${AID_UI_JOBS_DIR:-$PROJECT/.aid-ui/jobs}"
DEADLINE=28800   # 8 h, integer seconds as `aid-job.sh run --deadline` requires

# argv: <bind host> <bind port> <upstream port>. HTTP/1.0 to the browser: the
# connection close ends each response, so nothing is buffered or re-framed.
# ponytail: no WebSocket upgrade and no chunked request bodies (browsers send
# Content-Length); add them if Impeccable's page ever needs them.
PROXY_PY="$(cat <<'PY'
import http.client, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
host, port, up = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
LOCAL = "127.0.0.1:%d" % up
OWN = "%s:%d" % (host, port)   # the address the PM's browser uses
SKIP = {"host", "origin", "referer", "connection", "keep-alive", "proxy-connection",
        "te", "trailer", "transfer-encoding", "upgrade"}

class Proxy(BaseHTTPRequestHandler):
    def ours(self):   # Host is us; Origin/Referer, when sent, name us
        o, r = self.headers.get("Origin"), self.headers.get("Referer")
        return (self.headers.get("Host") == OWN
                and (o is None or o == "http://" + OWN)
                and (r is None or r == "http://" + OWN or r.startswith("http://" + OWN + "/")))

    def proxy(self):
        if not self.ours():
            self.send_error(403, "request not addressed to http://" + OWN)
            return
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else None
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in SKIP}
        hdrs["Host"] = LOCAL
        for k in ("Origin", "Referer"):
            if self.headers.get(k):
                hdrs[k] = "http://" + LOCAL + self.headers[k][len("http://" + OWN):]
        try:
            conn = http.client.HTTPConnection("127.0.0.1", up)
            conn.request(self.command, self.path, body, hdrs)
            r = conn.getresponse()
        except OSError as e:
            self.send_error(502, "upstream 127.0.0.1:%d: %s" % (up, e))
            return
        self.send_response_only(r.status, r.reason)
        for k, v in r.getheaders():
            if k.lower() not in SKIP:
                self.send_header(k, v)
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            while chunk := r.read1(65536):
                self.wfile.write(chunk)
                self.wfile.flush()
        except OSError:
            pass
        finally:
            conn.close()

for m in ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"):
    setattr(Proxy, "do_" + m, Proxy.proxy)
ThreadingHTTPServer((host, port), Proxy).serve_forever()
PY
)"

usage() { echo "usage: aid-ui-serve.sh forward <local-port> | brand <dir> | stop <forward|brand>" >&2; exit 2; }
die() { echo "ERROR: aid-ui-serve.sh: $1" >&2; exit 1; }
refuse() { echo "ERROR: aid-ui-serve.sh: $1" >&2; exit 2; }

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

# Internal: the forward job's command. aid-job.sh records argv one line per
# element, so the multi-line proxy source cannot be an argument of the job itself.
[[ "${1:-}" == __proxy ]] && { shift; exec python3 -c "$PROXY_PY" "$@"; }
[[ $# -eq 2 ]] || usage
case "$1" in
  forward)
    [[ "$2" =~ ^[0-9]+$ ]] || usage
    pids="$(ss -ltnpH "sport = :$2" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
    [[ -n "$pids" ]] || refuse "nothing of ours listens on 127.0.0.1:$2; forward only exposes Impeccable's page"
    for p in $pids; do
      cmdline="$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)"
      [[ "$cmdline" == *impeccable* ]] \
        || refuse "port $2 is not Impeccable's page (pid $p, $(cat "/proc/$p/comm" 2>/dev/null || echo '?')); refusing to expose it"
    done
    start forward bash "${JOB_SH%/*}/aid-ui-serve.sh" __proxy "$HOST" "$FWD_PORT" "$2"
    ;;
  brand)
    dir="$(realpath -e "$2" 2>/dev/null || true)"
    [[ "$dir" == */docs/brand && -f "$dir/state.json" && -f "$dir/index.html" ]] \
      || refuse "$2 is not a brand page (needs <project>/docs/brand with state.json and index.html); refusing to serve it"
    id="$(job_id brand)"
    if alive "$id" && listening "$BRAND_PORT" && [[ "$(jq -r '.command[-1]' "$JOBS/$id/job.json")" == "$dir" ]]; then
      echo "URL: http://$HOST:$BRAND_PORT/"; echo "JOB: $id"; exit 0
    fi
    start brand python3 -m http.server "$BRAND_PORT" --bind "$HOST" --directory "$dir"
    ;;
  stop)
    [[ "$2" == forward || "$2" == brand ]] || usage
    id="$(job_id "$2")"
    [[ -f "$JOBS/$id/job.json" ]] || exit 0
    bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id "$id" >/dev/null || die "cancel of $id failed"
    ;;
  *) usage ;;
esac
