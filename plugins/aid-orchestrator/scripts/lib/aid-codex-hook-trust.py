#!/usr/bin/env python3
"""Ask Codex which hooks it sees, and approve them (P086 Step 2).

    aid-codex-hook-trust.py check    -> JSON array of {key, trustStatus, ...}
    aid-codex-hook-trust.py seed     -> approve every unmanaged hook, idempotently

WHY PYTHON IN A BASH PLUGIN
    Codex publishes hook keys, hashes and trust states over JSON-RPC on
    `codex app-server` — a handshake, a request and a read of an interleaved
    stream. The ecosystem sheet (/ecosystem/specs/agent-hooks/codex) ships a
    reference implementation for exactly this and says to take it rather than
    invent one; this is that implementation, narrowed to two subcommands and
    given AID's error handling. Doing the same in bash would mean hand-rolling
    a JSON-RPC client around a pipe.

THE TWO MEASURED TRAPS, BOTH AVOIDED HERE
    `trusted_hash` written INSIDE a hook's own group grants nothing — it must
    live in its own `[hooks.state."<key>"]` table. And appending to
    config.toml when a hook changes produces a duplicate key, at which point
    Codex refuses to start at all. So the state is loaded, merged and the file
    REWRITTEN, every time.

WHAT IS DELIBERATELY ABSENT
    `--dangerously-bypass-hook-trust`. It removes the property the trust model
    exists for (/ecosystem/specs/agent-hooks/ rule 4).

Exit codes: 0 fine, 1 Codex could not be asked, 2 usage.

Last Updated: 2026-08-24
"""
import json
import os
import subprocess
import sys
import threading

TIMEOUT_S = 30


def hooks_list(home, cwd):
    """Every hook Codex would load for <cwd>, with its key, hash and trust state."""
    env = dict(os.environ, CODEX_HOME=home)
    try:
        proc = subprocess.Popen(
            ["codex", "app-server"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, env=env,
        )
    except OSError as exc:
        raise RuntimeError(f"cannot start 'codex app-server': {exc}") from exc

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "aid-hook-trust",
                                        "title": "AID hook trust",
                                        "version": "1"}}})
        send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send({"jsonrpc": "2.0", "id": 2, "method": "hooks/list",
              "params": {"cwds": [cwd]}})
    except (BrokenPipeError, OSError) as exc:
        proc.kill()
        raise RuntimeError(f"'codex app-server' closed the connection: {exc}") from exc

    answer = {}

    def read():
        for line in proc.stdout:
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("id") == 2:
                answer["msg"] = msg
                return

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    reader.join(TIMEOUT_S)
    proc.kill()
    if "msg" not in answer:
        raise RuntimeError(f"'codex app-server' did not answer hooks/list within {TIMEOUT_S}s")
    return answer["msg"].get("result", {}).get("data", [])


def flatten(entries):
    """One record per hook, which is the granularity trust is decided at."""
    return [hook for entry in entries for hook in entry.get("hooks", [])]


def load_state(path):
    """The approvals already in config.toml, as {key: trusted_hash}."""
    state, key = {}, None
    if not os.path.exists(path):
        return state
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            # Both quote forms: TOML allows either, and reading only one would
            # silently drop an approval that strip_state correctly removes.
            if text.startswith("[hooks.state.") and text.endswith("]"):
                key = text[len("[hooks.state."):-1].strip().strip("'\"")
            elif key and text.startswith("trusted_hash"):
                state[key] = text.split("=", 1)[1].strip().strip('"')
                key = None
            elif text.startswith("["):
                key = None
    return state


def strip_state(path):
    """config.toml without its [hooks.state.*] tables — the merge's base.

    A table is dropped from its header to the NEXT table header, whatever it
    contains. The narrower rule this replaces ("skip until a line that is not
    trusted_hash") left comments and extra fields behind, and only recognised
    the double-quoted header form — so a `[hooks.state.'a key']` table survived
    the strip, was written again by the merge, and produced the duplicate key
    that stops Codex from starting.
    """
    out, skipping = [], False
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if text.startswith("[") and not text.startswith("[["):
                skipping = text.startswith("[hooks.state.")
            if skipping:
                continue
            out.append(line)
    return "".join(out).rstrip() + "\n"


def cmd_check(home, cwd):
    print(json.dumps(flatten(hooks_list(home, cwd))))
    return 0


def cmd_seed(home, cwd):
    config = os.path.join(home, "config.toml")
    state = load_state(config)
    added = 0
    for hook in flatten(hooks_list(home, cwd)):
        if hook.get("isManaged"):
            continue                      # managed hooks are approved by policy
        key, current = hook.get("key"), hook.get("currentHash")
        if not key or not current:
            continue
        if state.get(key) != current:
            state[key] = current
            added += 1
            print(f"approving: {hook.get('eventName', '?')} <- {hook.get('command', '?')}",
                  file=sys.stderr)
    body = strip_state(config) if os.path.exists(config) else ""
    blocks = "".join(f'\n[hooks.state."{k}"]\ntrusted_hash = "{v}"\n'
                     for k, v in sorted(state.items()))
    os.makedirs(home, exist_ok=True)
    # Written beside the target and moved into place: a kill or a full disk
    # partway through a direct rewrite leaves a truncated config.toml, and a
    # truncated config.toml is a Codex that will not start — strictly worse
    # than the unapproved hook this command exists to fix. NOT a lock:
    # two concurrent seeds still race, and the loser's approvals are simply
    # re-seeded by the next run.
    tmp = config + ".aid-tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(body + blocks)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, config)
    print(f"{added} newly approved, {len(state)} record(s) in total", file=sys.stderr)
    return 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "seed"):
        print("Usage: aid-codex-hook-trust.py check|seed [codex_home] [cwd]", file=sys.stderr)
        return 2
    home = argv[2] if len(argv) > 2 else os.environ.get(
        "CODEX_HOME", os.path.expanduser("~/.codex"))
    cwd = argv[3] if len(argv) > 3 else os.getcwd()
    try:
        return cmd_check(home, cwd) if argv[1] == "check" else cmd_seed(home, cwd)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
