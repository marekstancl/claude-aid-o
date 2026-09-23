#!/usr/bin/env bash
# aid-codex-transport.sh — the one way AID talks to the Codex CLI.
#
# Sourced, never run. Three functions: `aid_codex_binary` (which install),
# `aid_codex_probe` (is it usable now; cached per project) and
# `_run_codex_isolated` (one fresh read-only process, raw captures out).
# Callers: aid-review-round.sh dispatch, lib/aid-brainstorm-opponent.sh,
# lib/aid-recovery-adjudicate.sh; aid-hook-verify.sh reads the binary only. A
# change of the five-argument signature is checked against all of them.

# The model is configuration: a caller may repoint CODEX_MODEL before the call.
CODEX_MODEL="${CODEX_MODEL:-${AID_C3_CODEX_MODEL:-gpt-5.6-terra}}"

# aid_codex_binary — the highest-version `codex` on $PATH, not the first one.
# Two installs coexist on the dev host (/usr/local/bin/codex 0.149.1 shadows
# /usr/bin/codex 0.154.0) and `command -v` picks the older.
aid_codex_binary() {
  local d bin first="" best="" best_v="" v
  # local: this file is SOURCED, and an array left behind in the caller's shell
  # is the kind of thing that only breaks two functions later.
  local -a _acb_dirs=()
  # An explicit choice beats every rule: a wrapper, a pinned install, or a test
  # shim that must win whatever version it claims.
  if [[ -n "${AID_CODEX_BIN:-}" && -x "${AID_CODEX_BIN}" ]]; then
    v="$("${AID_CODEX_BIN}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || true
    printf '%s\t%s\n' "${AID_CODEX_BIN}" "${v:-unknown}"
    return 0
  fi
  IFS=':' read -ra _acb_dirs <<< "$PATH"
  for d in "${_acb_dirs[@]}"; do
    bin="${d:-.}/codex"
    [[ -x "$bin" && ! -d "$bin" ]] || continue
    if [[ -z "$first" ]]; then
      first="$bin"
      v="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || true
      # A codex that will not say its version cannot be ranked, and a wrapper or
      # a test shim put FIRST on PATH is a deliberate choice. PATH order wins
      # there; the version rule is only for deciding between two real installs.
      [[ -n "$v" ]] || { printf '%s\t%s\n' "$first" "unknown"; return 0; }
      best="$bin"; best_v="$v"
      continue
    fi
    v="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || true
    [[ -n "$v" ]] || continue
    if [[ "$(printf '%s\n%s\n' "$best_v" "$v" | sort -V | tail -1)" == "$v" && "$best_v" != "$v" ]]; then
      best="$bin"; best_v="$v"
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s\t%s\n' "$best" "$best_v"
}

# aid_codex_probe [out.json] — can a codex answer right now? Prints
# {available, binary, version, reason, probed_at} and writes it to out.json when
# one is named. `reason` is none|codex_absent|rate_limited|timeout|error.
# A `codex exec` of a one-token prompt is the only way to see the usage limit,
# so the answer is cached for ten minutes under <root>/.aid-o/work/codex-probe.json.
# AID_CODEX_PROBE_STUB=<file> replaces the whole probe with that file's content
# (tests only; never a production path).
aid_codex_probe() {
  local out="${1:-}" root cache age now bin ver rc=0 reason=none avail=true tmp result
  if [[ -n "${AID_CODEX_PROBE_STUB:-}" && -r "${AID_CODEX_PROBE_STUB}" ]]; then
    result="$(cat "$AID_CODEX_PROBE_STUB")"
    [[ -n "$out" ]] && printf '%s\n' "$result" > "$out"
    printf '%s\n' "$result"; return 0
  fi
  root="${AID_PROJECT_ROOT:-$PWD}"; cache="${root}/.aid-o/work/codex-probe.json"
  now="$(date -u +%s)"
  if [[ -r "$cache" ]]; then
    age=$(( now - $(date -u -r "$cache" +%s 2>/dev/null || echo 0) ))
    if (( age >= 0 && age < 600 )) && jq -e . "$cache" >/dev/null 2>&1; then
      result="$(cat "$cache")"
      [[ -n "$out" ]] && printf '%s\n' "$result" > "$out"
      printf '%s\n' "$result"; return 0
    fi
  fi
  if ! IFS=$'\t' read -r bin ver < <(aid_codex_binary); then
    avail=false; reason=codex_absent; bin=""; ver=""
  else
    tmp="$(mktemp)" || { avail=false; reason=error; }
    if [[ "$avail" == true ]]; then
      timeout 30 "$bin" exec --sandbox read-only -m "${CODEX_MODEL:-gpt-5.6-terra}" ok </dev/null >"$tmp" 2>&1 || rc=$?
      if (( rc == 124 )); then avail=false; reason=timeout
      elif (( rc != 0 )); then
        avail=false
        grep -qiE 'usage limit|rate.?limit|429' "$tmp" && reason=rate_limited || reason=error
      fi
      rm -f "$tmp"
    fi
  fi
  result="$(jq -nc --argjson a "$avail" --arg b "$bin" --arg v "$ver" --arg r "$reason" \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{available: $a, binary: $b, version: $v, reason: $r, probed_at: $at}')"
  mkdir -p "${root}/.aid-o/work" 2>/dev/null && printf '%s\n' "$result" > "$cache" 2>/dev/null || true
  [[ -n "$out" ]] && printf '%s\n' "$result" > "$out"
  printf '%s\n' "$result"
}

# _run_codex_isolated <project_root> <prompt_file> <events_out> <stderr_out> <last_out>
#   One fresh, read-only codex process; its --json stream, stderr and last
#   message land in the three output files. Independence is provider + fresh
#   process + `--sandbox read-only`, not a filesystem jail. Reads $CODEX_MODEL
#   and $CODEX_EFFORT (default high, as measured in
#   docs/plans/P099-codex-model-check.md) and a timeout
#   (AID_CODEX_ISOLATED_TIMEOUT_SECONDS; AID_C3_TIMEOUT_SECONDS is the older name
#   and still wins when set). Returns the codex/timeout exit code (124 = timed out).
#
#   The prompt goes on stdin (`-`), never as an argument: a 189 kB CP1 prompt
#   failed with "Argument list too long" (exit 126) on 2026-09-21.
#
#   `--output-schema` is deliberately NOT passed: Codex forwards it to strict
#   structured output, which answers HTTP 400 to any `if`/`then`/`allOf`. The
#   trusted check of an answer is the caller's own validator, never the backend.
_run_codex_isolated() {
  local project_root="$1" prompt_file="$2" events_out="$3" stderr_out="$4" last_out="$5"
  local rc=0 bin
  [[ -r "$prompt_file" ]] || { echo "aid-codex-transport: cannot read prompt $prompt_file" >&2; return 2; }
  IFS=$'\t' read -r bin _ < <(aid_codex_binary) || bin=codex
  timeout "${AID_C3_TIMEOUT_SECONDS:-${AID_CODEX_ISOLATED_TIMEOUT_SECONDS:-900}}" \
    "$bin" exec --json \
      --cd "$project_root" \
      --sandbox read-only \
      -m "$CODEX_MODEL" \
      -c model_reasoning_effort="${CODEX_EFFORT:-high}" \
      --output-last-message "$last_out" \
      - < "$prompt_file" > "$events_out" 2> "$stderr_out" || rc=$?
  return "$rc"
}

