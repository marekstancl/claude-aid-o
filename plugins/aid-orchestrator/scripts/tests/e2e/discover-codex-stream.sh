#!/usr/bin/env bash
# =============================================================================
# discover-codex-stream.sh — E-065-1_7 Step 1 (C3 Cross-Provider Dispatch Bridge)
#
# Runtime-discovery harness for the real Codex CLI. It empirically grounds two
# things the C3 bridge depends on, BEFORE any parser / fake CLI / raw-validator
# is built:
#
#   (a) the actual `codex exec --json` event-stream shape — which JSONL events
#       carry the session/thread id, the model, and the terminal "turn done"
#       event, with the exact jq paths the parser (a LATER EPIC) will use; and
#   (b) what `--output-schema` actually enforces — is the final message
#       constrained to the schema shape? is `additionalProperties:false`
#       honored? is a JSON-Schema `if/then` rule honored? `--output-schema` is
#       treated as MODEL HELP only, never a trusted validator (H1); the bridge
#       validates the raw output itself (Step 6, a later EPIC).
#
# The captured findings live in `evidence/codex-stream-sample/fields.md`, which
# is the single grounding source for the parser (Step 5), the fake CLI (Step 3)
# and the jq raw-validator (Step 6). Re-run this harness to refresh evidence.
#
# ⚠️ This is NOT a CI/gate test. It makes REAL network calls to the Codex
#    backend and requires an authenticated `codex` CLI (>= 0.143.0). It never
#    mocks. Run it manually when Codex behavior needs re-grounding.
#
# Usage:
#   discover-codex-stream.sh [--model <slug>] [--evidence-dir <dir>] [--keep-tmp]
#   discover-codex-stream.sh --sanitize-stdin   # offline: scrub stdin, print, exit
#                                               # (no network; verifies the scrubber)
#
# Exit codes:
#   0  discovery complete, all gate fields present + stable across two runs
#   3  DISCOVERY_PENDING — codex unauthenticated / offline / rate-limited twice
#   4  DISCOVERY_BLOCKER — a required stream field is absent or unstable
#
# Requirements: bash 4+, jq, codex CLI >= 0.143.0, network + ChatGPT login.
# Portability:  Linux (GNU). Not intended for macOS CI.
# =============================================================================
set -euo pipefail

# ---- config -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="gpt-5.5"   # See fields.md §"Model floor": 0.143.0 + ChatGPT account only
                  # accepts this slug; the config default gpt-5.6-sol is rejected.
EVIDENCE_DIR="${SCRIPT_DIR}/evidence/codex-stream-sample"
PROBE_SCHEMA="${SCRIPT_DIR}/fixtures/c3-output-schema-capability-probe.json"
KEEP_TMP=0
MODE=discover

while [ $# -gt 0 ]; do
  case "$1" in
    --model)          MODEL="$2"; shift 2 ;;
    --evidence-dir)   EVIDENCE_DIR="$2"; shift 2 ;;
    --keep-tmp)       KEEP_TMP=1; shift ;;
    --sanitize-stdin) MODE=sanitize; shift ;;
    -h|--help)        sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq    >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

WORK="$(mktemp -d)"
cleanup() { [ "$KEEP_TMP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

# ---- sanitizer --------------------------------------------------------------
# Scrub committed evidence: absolute $HOME/temp paths -> placeholders, local
# username -> <USER>, token-shaped strings -> <REDACTED_TOKEN>. Order matters:
# longer/more specific paths first so they win over their prefixes.
#
# CP2 finding #3 (low): the values below are spliced into the PATTERN side of
# a `#`-delimited `sed -E` command, not the replacement side — escape the ERE
# metacharacter class (incl. `#`, our delimiter) that actually matters there,
# not the replacement-side `/`+`&` idiom the previous version used.
_escape_ere_pattern() {
  sed -e 's/[.[\*^$()+?{}|#\\]/\\&/g'
}

sanitize() {
  local home_esc tmp_esc work_esc user
  user="$(id -un 2>/dev/null || echo user)"
  home_esc="$(printf '%s' "${HOME:-/nonexistent}" | _escape_ere_pattern)"
  tmp_esc="$(printf '%s' "${TMPDIR:-/tmp}" | sed -e 's#/*$##' | _escape_ere_pattern)"
  work_esc="$(printf '%s' "$WORK" | _escape_ere_pattern)"
  sed -E \
    -e "s#${work_esc}#<TMP>#g" \
    -e "s#${tmp_esc}/[A-Za-z0-9._-]+#<TMP>#g" \
    -e "s#${home_esc}#<HOME>#g" \
    -e "s#/(home|Users)/${user}#<HOME>#g" \
    -e "s#\\b${user}\\b#<USER>#g" \
    -e 's#sk[-_](live|test)?[A-Za-z0-9_-]{16,}#<REDACTED_TOKEN>#g' \
    -e 's#gh[ps]_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g' \
    -e 's#gho_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g' \
    -e 's#ghu_[A-Za-z0-9]{16,}#<REDACTED_TOKEN>#g' \
    -e 's#github_pat_[A-Za-z0-9_]{16,}#<REDACTED_TOKEN>#g' \
    -e 's#AKIA[0-9A-Z]{16}#<REDACTED_TOKEN>#g' \
    -e 's#xox[baprs]-[A-Za-z0-9-]{10,}#<REDACTED_TOKEN>#g' \
    -e 's#-----BEGIN [A-Z ]*PRIVATE KEY-----.*-----END [A-Z ]*PRIVATE KEY-----#<REDACTED_PRIVATE_KEY>#g' \
    -e 's#([Aa]uthorization:[[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1<REDACTED_TOKEN>#g' \
    -e 's#eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+#<REDACTED_JWT>#g'
}

# CP2 finding #1 (high): "sanitize and hope" -> "sanitize and verify". Hard
# post-write self-check: abort (non-zero, leave nothing committed-worthy) if
# any leak signature survives sanitization, instead of trusting prose in
# fields.md as the only assurance.
_verify_no_leaks() {
  local file="$1" user
  user="$(id -un 2>/dev/null || echo user)"
  if grep -qE "${HOME:-/nonexistent}|/(home|Users)/${user}|\\b${user}\\b|sk[-_](live|test)?[A-Za-z0-9_-]{16,}|gh[ps]_[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]{16,}|ghu_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" "$file" 2>/dev/null; then
    echo "SANITIZE_LEAK_DETECTED: residual secret/path signature found in ${file} after sanitization — refusing to leave it in place" >&2
    return 1
  fi
  return 0
}

# Offline self-test: scrub stdin and exit. Lets tests / maintainers verify the
# scrubber deterministically without any network call.
if [ "$MODE" = sanitize ]; then
  sanitize
  exit 0
fi

command -v codex >/dev/null 2>&1 || { echo "DISCOVERY_PENDING: codex CLI not on PATH" >&2; exit 3; }

# ---- one codex --json run ---------------------------------------------------
# Args: <run_dir> <out_jsonl> <prompt> [extra codex args...]
# Retries once on a rate-limit signature. Echoes the codex exit code.
run_codex() {
  local dir="$1" out="$2" prompt="$3"; shift 3
  printf 'Project Falcon status report.\nBudget: on track.\nTimeline: two weeks behind due to vendor delay.\n' > "${dir}/sample.txt"
  local attempt ec
  for attempt in 1 2; do
    ec=0
    codex exec --json --skip-git-repo-check --ephemeral \
      --cd "$dir" --sandbox read-only -m "$MODEL" "$@" "$prompt" \
      < /dev/null > "$out" 2> "${out}.stderr" || ec=$?
    if grep -qiE 'rate.?limit|429|too many requests' "${out}.stderr" "$out" 2>/dev/null; then
      [ "$attempt" -eq 1 ] && { sleep 5; continue; }
      echo "DISCOVERY_PENDING: rate-limited twice" >&2; exit 3
    fi
    break
  done
  # Auth/offline signature -> PENDING (empty stream + auth error text).
  if ! jq -e 'select(.type=="thread.started")' "$out" >/dev/null 2>&1; then
    if grep -qiE 'not logged in|unauthor|auth|offline|network|connection' "${out}.stderr" 2>/dev/null; then
      echo "DISCOVERY_PENDING: codex unauthenticated/offline" >&2; exit 3
    fi
  fi
  echo "$ec"
}

echo "== discover-codex-stream.sh :: model=${MODEL} =="
codex --version 2>/dev/null || true

# ---- Run 1 + Run 2 : basic stream shape, twice for stability ----------------
D1="${WORK}/run1"; D2="${WORK}/run2"; mkdir -p "$D1" "$D2"
PROMPT="Read sample.txt and summarize it in one sentence."
ec1="$(run_codex "$D1" "${WORK}/run1.jsonl" "$PROMPT")"
ec2="$(run_codex "$D2" "${WORK}/run2.jsonl" "$PROMPT")"
echo "run1 exit=${ec1}  run2 exit=${ec2}"

# ---- Gate: required stream fields present + stable across the two runs -------
gate_field() {  # <label> <jq filter> <file>
  local label="$1" filt="$2" file="$3" val ec=0
  val="$(jq -r "$filt" "$file" 2>/dev/null)" || ec=$?
  if [ "$ec" -ne 0 ] || [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "DISCOVERY_BLOCKER: ${label} absent in ${file}" >&2
    return 1
  fi
  echo "$val"
}

sid1="$(gate_field 'session-id (run1)' 'select(.type=="thread.started")|.thread_id' "${WORK}/run1.jsonl")" || exit 4
sid2="$(gate_field 'session-id (run2)' 'select(.type=="thread.started")|.thread_id' "${WORK}/run2.jsonl")" || exit 4
gate_field 'completion-event (run1)' 'select(.type=="turn.completed")|.type' "${WORK}/run1.jsonl" >/dev/null || exit 4
gate_field 'completion-event (run2)' 'select(.type=="turn.completed")|.type' "${WORK}/run2.jsonl" >/dev/null || exit 4

# Event-type sequence must be identical across the two runs (stability).
seq1="$(jq -r '.type' "${WORK}/run1.jsonl" | tr '\n' ',')"
seq2="$(jq -r '.type' "${WORK}/run2.jsonl" | tr '\n' ',')"
if [ "$seq1" != "$seq2" ]; then
  echo "DISCOVERY_BLOCKER: event-type sequence unstable across runs" >&2
  echo "  run1: $seq1" >&2; echo "  run2: $seq2" >&2; exit 4
fi

# Model is KNOWN-ABSENT from the --json stream (documented in fields.md). It is
# NOT gated here because the bridge sources the model from its own -m argument,
# not the stream. Fail loudly only if a future codex build STARTS emitting it in
# a shape fields.md does not describe, so the discrepancy is noticed.
if grep -q "\"${MODEL}\"" "${WORK}/run1.jsonl" 2>/dev/null; then
  echo "NOTE: model slug now appears in the --json stream — update fields.md §Model." >&2
fi

# ---- --output-schema probe (b): if/then rule (from committed fixture) -------
DS="${WORK}/schema"; mkdir -p "$DS"
: > "${DS}/ifthen.jsonl"
codex exec --json --skip-git-repo-check --ephemeral --cd "$DS" --sandbox read-only \
  -m "$MODEL" --output-schema "$PROBE_SCHEMA" \
  "Emit your final answer as JSON. Set verdict to fail. Do NOT include any reason field. Also add an extra top-level field named confidence set to 0.9." \
  < /dev/null > "${DS}/ifthen.jsonl" 2>"${DS}/ifthen.stderr" || true

# ---- --output-schema probe (a)+(c): additionalProperties:false --------------
# Uses an inline shape-only schema (no if/then) so the request is ACCEPTED and
# the additionalProperties behavior is observable (the if/then fixture is
# rejected outright, masking it).
cat > "${DS}/addprops.json" <<'JSON'
{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,
 "properties":{"verdict":{"type":"string","enum":["pass","fail"]},"reason":{"type":"string"}},
 "required":["verdict","reason"]}
JSON
codex exec --json --skip-git-repo-check --ephemeral --cd "$DS" --sandbox read-only \
  -m "$MODEL" --output-schema "${DS}/addprops.json" \
  "Emit your final answer as JSON. Set verdict to fail and reason to any short string. Also add extra top-level fields named confidence (0.9) and notes (hello)." \
  < /dev/null > "${DS}/addprops.jsonl" 2>"${DS}/addprops.stderr" || true

echo "-- --output-schema if/then probe (expect API 400 'if is not permitted') --"
# The error `message` is itself a JSON blob; unwrap it to the code + one-line msg.
jq -rc 'select(.type=="error" or .type=="turn.failed")
        | (.message // .error.message) as $m
        | (try ($m|fromjson) catch {error:{message:$m}})
        | "\(.status // "?"): \(.error.code // "?") — \(.error.message // .message)"' \
  "${DS}/ifthen.jsonl" 2>/dev/null | head -1 || true
echo "-- --output-schema additionalProperties probe (expect extras dropped) --"
jq -rs 'map(select(.type=="item.completed" and .item.type=="agent_message"))|last|.item.text' "${DS}/addprops.jsonl" 2>/dev/null || true

# ---- Write sanitized primary stream sample ----------------------------------
mkdir -p "$EVIDENCE_DIR"
sanitize < "${WORK}/run1.jsonl" > "${EVIDENCE_DIR}/events.jsonl"
if ! _verify_no_leaks "${EVIDENCE_DIR}/events.jsonl"; then
  rm -f "${EVIDENCE_DIR}/events.jsonl"
  exit 4
fi

echo "OK: session-id (run1=${sid1}, run2=${sid2}), completion event, and event"
echo "    sequence are present and STABLE across two runs."
echo "Wrote sanitized sample -> ${EVIDENCE_DIR}/events.jsonl"
echo "Author/refresh the analysis in ${EVIDENCE_DIR}/fields.md from this run's output."
exit 0
