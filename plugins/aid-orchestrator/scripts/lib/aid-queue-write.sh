#!/usr/bin/env bash
# =============================================================================
# aid-queue-write.sh — THE single writer for .aid-o/config/queue.yaml
# (P064 "Plan Branch Substrate", EPIC E-064-2_2, Step 2 = plan Step 7).
#
# WHY THIS EXISTS: until this file, `aid-queue-add.sh` was the only script that
# ever wrote a queue entry, and it always wrote the literal `status: queued`
# (aid-queue-add.sh:447). Every other status in the live queue — 34 entries
# reading `status: completed` at the time of writing — got there by HAND. That
# is exactly why `aid-fsm.sh`'s `_revalidate_one_dep` could unblock a dependent
# on `status == completed`: a hand edit was, in practice, an unblock button.
# This library makes every status transition the product of a script running
# under a lock, and adds the two fields (`plan_id`, `merge_target`) that let
# dependency readiness be PROVEN against the ref the dependency was actually
# merged into, instead of guessed via the `main|master|HEAD` fallback at
# `aid-fsm.sh:_queue_merge_target`.
#
# ── A QUEUE ENTRY IS A DERIVED VIEW, NEVER EVIDENCE ──────────────────────────
# Nothing in this file may be read as proof that work landed. `merged_to_plan`
# here MIRRORS a fact that `aid-plan-fsm.sh epic-merge-to-plan` established in
# Git (a merge commit that is an ancestor of `plan/<plan_id>`); it does not
# create it. Accordingly, `queue_claim_next`'s readiness test for a dependency
# that carries a `merge_target` is a live `git merge-base --is-ancestor` check
# and NOTHING else — not the status field, not evidence files, not merge-log
# greps. A hand-edited `completed`/`merged_to_plan` on such an entry cannot
# unblock anything (see `_queue_dep_state` below, and the matching restriction
# in `aid-fsm.sh:_revalidate_one_dep`).
#
# ── STATUS ENUM (source of truth: .aid-o/plans/P064-plan-branch-substrate.md
#    → "## Data Model" → "Queue entry — added statuses") ──────────────────────
#   pending           aid-queue-add.sh              queued, not claimed
#   running           aid-plan-fsm.sh epic-start    claimed by a live run
#   merged_to_plan    aid-plan-fsm.sh epic-merge-to-plan
#   released_to_main  aid-plan-fsm.sh plan-merge-to-main
#   abandoned         aid-plan-fsm.sh epic-complete --abandon
#   superseded        aid-plan-fsm.sh epic-complete --supersede
#   blocked           THIS FILE (queue_claim_next)  dependency unresolved
#
# READ-ONLY LEGACY VALUES — accepted when reading an existing entry, never
# written by this library:
#   queued     the historical literal written by aid-queue-add.sh; read as
#              `pending` so the 43 pre-existing entries stay claimable.
#   completed  never written by any script; 34 live entries carry it from hand
#              edits. Read as a legacy synonym of "done" ONLY for entries with
#              no `merge_target` (i.e. legacy, non-plan-branch work). For an
#              entry that declares a `merge_target`, it is ignored entirely.
#
# ── QUEUE `pending` vs MANIFEST `merge_status: pending` ──────────────────────
# They are DIFFERENT fields with different subjects and must not be conflated:
#   * queue `status: pending`     — "this EPIC has not been claimed by a run
#                                   yet". Precedes `running`.
#   * manifest `merge_status: pending` (written by `epic-complete`, Step 1)
#                                 — "this EPIC's run is finished and its merge
#                                   into the plan branch is owed". FOLLOWS
#                                   `running`, and the manifest's own `status`
#                                   stays the literal `running` there, because
#                                   the manifest transition table has no
#                                   `running -> pending` edge.
# Therefore `epic-complete` MUST NOT write queue `status: pending` — that would
# move a claimed EPIC backwards to unclaimed and make it re-claimable by
# `queue_claim_next` while its merge is still owed. The queue's mirror of
# "merge owed" is simply the entry STAYING at `running` until
# `epic-merge-to-plan` writes `merged_to_plan`. The only writer of queue
# `pending` is `aid-queue-add.sh`, exactly as the plan's enum table states.
#
# ── FILE FORMAT: WHY LINE-ORIENTED awk AND NOT yq ───────────────────────────
# The live `.aid-o/config/queue.yaml` is NOT yq-parseable (mixed indentation: a
# top-level `- epic_id:` list with 2-space keys interleaved with a 4-space
# quoted block) — this is documented at `aid-fsm.sh:_queue_parse_to_json` and
# is why that function is a hand-written awk parser. Every read and write here
# is therefore line-oriented awk that preserves untouched lines byte for byte,
# and every write goes through the same `mktemp`-in-place + `mv` shape used at
# `aid-queue-add.sh:459-489`.
#
# ── LOCKING ─────────────────────────────────────────────────────────────────
# All three public mutators acquire `<queue_file>.lock` (a sidecar, never the
# data file — see aid-lock.sh's header for why) via `aid_lock_acquire` with a
# 10s budget and perform read-modify-write INSIDE the hold. Per aid-lock.sh's
# documented flock hazard, a function that holds the lock never calls another
# function that takes it: the internal `_queue_*` helpers below are all
# lock-free and are the only thing the public functions call while holding.
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` — see aid-lock.sh's header for the
# full rationale. Every public function returns an explicit code.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced (the real, intended usage):
#     source .../lib/aid-queue-write.sh
#     queue_set_plan   "E-064-2_2" "P064" "plan/P064"
#     queue_set_status "E-064-2_2" "merged_to_plan"
#     queue_claim_next "P064"          # -> prints the claimed epic_id
#
#   Standalone (debugging / bats convenience — see `main` below):
#     bash aid-queue-write.sh set-status <epic_id> <status> [reason]
#     bash aid-queue-write.sh set-plan   <epic_id> <plan_id> <merge_target>
#     bash aid-queue-write.sh claim-next <plan_id>
#     bash aid-queue-write.sh get        <epic_id> <key>
#     bash aid-queue-write.sh deps       <epic_id>
#   All subcommands accept `--queue <path>` and/or `--project-root <path>`.
#
# Environment:
#   AID_QUEUE_FILE                  absolute path to the queue file (wins).
#   AID_QUEUE_WRITE_PROJECT_ROOT    project root; the queue is
#                                   <root>/.aid-o/config/queue.yaml. Also the
#                                   root every `git -C` ancestry check runs in.
#   AID_QUEUE_WRITE_LOCK_TIMEOUT_S  lock budget in seconds (default 10).
#
# ── UNTRUSTED INPUT: THE TWO DOORS INTO THE FILE ────────────────────────────
# There are exactly TWO ways a byte reaches queue.yaml through this library:
# `_queue_apply_fields` (mutate an existing entry) and `queue_append_entry`
# (add a new one). Both are guarded, and the guards are DIFFERENT because the
# two doors have different shapes.
#
# DOOR 1 — `_queue_apply_fields`, and the awk transport hazard (CP2 finding 1).
# `awk -v x=VALUE` is NOT a literal channel: BOTH mawk and gawk run escape
# processing over the -v value, so a two-character `\n` inside it becomes a
# real newline INSIDE awk. Since `_queue_apply_fields` encodes its k=v payload
# newline-separated, a `reason` carrying `\n` used to smuggle a second
# assignment into the payload and write a status the caller never asked for
# (verified: `set-status E-1 blocked 'oops\nstatus=released_to_main'` landed the
# entry on the terminal `released_to_main` and wedged it). Three layers stand
# in front of THIS door:
#   1. TRANSPORT — every attacker-influenced awk variable travels through
#      `ENVIRON[...]`, which awk copies verbatim with NO escape processing.
#      Chosen over backslash-doubling because it removes the escape semantics
#      entirely instead of trying to out-quote them, and over a temp file
#      because it needs no cleanup path inside a lock hold.
#   2. PARSE — `_queue_apply_fields`' BEGIN block REJECTS (exit 8, nothing
#      written) any payload line with no `=`, any key outside `^[a-z_]+$`, and
#      any duplicated key. A malformed payload aborts the whole write; it never
#      partially applies.
#   3. INPUT — `reason` is charset-validated (`_queue_valid_reason`), `plan_id`
#      by `_queue_valid_id`, `merge_target` by `_queue_valid_branch_ref`, and
#      every `dep` id read back OUT of the queue file goes through the same
#      `_queue_valid_id` guard as a caller-supplied epic_id. An id sitting in
#      the queue file is untrusted input: the file is hand-editable, which is
#      the whole reason this library exists.
#
# DOOR 2 — `queue_append_entry`, and the STRUCTURE layer (CP2 iteration 2,
# finding 1). Door 1's three layers say NOTHING about door 2: an appended
# entry arrives as a pre-rendered YAML block, and until this fix the block was
# written byte-for-byte with no validation at all. `aid-queue-add.sh` builds
# that block by interpolating six argument-reachable values into it, so
# `--merge-target 'plan/P800"<newline>    status: completed<newline>…'` appended
# a SECOND `status:` line to the entry — after which `queue_get_field` (first
# key wins) read `pending` while `aid-fsm.sh:_queue_parse_to_json` (last key
# wins) read `completed`, and the FSM unblocked a dependent that had no branch,
# no evidence and no merge commit. That is a queue status substituting for git
# ancestry proof, i.e. the exact invariant this file exists to defend.
#   4. STRUCTURE — `_queue_validate_entry_block` (below) re-derives the shape
#      of the block INSIDE this library and rejects the whole append unless
#      every non-blank line is either the single leading `  - epic_id: "<id>"`
#      or a `    <key>: <value>` whose value is one of the four literal shapes
#      this library's own writer can emit. Key-shape, value-shape, exactly one
#      `epic_id` line, no repeated key, and the block's id must equal the id
#      argument the duplicate check was run against. Callers are still expected
#      to validate their own inputs (aid-queue-add.sh does, and reports a usage
#      error), but the LIBRARY no longer depends on them doing so — this door
#      cannot be walked through by any present or future caller.
#
# ── REF CHARSET: ONE PREDICATE, BOTH HALVES (CP2 iteration 2, finding 2) ─────
# A branch name is validated by `_queue_valid_branch_ref`, whose authority is
# `git check-ref-format` — not a hand-rolled regex. The previous regex
# (`^[A-Za-z0-9][A-Za-z0-9._/-]*$`) rejected git-legal names like `_wip` while
# `aid-fsm.sh:_resolve_dep_branch` had no charset test at all, so the two
# halves disagreed on exactly those names: the reader said `unblocked`, the
# writer wrote `dependency_no_ancestry_proof`. `aid-fsm.sh:_dep_valid_branch_ref`
# is the byte-for-byte twin of the predicate below. CHANGE BOTH.
#
# Exit codes (functions, as `return`; the standalone CLI mirrors them as `exit`):
#   0 = success.
#   1 = precondition failure that wrote NOTHING: no such entry, a transition
#       out of a terminal status, or (queue_claim_next) nothing claimable.
#   2 = usage / validation failure, including a status outside the enum, a
#       `reason` outside the allowed charset, and a malformed k=v payload.
#   3 = the lock could not be acquired inside the budget, OR a write that the
#       caller was promised would be durable failed. Callers driving a Git
#       transaction (epic-start, epic-merge-to-plan) must treat 3 as a
#       transaction failure at the `intent` phase — no Git action has happened
#       at the point where these functions are called.
#
# **Last Updated:** 2026-07-23
# =============================================================================

_AID_QUEUE_WRITE_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_AID_QUEUE_WRITE_LIBDIR}/aid-lock.sh"

# The writable enum (the "Written by" column of the plan's Data Model table).
AID_QUEUE_WRITE_STATUSES="pending running merged_to_plan released_to_main abandoned superseded blocked"
# Statuses with no outgoing edge — mirroring plan_manifest_set_epic_status's
# terminal set. `merged_to_plan` is deliberately NOT terminal here: the queue's
# own lifecycle continues to `released_to_main` when the plan lands.
AID_QUEUE_TERMINAL_STATUSES="released_to_main abandoned superseded"

_aid_queue_warn() {
  echo "WARN: aid-queue-write.sh: $*" >&2
}

_queue_project_root() {
  printf '%s' "${AID_QUEUE_WRITE_PROJECT_ROOT:-$(pwd)}"
}

# queue_write_path — the canonical queue file this library reads and writes.
queue_write_path() {
  if [[ -n "${AID_QUEUE_FILE:-}" ]]; then
    printf '%s' "$AID_QUEUE_FILE"
  else
    printf '%s/.aid-o/config/queue.yaml' "$(_queue_project_root)"
  fi
}

_queue_lock_path() {
  printf '%s.lock' "$(queue_write_path)"
}

_queue_lock_timeout() {
  printf '%s' "${AID_QUEUE_WRITE_LOCK_TIMEOUT_S:-10}"
}

_queue_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# _queue_valid_id <id> — charset guard for anything interpolated into an awk
# -v variable or compared as a key. EPIC ids are controller-authored
# `E-<digits>...`; plan ids are `P<digits>`. Reject everything else BEFORE it
# reaches awk or the filesystem.
_queue_valid_id() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# _queue_valid_scalar <value> — the EXHAUSTIVE structural guard for anything
# this library writes as a one-line double-quoted YAML scalar (`key: "<v>"`).
# Inside a double-quoted YAML scalar exactly three things can end or escape it:
# a `"`, a `\`, and a line break. Rejecting those three (plus every other
# control character, which would break the line-oriented awk framing) is not a
# heuristic blocklist — it is the complete set, which is why this is safe to
# apply to filesystem paths, where an id-style allowlist would be wrong.
_queue_valid_scalar() {
  local v="${1:-}"
  [[ -n "$v" ]]                          || return 1
  [[ "$v" != *'"'* ]]                    || return 1
  [[ "$v" != *'\'* ]]                    || return 1
  [[ "$v" != *[$'\001'-$'\037']* ]]      || return 1
  [[ "$v" != *$'\177'* ]]                || return 1
  return 0
}

# _queue_valid_branch_ref <ref> — the guard for a branch/ref name.
#
# CONTRACT TWIN of aid-fsm.sh:_dep_valid_branch_ref (CP2 iteration 2, finding
# 2). The authority is `git check-ref-format`, deliberately, because the
# question "is this a ref name?" has exactly one correct answer and it is git's:
# a hand-rolled regex is guaranteed to drift from it in one direction or the
# other, and it drifted — it rejected `_wip`, which git accepts, while the
# reader half accepted it, so the two halves gave opposite answers about the
# same dependency. Widened rather than narrowed the reader because a ref
# reaching this library is only ever passed to `git` as ONE element of an argv
# — never through a shell, never into awk, never re-parsed — so narrowing would
# have invented a false block for a legitimate branch to buy no safety at all.
#
# Two things git's own check does NOT cover are added on top:
#   * a leading `-`, which git accepts as a ref name but which would be read as
#     an OPTION by `git merge-base --is-ancestor "$ref" …`;
#   * a `"` (git accepts it), so that a ref remains safe if a future caller
#     ever writes it back into the file as a YAML scalar.
_queue_valid_branch_ref() {
  local r="${1:-}"
  [[ -n "$r" ]]           || return 1
  [[ "$r" != -* ]]        || return 1
  _queue_valid_scalar "$r" || return 1
  git check-ref-format "refs/heads/${r}" >/dev/null 2>&1
}

# _queue_valid_reason <reason> — allowlist for the free-text `reason` scalar.
# A reason ends up inside a double-quoted YAML scalar AND inside the
# newline-separated k=v payload, so it must contain neither a `"` (breaks the
# quoting), nor a backslash (YAML escape + the awk -v escape vector this guard
# exists for), nor any control character (breaks the payload framing).
# Everything this library itself generates — `dependency_unmerged:E-1`,
# `dependency_abandoned:E-1:plan=P064` — is inside the allowlist.
_queue_valid_reason() {
  [[ "${1:-}" =~ ^[A-Za-z0-9._:/=,()@+#\ -]*$ ]]
}

# _queue_valid_status <status> — membership test against the writable enum.
_queue_valid_status() {
  local s="${1:-}" known
  for known in $AID_QUEUE_WRITE_STATUSES; do
    [[ "$s" == "$known" ]] && return 0
  done
  return 1
}

_queue_is_terminal_status() {
  local s="${1:-}" known
  for known in $AID_QUEUE_TERMINAL_STATUSES; do
    [[ "$s" == "$known" ]] && return 0
  done
  return 1
}

# queue_status_normalize <raw> — the READ-side synonym map. `queued` is the
# historical literal for `pending`; everything else passes through unchanged
# (including the legacy `completed`, which stays visible to callers so they can
# decide for themselves whether it means anything — `_queue_dep_state` decides
# it does NOT for a merge_target entry).
queue_status_normalize() {
  case "${1:-}" in
    queued) printf 'pending' ;;
    *)      printf '%s' "${1:-}" ;;
  esac
}

# ---------------------------------------------------------------------------
# READ helpers — all lock-free (safe to call while holding the lock).
# ---------------------------------------------------------------------------

# queue_entry_ids [file] — every epic_id in file order.
queue_entry_ids() {
  local file="${1:-$(queue_write_path)}"
  [[ -f "$file" ]] || return 0
  awk '
    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", val)
      gsub(/"/, "", val); gsub(/\047/, "", val)
      sub(/[[:space:]]*$/, "", val)
      print val
    }
  ' "$file"
}

# queue_get_field <epic_id> <key> [file] — one scalar field of one entry.
# Prints the empty string when the entry or the key is absent, and also when
# the value is the YAML literal `null` (callers treat "absent" and "null"
# identically — that is what `plan_id: null` means).
queue_get_field() {
  local epic_id="${1:-}" key="${2:-}" file="${3:-$(queue_write_path)}"
  [[ -n "$epic_id" && -n "$key" ]] || return 2
  [[ -f "$file" ]] || return 0
  # ENVIRON, never -v: see the header's "UNTRUSTED INPUT / awk TRANSPORT".
  AID_QW_TARGET="$epic_id" AID_QW_WANT="$key" awk '
    BEGIN { target = ENVIRON["AID_QW_TARGET"]; want = ENVIRON["AID_QW_WANT"] }
    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", val)
      gsub(/"/, "", val); gsub(/\047/, "", val)
      sub(/[[:space:]]*$/, "", val)
      # FIRST entry only (CP2 finding 2): the writer mutates exactly the entry
      # this reader reads, so the reader must stop at the end of that entry
      # rather than fall through into a same-id duplicate further down.
      if (in_target) exit
      in_target = (val == target)
      next
    }
    in_target && /^[[:space:]]+[a-z_]+:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      cp = index(line, ":")
      k = substr(line, 1, cp - 1)
      if (k != want) next
      v = substr(line, cp + 1)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      gsub(/"/, "", v); gsub(/\047/, "", v)
      if (v == "null" || v == "~") v = ""
      print v
      exit
    }
  ' "$file"
}

# queue_get_status <epic_id> [file] — the NORMALIZED status (`queued` reads
# back as `pending`). Empty when the entry has no status line at all.
queue_get_status() {
  local raw
  raw="$(queue_get_field "${1:-}" status "${2:-}")" || return $?
  queue_status_normalize "$raw"
}

# queue_get_deps <epic_id> [file] — the entry's depends_on ids, one per line.
# Handles BOTH shapes the queue uses: the inline `depends_on: ["E-x", "E-y"]`
# that aid-queue-add.sh writes and the multi-line YAML list form.
queue_get_deps() {
  local epic_id="${1:-}" file="${2:-$(queue_write_path)}"
  [[ -n "$epic_id" ]] || return 2
  [[ -f "$file" ]] || return 0
  # ENVIRON, never -v: see the header's "UNTRUSTED INPUT / awk TRANSPORT".
  AID_QW_TARGET="$epic_id" awk '
    BEGIN { target = ENVIRON["AID_QW_TARGET"] }
    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", val)
      gsub(/"/, "", val); gsub(/\047/, "", val)
      sub(/[[:space:]]*$/, "", val)
      if (in_target) exit   # FIRST entry only — see queue_get_field
      in_target = (val == target)
      in_deps = 0
      next
    }
    in_target && /^[[:space:]]+[a-z_]+:/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      cp = index(line, ":")
      k = substr(line, 1, cp - 1)
      in_deps = 0
      if (k != "depends_on") next
      v = substr(line, cp + 1)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /\[/) {
        gsub(/[\[\]]/, "", v); gsub(/"/, "", v); gsub(/\047/, "", v)
        n = split(v, items, ",")
        for (i = 1; i <= n; i++) {
          sub(/^[[:space:]]+/, "", items[i])
          sub(/[[:space:]]+$/, "", items[i])
          if (items[i] != "") print items[i]
        }
        exit
      }
      in_deps = 1
      next
    }
    in_target && in_deps && /^[[:space:]]*-[[:space:]]/ {
      v = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", v)
      gsub(/"/, "", v); gsub(/\047/, "", v)
      sub(/[[:space:]]*$/, "", v)
      if (v != "") print v
      next
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# _queue_apply_fields <file> <epic_id> <k=v>... — the ONE mutation primitive.
# Lock-free by design: every public mutator holds the lock around its call.
#
# Two awk passes over the same file (`file file` + NR==FNR): the first learns
# which of the requested keys the target entry already has and what indentation
# its keys use; the second rewrites, replacing keys in place and inserting the
# missing ones IMMEDIATELY AFTER the `- epic_id:` line. Insertion at the entry
# HEAD rather than the tail is deliberate: entries are separated by blank lines
# and may end in a multi-line `depends_on` list, so a tail insertion would
# either land after the separator (detaching the key from its entry) or inside
# the list.
#
# Returns 1 without writing when <epic_id> has no entry, and 2 without writing
# for a malformed k=v payload. Writes via `mktemp`-in-place + `mv`, the same
# atomic shape as aid-queue-add.sh:459-489.
#
# EXACTLY ONE ENTRY (CP2 finding 2): when the file carries more than one entry
# with <epic_id> — which aid-queue-add.sh:272-275 permits, because its
# duplicate guard only rejects queued|pending|blocked|running — only the FIRST
# is rewritten, because the FIRST is what queue_get_field reads. A duplicate id
# is warned about, not refused: refusing would wedge the legitimate re-add of an
# EPIC whose earlier entry is already terminal.
# ---------------------------------------------------------------------------
_queue_apply_fields() {
  local file="$1" epic_id="$2"; shift 2
  [[ -f "$file" ]] || { _aid_queue_warn "queue file not found: $file"; return 1; }
  [[ $# -gt 0 ]] || return 0
  if ! _queue_valid_id "$epic_id"; then
    _aid_queue_warn "_queue_apply_fields: invalid epic_id '${epic_id}' — nothing written"
    return 2
  fi

  # ── input layer: validate every pair BEFORE it is framed into the payload ──
  local kvs="" pair k seen=""
  for pair in "$@"; do
    if [[ "$pair" != *=* ]]; then
      _aid_queue_warn "malformed field assignment: $pair"; return 2
    fi
    k="${pair%%=*}"
    if [[ ! "$k" =~ ^[a-z_]+$ ]]; then
      _aid_queue_warn "invalid field key '${k}' — nothing written"; return 2
    fi
    if [[ "$pair" == *[$'\001'-$'\037']* ]]; then
      _aid_queue_warn "field assignment for '${k}' contains a control character — nothing written"; return 2
    fi
    if [[ " ${seen} " == *" ${k} "* ]]; then
      _aid_queue_warn "duplicate field key '${k}' in one write — nothing written"; return 2
    fi
    seen+="${k} "
    kvs+="${pair}"$'\n'
  done

  local ndup
  ndup="$(queue_entry_ids "$file" | grep -Fxc -- "$epic_id" || true)"
  if [[ "${ndup:-0}" -gt 1 ]]; then
    _aid_queue_warn "${ndup} entries carry epic_id '${epic_id}' in ${file}; rewriting only the FIRST (the one queue_get_field reads)"
  fi

  local tmp="${file}.tmp.$$"
  local ts; ts="$(_queue_timestamp)"
  local -a pstat=()
  # STREAMED, never `out="$(awk …)"` (CP2 iteration 2, LOW note): command
  # substitution strips every trailing newline, so the round-trip silently
  # collapsed a file's trailing blank lines and the "preserves untouched lines
  # byte for byte" claim in the header was false for the last line of the file.
  # A pipeline into the staging temp keeps the stream intact; `PIPESTATUS` (this
  # library sets no `pipefail`, by the sourceable-safe convention) carries the
  # awk rc that the rejection codes 8/9 below depend on.
  #
  # `last_modified` is a top-level scalar refreshed with the same sed shape
  # aid-queue-add.sh:471 uses (piped, not `sed -i`, which is not portable).
  #
  # ENVIRON, never -v — see the header. `target`/`kvs` both carry data that can
  # originate outside this library, and -v would escape-process both.
  AID_QW_TARGET="$epic_id" AID_QW_KVS="$kvs" awk '
    BEGIN {
      target = ENVIRON["AID_QW_TARGET"]
      kvs    = ENVIRON["AID_QW_KVS"]
      aborted = 0
      nkeys = 0
      n = split(kvs, lines, "\n")
      for (i = 1; i <= n; i++) {
        if (lines[i] == "") continue
        p = index(lines[i], "=")
        # parse layer: a line with no "=" (p == 0) used to yield an EMPTY key
        # that was still counted in nkeys; a bad or repeated key used to be
        # resolved "last one wins" at the rewrite. All three now abort the
        # whole write.
        if (p < 2) { aborted = 1; exit 8 }
        k = substr(lines[i], 1, p - 1)
        if (k !~ /^[a-z_]+$/) { aborted = 1; exit 8 }
        if (k in seenkey)     { aborted = 1; exit 8 }
        seenkey[k] = 1
        nkeys++
        key[nkeys] = k
        val[nkeys] = substr(lines[i], p + 1)
      }
      if (nkeys == 0) { aborted = 1; exit 8 }
      keyindent = "    "
      found = 0
    }

    function entry_id(line,   v) {
      v = line
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", v)
      gsub(/"/, "", v); gsub(/\047/, "", v)
      sub(/[[:space:]]*$/, "", v)
      return v
    }

    # ── pass 1: which keys already exist, and at what indentation ──────────
    NR == FNR {
      if ($0 ~ /^[[:space:]]*-[[:space:]]+epic_id:/) {
        # FIRST matching entry only (CP2 finding 2).
        if (entry_id($0) == target && !found) { in_target = 1; found = 1 }
        else                                    in_target = 0
        next
      }
      if (in_target && $0 ~ /^[[:space:]]+[a-z_]+:/) {
        line = $0
        match(line, /^[[:space:]]+/)
        if (!indent_seen) { keyindent = substr(line, 1, RLENGTH); indent_seen = 1 }
        sub(/^[[:space:]]+/, "", line)
        cp = index(line, ":")
        k = substr(line, 1, cp - 1)
        for (i = 1; i <= nkeys; i++) if (k == key[i]) has[i] = 1
      }
      next
    }

    # ── pass 2: rewrite ────────────────────────────────────────────────────
    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      # FIRST matching entry only (CP2 finding 2): once the target entry has
      # been rewritten, a later entry with the same id is left alone.
      if (entry_id($0) == target && !done_target) { in_target2 = 1; done_target = 1 }
      else                                          in_target2 = 0
      print
      if (in_target2) {
        for (i = 1; i <= nkeys; i++) if (!has[i]) printf "%s%s: %s\n", keyindent, key[i], val[i]
      }
      next
    }
    {
      if (in_target2 && $0 ~ /^[[:space:]]+[a-z_]+:/) {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        cp = index(line, ":")
        k = substr(line, 1, cp - 1)
        # Keys are unique by construction (BEGIN aborts on a duplicate), so the
        # first match IS the only match — no "last one wins" ambiguity left.
        idx = 0
        for (i = 1; i <= nkeys; i++) if (k == key[i]) { idx = i; break }
        if (idx > 0) { printf "%s%s: %s\n", keyindent, key[idx], val[idx]; next }
      }
      print
    }

    END {
      if (aborted) exit 8
      if (!found)  exit 9
    }
  ' "$file" "$file" \
    | sed "s|^last_modified:.*|last_modified: \"${ts}\"|" > "$tmp"
  pstat=("${PIPESTATUS[@]}")
  local rc="${pstat[0]:-1}" sedrc="${pstat[1]:-1}"

  if [[ "$rc" -eq 8 ]]; then
    rm -f "$tmp"
    _aid_queue_warn "malformed k=v payload rejected by the awk parse layer — nothing written"
    return 2
  fi
  if [[ "$rc" -eq 9 ]]; then
    rm -f "$tmp"
    _aid_queue_warn "no queue entry for '${epic_id}' in ${file} — nothing written"
    return 1
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp"
    _aid_queue_warn "failed to rewrite ${file} (awk rc=${rc}) — nothing written"
    return 1
  fi
  if [[ "$sedrc" -ne 0 ]]; then
    rm -f "$tmp"
    _aid_queue_warn "failed to stage ${tmp} — nothing written"
    return 1
  fi

  mv -- "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# BRANCH RESOLUTION — CONTRACT TWIN of aid-fsm.sh:_resolve_dep_branch (~:4924)
# and its helper _dep_evidence_branch (~:4912).
#
# WHY A TWIN AND NOT A REUSE (CP2 finding 3): aid-fsm.sh is a 5000-line command
# script, not a sourceable library — sourcing it to reach `_resolve_dep_branch`
# would drag in its whole global surface (and its own `yaml_field`), and it is
# outside this step's allowed paths to split out. The rule is therefore
# re-implemented here, byte-for-byte in behaviour:
#   1. `task/<dep>/main` if that ref exists;
#   2. else the `branch:` recorded in the dep's evidence fsm-state.yaml, if
#      that ref exists and is NOT main/master (a legacy `branch: main` would
#      false-unblock everything);
#   3. else empty — no live branch to prove ancestry with.
# BEFORE this, the writer knew only rule 1, so a dependency that ran on a
# non-conventional branch made `aid-fsm.sh queue-revalidate` say `unblocked`
# while `queue_claim_next` wrote `blocked:…:dependency_no_ancestry_proof` on
# the same fact. If you change one implementation, change the other.
# ---------------------------------------------------------------------------

# _queue_yaml_field <file> <key> — flat `key: value` scalar reader, the twin of
# aid-fsm.sh:yaml_field (:87). First match wins; empty on missing file/key.
_queue_yaml_field() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "${key}:"* ]] || continue
    line="${line#"${key}:"}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%%[[:space:]]*}"
    if [[ ${#line} -ge 2 && "${line:0:1}" == '"' && "${line: -1}" == '"' ]]; then
      line="${line:1:${#line}-2}"
    elif [[ ${#line} -ge 2 && "${line:0:1}" == "'" && "${line: -1}" == "'" ]]; then
      line="${line:1:${#line}-2}"
    fi
    printf '%s' "$line"
    return 0
  done < "$file"
  return 0
}

# _queue_evidence_branch <dep> <root> — twin of aid-fsm.sh:_dep_evidence_branch.
# Command substitution rather than `done < <(find ...)` on purpose: this runs
# while the queue lock is held, and a process-substitution subshell would hold a
# duplicate of the lock fd past aid_lock_release (CP2 finding 5).
_queue_evidence_branch() {
  local dep="$1" root="$2" f br files
  files="$(find "${root}/.aid-o/work/evidence/${dep}" -name fsm-state.yaml 2>/dev/null)"
  [[ -n "$files" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    br="$(_queue_yaml_field "$f" branch)"
    [[ -n "$br" ]] && { printf '%s' "$br"; return 0; }
  done <<< "$files"
  return 0
}

# _queue_resolve_dep_branch <dep> <root> — see the block comment above.
_queue_resolve_dep_branch() {
  local dep="$1" root="$2"
  local conv="task/${dep}/main"
  if _queue_valid_branch_ref "$conv" \
     && git -C "$root" show-ref --verify --quiet "refs/heads/${conv}"; then
    printf '%s' "$conv"; return 0
  fi
  local ev; ev="$(_queue_evidence_branch "$dep" "$root")"
  # `_queue_valid_branch_ref`, not the old hand-rolled regex (CP2 iteration 2,
  # finding 2): the evidence `branch:` field records whatever branch the dep
  # actually ran on, and git-legal names like `_wip` were rejected here while
  # aid-fsm.sh's reader accepted them — the two halves then disagreed about
  # whether the dependent was ready.
  if [[ -n "$ev" && "$ev" != "main" && "$ev" != "master" ]] \
     && _queue_valid_branch_ref "$ev" \
     && git -C "$root" show-ref --verify --quiet "refs/heads/${ev}"; then
    printf '%s' "$ev"; return 0
  fi
  return 0
}

# _queue_target_branch <root> — the resolved cross-plan target branch: the ref
# a RELEASED dependency's merge_target is rewritten to (plan-merge-to-main).
# CONTRACT TWIN of aid-fsm.sh:_queue_merge_target (main → master → HEAD). Used
# only by _queue_merge_target_authorized to recognise the target-branch case.
_queue_target_branch() {
  local root="$1"
  if git -C "$root" show-ref --verify --quiet refs/heads/main; then echo main
  elif git -C "$root" show-ref --verify --quiet refs/heads/master; then echo master
  else echo HEAD; fi
}

# _queue_merge_target_authorized <declared> <dep> <root> — IMP-272 (+ HIGH hardening).
#
# A `merge_target` is read straight out of the hand-editable queue file, and
# `git merge-base --is-ancestor <branch> <merge_target>` is proven AGAINST it —
# so a value the attacker controls is the very ref the proof is anchored to.
# `_queue_valid_branch_ref` only asks "is this a legal ref name?"; it accepts
# the dependency's OWN task branch, whose ancestry against itself is trivially
# true, so pointing a dependency at `task/<its own id>/main` self-satisfied the
# check and marked work `merged` that was provably never in `plan/<plan>`. This
# predicate constrains the value to the only two refs the substrate ever
# legitimately writes there:
#   * `plan/<id-derived plan>` — a same-plan dependency, still on its plan branch;
#   * the resolved target branch (_queue_target_branch) — a cross-plan
#     dependency already released to main/master.
# Any OTHER ref that resolves (an EPIC task branch, another plan's branch, an
# arbitrary feature branch) is refused by _queue_dep_state, never treated as
# proof. An entry with no plan_id (`plan_id: null`, read back as empty) has no
# owning plan, so `plan/<...>` is impossible for it and only the target branch
# is legal.
#
# IMP-272 HARDENING (post-review HIGH): the owning plan is DERIVED from the
# dependency's epic id — the record KEY bound to the identity the ancestry
# check runs against — never read from the entry's hand-editable `plan_id`
# field. Trusting `plan_id` let `plan_id: P999` + `merge_target: plan/P999`
# self-authorize the anchor one field over. `_queue_dep_derived_plan` derives
# `P<nnn>` from the id (empty for an ad-hoc id); the entry's declared plan_id,
# when present, is fail-closed cross-checked against it by _queue_dep_state.
# Byte-for-byte the same derivation as aid-fsm.sh:_fsm_epic_plan_nnn.
#
# CONTRACT TWIN of aid-fsm.sh:_dep_merge_target_authorized, which enforces the
# same rule for the READ side (queue-revalidate). CHANGE BOTH.
_queue_dep_derived_plan() {
  local id="${1:-}"; id="${id%%_*}"
  [[ "$id" =~ ^E-([0-9]+) ]] && printf 'P%s' "${BASH_REMATCH[1]}"
}
_queue_merge_target_authorized() {
  local declared="$1" dep="$2" root="$3"
  [[ "$declared" == "$(_queue_target_branch "$root")" ]] && return 0
  local derived; derived="$(_queue_dep_derived_plan "$dep")"
  [[ -n "$derived" && "$declared" == "plan/${derived}" ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# _queue_dep_state <dep> <file> <root> — is this dependency delivered?
# Echoes exactly one of:
#   merged             proven: its branch is an ancestor of its declared
#                      merge_target (or, for a LEGACY entry with no
#                      merge_target, its status says so).
#   unmerged           branch exists, is not contained in merge_target.
#   no_proof           merge_target declared but no live branch to prove
#                      ancestry with — a deleted branch is NOT proof, and
#                      neither is a status field (see the header).
#   abandoned          terminal-not-delivered (abandoned/superseded).
#   target_missing     the declared merge_target ref is unusable or does not
#                      resolve.
#   target_unauthorized  the declared merge_target resolves but is neither the
#                      entry's own plan branch nor the target branch (IMP-272):
#                      an illegal anchor for the ancestry proof, refused rather
#                      than believed.
#   invalid_id         <dep> is not a well-formed id — the queue file is corrupt
#                      or hand-edited. NEVER interpolated anywhere (CP2 finding
#                      1: a dep id is read straight out of a hand-editable file
#                      and is untrusted input, exactly like a caller argument).
# Lock-free; git reads only.
# ---------------------------------------------------------------------------
_queue_dep_state() {
  local dep="$1" file="$2" root="$3"
  local status mt
  if ! _queue_valid_id "$dep"; then
    echo "invalid_id"; return 0
  fi
  status="$(queue_get_status "$dep" "$file")"
  mt="$(queue_get_field "$dep" merge_target "$file")"

  case "$status" in
    abandoned|superseded) echo "abandoned"; return 0 ;;
  esac

  if [[ -z "$mt" ]]; then
    # LEGACY entry (no merge_target): the pre-P064 semantics, unchanged —
    # the status field is all there is.
    case "$status" in
      merged_to_plan|released_to_main|completed) echo "merged" ;;
      *)                                         echo "unmerged" ;;
    esac
    return 0
  fi

  # A merge_target read back OUT of the hand-editable queue file is untrusted
  # input exactly like a dep id (CP2 iteration 2, LOW note): guard it with the
  # same predicate before it becomes an argv element of `git`, where a leading
  # `-` would be read as an option. An unusable target is reported as
  # `target_missing` — the same answer a non-resolving ref already gets, and the
  # one that keeps the dependent BLOCKED rather than silently proven.
  if ! _queue_valid_branch_ref "$mt" \
     || ! git -C "$root" rev-parse --verify --quiet "${mt}^{commit}" >/dev/null 2>&1; then
    echo "target_missing"; return 0
  fi

  # IMP-272: a resolvable ref is not yet an AUTHORIZED anchor for the ancestry
  # proof. Constrain it to the entry's own plan branch or the resolved target
  # branch; any other resolvable ref (the dep's own task branch — the demonstrated
  # attack — another plan's branch, an arbitrary feature branch) is refused, so a
  # dependent is never claimed on a self-satisfying anchor. `plan_id` is read from
  # the same hand-editable entry; queue_get_field maps a `null`/absent plan_id to
  # empty, which leaves only the target branch legal (an entry with no owning plan
  # cannot legitimately declare `plan/<x>`).
  # Fail-closed cross-check (post-review HIGH): a declared plan_id must agree
  # with the id-derived plan, or it was set to launder an unauthorized target.
  local own_plan; own_plan="$(queue_get_field "$dep" plan_id "$file")"
  local derived_plan; derived_plan="$(_queue_dep_derived_plan "$dep")"
  if [[ -n "$own_plan" && "$own_plan" != "$derived_plan" ]]; then
    echo "target_unauthorized"; return 0
  fi
  if ! _queue_merge_target_authorized "$mt" "$dep" "$root"; then
    echo "target_unauthorized"; return 0
  fi

  # Contract twin of aid-fsm.sh:_resolve_dep_branch — see the block comment
  # above _queue_yaml_field. Reader and writer must answer the same question
  # the same way, including for a dep that ran on a non-conventional branch.
  local branch; branch="$(_queue_resolve_dep_branch "$dep" "$root")"
  if [[ -z "$branch" ]]; then
    echo "no_proof"; return 0
  fi

  if git -C "$root" merge-base --is-ancestor "$branch" "$mt" >/dev/null 2>&1; then
    echo "merged"
  else
    echo "unmerged"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

# queue_set_status <epic_id> <status> [reason]
#   Validates <status> against the writable enum (exit 2, nothing written, for
#   anything else — including the read-only legacy `queued`/`completed`), then
#   rewrites the entry's `status:` (and `reason:` when given) under the lock.
#   Refuses (exit 1, nothing written) to move OUT of a terminal status.
queue_set_status() {
  local epic_id="${1:-}" status="${2:-}" reason="${3:-}"
  if [[ -z "$epic_id" || -z "$status" ]]; then
    _aid_queue_warn "queue_set_status: usage: queue_set_status <epic_id> <status> [reason]"
    return 2
  fi
  if ! _queue_valid_id "$epic_id"; then
    _aid_queue_warn "queue_set_status: invalid epic_id '${epic_id}'"
    return 2
  fi
  if ! _queue_valid_status "$status"; then
    _aid_queue_warn "queue_set_status: '${status}' is not a writable queue status (enum: ${AID_QUEUE_WRITE_STATUSES}); nothing written"
    return 2
  fi
  # INPUT layer (CP2 finding 1). A reason used to be "sanitised" by stripping
  # `"` and newlines, which left BACKSLASHES intact — and `awk -v` turns a
  # two-character `\n` into a real newline, which used to smuggle a second
  # `status=` assignment into _queue_apply_fields' payload and land the entry
  # on a status the caller never asked for. Reject rather than mangle: the
  # library's own reasons are machine-generated tokens well inside this
  # allowlist, so anything outside it is a bug or an attack, and the plan's
  # rule for a bad status ("exits 2 and writes nothing") applies here too.
  if [[ -n "$reason" ]] && ! _queue_valid_reason "$reason"; then
    _aid_queue_warn "queue_set_status: reason contains characters outside the allowed set (no quotes, backslashes or control characters); nothing written"
    return 2
  fi

  local file; file="$(queue_write_path)"
  aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)" || return 3
  local fd="$AID_LOCK_FD"

  local cur; cur="$(queue_get_status "$epic_id" "$file")"
  if [[ -n "$cur" && "$cur" != "$status" ]] && _queue_is_terminal_status "$cur"; then
    aid_lock_release "$fd"
    _aid_queue_warn "queue_set_status: ${epic_id} is terminal at '${cur}' — refusing to move it to '${status}'; nothing written"
    return 1
  fi

  # The reason is already charset-validated above, so it is a safe one-line
  # double-quoted YAML scalar by construction.
  local -a fields=("status=${status}")
  [[ -n "$reason" ]] && fields+=("reason=\"${reason}\"")

  local rc=0
  _queue_apply_fields "$file" "$epic_id" "${fields[@]}" || rc=$?
  aid_lock_release "$fd"
  return "$rc"
}

# queue_set_plan <epic_id> <plan_id> <merge_target>
#   Records the two P064 fields. <plan_id> may be the literal `null` for work
#   that belongs to no plan. <merge_target> is `plan/<plan_id>` while the plan
#   is open, and is REWRITTEN to the target branch by plan-merge-to-main when
#   the plan is released — which is what makes a cross-plan dependency resolve
#   against `main` rather than a plan branch that may later be deleted.
queue_set_plan() {
  local epic_id="${1:-}" plan_id="${2:-}" merge_target="${3:-}"
  if [[ -z "$epic_id" || -z "$plan_id" || -z "$merge_target" ]]; then
    _aid_queue_warn "queue_set_plan: usage: queue_set_plan <epic_id> <plan_id|null> <merge_target>"
    return 2
  fi
  if ! _queue_valid_id "$epic_id"; then
    _aid_queue_warn "queue_set_plan: invalid epic_id '${epic_id}'"
    return 2
  fi
  if [[ "$plan_id" != "null" ]] && ! _queue_valid_id "$plan_id"; then
    _aid_queue_warn "queue_set_plan: invalid plan_id '${plan_id}'"
    return 2
  fi
  # A ref name, not a shell word: reject whitespace and quoting metacharacters
  # rather than emitting YAML that no longer parses. Same predicate as the
  # resolver (CP2 iteration 2, finding 2) so a plan released onto a git-legal
  # branch name the old regex happened to dislike is not rejected here and then
  # accepted there.
  if [[ "$merge_target" != "null" ]] && ! _queue_valid_branch_ref "$merge_target"; then
    _aid_queue_warn "queue_set_plan: invalid merge_target '${merge_target}'"
    return 2
  fi

  local file; file="$(queue_write_path)"
  aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)" || return 3
  local fd="$AID_LOCK_FD"

  local plan_val="null" mt_val="null"
  [[ "$plan_id" != "null" ]] && plan_val="\"${plan_id}\""
  [[ "$merge_target" != "null" ]] && mt_val="\"${merge_target}\""

  local rc=0
  _queue_apply_fields "$file" "$epic_id" "plan_id=${plan_val}" "merge_target=${mt_val}" || rc=$?
  aid_lock_release "$fd"
  return "$rc"
}

# ---------------------------------------------------------------------------
# _queue_validate_entry_block <epic_id> <block> — the STRUCTURE layer (door 2;
# see the header). Returns 0 when <block> is a single, well-formed queue entry
# for <epic_id>, and 2 (with a warning naming the offending line) otherwise.
#
# WHY THIS IS NOT THE CALLER'S JOB: it is the caller's job TOO, but the library
# may not depend on it. `aid-queue-add.sh` renders this block by interpolating
# six argument-reachable values into a heredoc; before this check existed, ONE
# unguarded value containing a newline appended a second `status:` line to the
# entry and split the two queue readers' answers apart (`queue_get_field` is
# first-key-wins, `aid-fsm.sh:_queue_parse_to_json` is last-key-wins), which is
# how a hand-supplied `completed` came to unblock an EPIC with no branch, no
# evidence and no merge commit.
#
# The value shapes below are EXHAUSTIVE for what this library's own writers
# emit — a bare token, `null`/`~`, a double-quoted scalar with no embedded `"`,
# or an inline list of such scalars. Anything else is refused rather than
# guessed at: an entry whose value shape this library does not recognise is an
# entry it cannot promise to read back the same way.
# ---------------------------------------------------------------------------
_queue_validate_entry_block() {
  local epic_id="$1" block="$2"
  local id_re='^  - epic_id: "([A-Za-z0-9][A-Za-z0-9._-]*)"$'
  local key_re='^    ([a-z_]+): (.*)$'
  local val_re='^(null|~|[A-Za-z0-9][A-Za-z0-9._/-]*|"[^"]*"|\[\]|\[("[^"]*")(, *"[^"]*")*\])$'
  local line k v seen=" " nid=0 first=1

  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue    # blank lines are inert
    if [[ "$line" == *[$'\001'-$'\037']* || "$line" == *$'\177'* ]]; then
      _aid_queue_warn "queue_append_entry: entry block line carries a control character — nothing written"
      return 2
    fi
    if [[ "$line" =~ $id_re ]]; then
      if [[ "$first" -ne 1 ]]; then
        _aid_queue_warn "queue_append_entry: entry block carries more than one '- epic_id:' line — nothing written"
        return 2
      fi
      if [[ "${BASH_REMATCH[1]}" != "$epic_id" ]]; then
        _aid_queue_warn "queue_append_entry: entry block declares epic_id '${BASH_REMATCH[1]}' but the append was requested for '${epic_id}' — nothing written"
        return 2
      fi
      nid=$((nid + 1)); k="epic_id"
    elif [[ "$line" =~ $key_re ]]; then
      if [[ "$first" -eq 1 ]]; then
        _aid_queue_warn "queue_append_entry: entry block does not start with '  - epic_id:' — nothing written"
        return 2
      fi
      k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
      if [[ ! "$v" =~ $val_re ]]; then
        _aid_queue_warn "queue_append_entry: value of '${k}' is not a shape this library writes — nothing written"
        return 2
      fi
    else
      _aid_queue_warn "queue_append_entry: entry block line is neither '  - epic_id: \"<id>\"' nor '    <key>: <value>' — nothing written"
      return 2
    fi
    if [[ " ${seen} " == *" ${k} "* ]]; then
      _aid_queue_warn "queue_append_entry: key '${k}' appears twice in one entry block — nothing written"
      return 2
    fi
    seen+="${k} "
    first=0
  done <<< "$block"

  if [[ "$nid" -ne 1 ]]; then
    _aid_queue_warn "queue_append_entry: entry block must contain exactly one '- epic_id:' line — nothing written"
    return 2
  fi
  return 0
}

# queue_append_entry <epic_id> <entry_yaml_block>
#   The append half of the write path, delegated here from aid-queue-add.sh so
#   BOTH the append and every later transition happen under the same lock. The
#   duplicate check is re-run INSIDE the lock: aid-queue-add.sh's own check
#   runs before it, and two concurrent adds would otherwise both pass it.
#
#   The block itself is STRUCTURALLY validated before anything is staged — see
#   _queue_validate_entry_block. Validation happens BEFORE the lock is taken:
#   it touches no file, and a rejected append must not make a concurrent
#   legitimate one wait.
queue_append_entry() {
  local epic_id="${1:-}" block="${2:-}"
  if [[ -z "$epic_id" || -z "$block" ]]; then
    _aid_queue_warn "queue_append_entry: usage: queue_append_entry <epic_id> <entry_yaml>"
    return 2
  fi
  if ! _queue_valid_id "$epic_id"; then
    _aid_queue_warn "queue_append_entry: invalid epic_id '${epic_id}' — nothing written"
    return 2
  fi
  _queue_validate_entry_block "$epic_id" "$block" || return 2
  local file; file="$(queue_write_path)"
  local dir; dir="$(dirname -- "$file")"
  [[ -d "$dir" ]] || { _aid_queue_warn "queue directory does not exist: $dir"; return 3; }

  aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)" || return 3
  local fd="$AID_LOCK_FD"

  local existing
  existing="$(queue_entry_ids "$file" | grep -Fx -- "$epic_id" || true)"
  if [[ -n "$existing" ]]; then
    aid_lock_release "$fd"
    _aid_queue_warn "queue_append_entry: ${epic_id} already present — nothing written"
    return 1
  fi

  local ts; ts="$(_queue_timestamp)"
  local tmp="${file}.tmp.$$"
  local rc=0
  if [[ -f "$file" ]]; then
    { sed "s|^last_modified:.*|last_modified: \"${ts}\"|" "$file"; printf '%s\n' "$block"; } > "$tmp" || rc=$?
  else
    {
      printf '%s\n' '# Epic Queue — managed by Orchestrator + /epic-queue command'
      printf '%s\n' '# Do not edit manually while an EPIC is running.'
      printf '\n'
      printf '%s\n' 'paused: false'
      printf 'last_modified: "%s"\n' "$ts"
      printf '\n'
      printf '%s\n' 'queue:'
      printf '%s\n' "$block"
    } > "$tmp" || rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp"; aid_lock_release "$fd"
    _aid_queue_warn "queue_append_entry: could not stage ${tmp}"
    return 3
  fi
  mv -- "$tmp" "$file" || rc=$?
  aid_lock_release "$fd"
  if [[ "$rc" -ne 0 ]]; then rm -f "$tmp"; return 3; fi
  return 0
}

# queue_claim_next <plan_id>
#   Read-and-claim inside ONE lock hold: scans entries in file order for the
#   first one that (a) belongs to <plan_id>, (b) is claimable (`pending` —
#   including the legacy `queued` — or a previously recorded `blocked`, which
#   the manifest's own table also allows back to `running`), and (c) has every
#   `depends_on` entry resolving as merged against ITS OWN declared
#   merge_target. That entry is set to `running` and its id printed.
#
#   Because the read and the write happen under one hold, two concurrent
#   callers cannot both win the same entry: the loser re-reads `running` and
#   skips it.
#
#   Candidates that are NOT ready are recorded `blocked` with a `reason` before
#   the scan moves on, so a plan aborted upstream leaves a durable, readable
#   explanation on the dependent rather than silent inaction.
#
#   stdout / exit:
#     <epic_id>                    rc 0 — claimed.
#     blocked:<epic_id>:<reason>   rc 1 — candidates existed, none ready.
#     none                         rc 1 — no candidate entry for this plan.
queue_claim_next() {
  local plan_id="${1:-}"
  if [[ -z "$plan_id" ]] || ! _queue_valid_id "$plan_id"; then
    _aid_queue_warn "queue_claim_next: usage: queue_claim_next <plan_id>"
    return 2
  fi

  local file; file="$(queue_write_path)"
  local root; root="$(_queue_project_root)"

  aid_lock_acquire "$(_queue_lock_path)" "$(_queue_lock_timeout)" || return 3
  local fd="$AID_LOCK_FD"

  local id status entry_plan dep dep_state reason
  local first_blocked="" first_reason=""
  # Command substitution, NOT `done < <(...)` (CP2 finding 5): a process
  # substitution's subshell inherits a duplicate of the lock fd, and flock only
  # drops when the LAST descriptor on the open file description closes — so a
  # subshell still draining a large id list would hold the lock past
  # aid_lock_release. `$(...)` is synchronous: the child has exited before the
  # loop starts. The same applies to the depends_on loop below.
  local ids_blob deps_blob
  ids_blob="$(queue_entry_ids "$file")"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    # An epic_id read out of the hand-editable queue file is untrusted input
    # (CP2 finding 1): never act on one that is not a well-formed id.
    if ! _queue_valid_id "$id"; then
      _aid_queue_warn "queue_claim_next: skipping malformed epic_id in ${file}"
      continue
    fi
    status="$(queue_get_status "$id" "$file")"
    case "$status" in
      pending|blocked|"") ;;
      *) continue ;;
    esac
    entry_plan="$(queue_get_field "$id" plan_id "$file")"
    [[ "$entry_plan" == "$plan_id" ]] || continue

    reason=""
    deps_blob="$(queue_get_deps "$id" "$file")"
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      dep_state="$(_queue_dep_state "$dep" "$file" "$root")"
      case "$dep_state" in
        merged) continue ;;
        # invalid_id is deliberately reported WITHOUT the id: the id is exactly
        # the untrusted string we refuse to propagate into a written field.
        invalid_id)     reason="dependency_id_invalid" ;;
        abandoned)
          local dep_plan; dep_plan="$(queue_get_field "$dep" plan_id "$file")"
          reason="dependency_abandoned:${dep}:plan=${dep_plan:-none}" ;;
        target_missing) reason="dependency_merge_target_missing:${dep}" ;;
        # IMP-272: the declared merge_target resolves but is an illegal anchor
        # (its own task branch / another plan's branch / a feature branch). Keep
        # the dependent BLOCKED with the illegal value class named, never claim it.
        target_unauthorized) reason="dependency_merge_target_unauthorized:${dep}" ;;
        no_proof)       reason="dependency_no_ancestry_proof:${dep}" ;;
        *)              reason="dependency_unmerged:${dep}" ;;
      esac
      break
    done <<< "$deps_blob"

    if [[ -z "$reason" ]]; then
      local rc=0
      _queue_apply_fields "$file" "$id" "status=running" "started_at=\"$(_queue_timestamp)\"" || rc=$?
      aid_lock_release "$fd"
      [[ "$rc" -ne 0 ]] && return "$rc"
      printf '%s\n' "$id"
      return 0
    fi

    # Belt and braces: the reason is assembled from ids that _queue_dep_state
    # has already charset-validated, so this can only fire on a future edit
    # that introduces a new reason shape.
    if ! _queue_valid_reason "$reason"; then reason="dependency_unresolved"; fi

    # AC4 says the block is recorded "with a recorded reason". This write used
    # to be `|| true`, so a failed write still produced a `blocked:<id>:<reason>`
    # line the caller believed was durable (CP2 finding 4). A write that MUST be
    # durable and was not is a transaction failure (rc 3), never a quiet 1.
    local wrc=0
    _queue_apply_fields "$file" "$id" "status=blocked" "reason=\"${reason}\"" || wrc=$?
    if [[ "$wrc" -ne 0 ]]; then
      aid_lock_release "$fd"
      _aid_queue_warn "queue_claim_next: could not record blocked/${reason} on ${id} (rc=${wrc}) — reporting the failure instead of an unrecorded block"
      return 3
    fi
    [[ -n "$first_blocked" ]] || { first_blocked="$id"; first_reason="$reason"; }
  done <<< "$ids_blob"

  aid_lock_release "$fd"
  if [[ -n "$first_blocked" ]]; then
    printf 'blocked:%s:%s\n' "$first_blocked" "$first_reason"
    return 1
  fi
  printf 'none\n'
  return 1
}

# ===========================================================================
# Standalone CLI — the surface aid-plan-fsm.sh's commands and the bats suite
# drive (mirrors aid-lock.sh / aid-plan-state.sh's own `main` convention).
# ===========================================================================
_aid_queue_write_usage() {
  cat <<'EOF'
Usage: aid-queue-write.sh <subcommand> [args...] [--queue <path>] [--project-root <path>]

Subcommands:
  set-status <epic_id> <status> [reason]   Transition one entry's status.
  set-plan   <epic_id> <plan_id> <target>  Record plan_id + merge_target.
  claim-next <plan_id>                     Atomically claim the next ready entry.
  get        <epic_id> <key>               Print one field (empty when null).
  deps       <epic_id>                     Print depends_on ids, one per line.
EOF
}

main() {
  local -a rest=()
  local sub="" a
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue)        AID_QUEUE_FILE="${2:?--queue requires a value}"; export AID_QUEUE_FILE; shift 2 ;;
      --project-root) AID_QUEUE_WRITE_PROJECT_ROOT="${2:?--project-root requires a value}"; export AID_QUEUE_WRITE_PROJECT_ROOT; shift 2 ;;
      *)              rest+=("$1"); shift ;;
    esac
  done
  set -- "${rest[@]+"${rest[@]}"}"
  sub="${1:-}"
  [[ $# -gt 0 ]] && shift

  case "$sub" in
    set-status) queue_set_status "$@"; exit $? ;;
    set-plan)   queue_set_plan "$@";   exit $? ;;
    claim-next) queue_claim_next "$@"; exit $? ;;
    get)        a="$(queue_get_field "$@")" || exit $?; printf '%s\n' "$a"; exit 0 ;;
    deps)       queue_get_deps "$@"; exit $? ;;
    -h|--help|"")
      _aid_queue_write_usage
      [[ -z "$sub" ]] && exit 2
      exit 0
      ;;
    *)
      _aid_queue_write_usage >&2
      echo "ERROR: unknown subcommand: $sub" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
