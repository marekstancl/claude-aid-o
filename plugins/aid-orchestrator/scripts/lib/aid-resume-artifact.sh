#!/usr/bin/env bash
# =============================================================================
# aid-resume-artifact.sh — the SHARED vocabulary of the P076 continuation
# mechanism. One definition per concept, sourced by every consumer.
#
# It exists because the mechanism has TWO readers (the gate runner writes the
# pointer and the row checkpoints; the FSM reads both in `init`'s preflight and
# in `resume`) and a per-file copy of any of these definitions fails OPEN: a
# renamed artifact basename makes the live-job refusal evaluate an empty glob
# and return 0, and a private re-implementation of the pending-pointer scan
# makes one reader resolve a pointer the other cannot.
#
# Provides:
#   AID_RESUME_ARTIFACT_BASENAME   the run's ONE continuation pointer filename
#   AID_GATE_ROW_KEY_BASENAME      the per-run gate-row secret's filename
#   aid_repo_revision              <repo>            -> "<head> <tree>"
#   aid_gate_row_revision          <repo>            -> "<head> <tree>", normalized
#   aid_resume_resolve_pending     <jobs_dir> <fp>   -> job id | ""
#   aid_gate_row_run_key           <evidence_dir>    -> 64-hex secret | ""
#   aid_gate_row_home              <evidence_dir>    -> canonical dir | ""
#   aid_gate_row_binding_key       <key> <gate> <head> <tree> <home> -> 64-hex | ""
#
# Sourced, never executed. Re-source safe.
# =============================================================================

[[ -n "${_AID_RESUME_ARTIFACT_LIB_LOADED:-}" ]] && return 0
_AID_RESUME_ARTIFACT_LIB_LOADED=1

# THE artifact basename. Both the writer (aid-run-gates.sh) and the three FSM
# globs read it from here; a rename is therefore a one-line change that cannot
# silently disable the live-job refusal.
AID_RESUME_ARTIFACT_BASENAME="auto_resume_required.json"

# THE per-run gate-row secret's filename. A dotfile so it never appears in the
# `ls -1 <evidence_dir>` listings other consumers assert against, and it lives
# BESIDE gates_rows/ rather than inside it.
AID_GATE_ROW_KEY_BASENAME=".gate_row_key"

_AID_RESUME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_RESUME_JOB_SH="${_AID_RESUME_LIB_DIR}/../aid-job.sh"

# aid_repo_revision <repo> — "<head> <tree>", the SAME pair aid-job.sh binds a
# job record to. Delegated to `aid-job.sh revision` for the same reason the
# command fingerprint is delegated to `aid-job.sh fingerprint`: there is one
# implementation of the formula, and a caller that needs the answer asks for it
# instead of copying it. Unresolvable → "none none" (the supervisor's own
# no-git marker), which every drift check treats as "unknowable, not drifted".
aid_repo_revision() {
  local repo="${1:-}" out=""
  local -a args=(revision)
  [[ -n "$repo" ]] && args+=(--repo "$repo")   # array, so a path with spaces survives
  [[ -f "$_AID_RESUME_JOB_SH" ]] || { printf 'none none'; return 0; }
  out="$(bash "$_AID_RESUME_JOB_SH" "${args[@]}" 2>/dev/null || true)"
  [[ -n "$out" ]] || out="none none"
  printf '%s' "$out"
}

# aid_gate_row_revision <repo> — THE (head, tree) pair a gate-row checkpoint is
# bound to, for BOTH writers: the in-line one in aid-run-gates.sh and the
# resume-time one in aid-fsm.sh. `aid_repo_revision` above answers the raw
# question; this adds the ONE normalization the binding depends on — the
# supervisor's "none"/"nogit" markers mean "no revision", and a row bound to the
# literal string "none" would compare equal to any other repo that has no git.
#
# It exists because the normalization used to be copied into both writers, and
# the copies had already drifted: the resume-side one fell back to
# `git rev-parse HEAD` in the CALLER's working directory when the job record
# named no repo, so a resume run from a different checkout could bind a row to a
# head the runner would never compare against. There is now no fallback: the
# revision of a row is always the revision of the repo the JOB ran in, and
# "unknowable" stays empty rather than borrowing the caller's.
aid_gate_row_revision() {
  local repo="${1:-}" rev head tree
  rev="$(aid_repo_revision "$repo")"
  head="${rev%% *}"; tree="${rev##* }"
  # BOTH halves are normalized, not just the head. The supervisor answers
  # "nogit nogit" outside a repository, and normalizing only the head left the
  # asymmetric pair ("", "nogit") — a tree that LOOKS like a real digest and
  # compares equal to every other non-repo run, which is the shape a staleness
  # check is least able to question. "No revision" has to look like no revision
  # on both sides (found while investigating ACTA's 2026-08-31 checkpoint
  # report; not the defect that report describes, but a real one beside it).
  [[ "$head" == "none" || "$head" == "nogit" ]] && head=""
  [[ "$tree" == "none" || "$tree" == "nogit" ]] && tree=""
  printf '%s %s' "$head" "$tree"
}

# aid_resume_resolve_pending <jobs_dir_abs> <command_fingerprint>
#   THE resolution of a `pending` (PRE-SPAWN) pointer, shared by `resume` and by
#   `init`'s live-job preflight. `pending` is not a gap in the record: it says
#   "a job with THIS fingerprint was about to be started HERE", so the jobs dir
#   is scanned for a record carrying that fingerprint. Echoes the job id when
#   one is found, nothing when none is. An empty fingerprint never matches —
#   otherwise a malformed pointer would adopt an arbitrary job.
aid_resume_resolve_pending() {
  local jobs_dir="${1:-}" fp="${2:-}" d rec cand=""
  [[ -n "$fp" && -d "$jobs_dir" ]] || return 0
  for d in "$jobs_dir"/*/; do
    [[ -f "${d}job.json" ]] || continue
    rec="$(jq -r '.command_fingerprint // ""' "${d}job.json" 2>/dev/null || echo "")"
    [[ "$rec" == "$fp" ]] || continue
    cand="$(basename "$d")"
  done
  printf '%s' "$cand"
}

# aid_gate_row_home <evidence_dir> — the canonical, symlink-resolved absolute
# path of the directory a gate-row binding belongs to, or nothing when that
# directory does not exist. The runner addresses its evidence directory
# RELATIVELY (from the project root) and `resume` addresses the same directory
# ABSOLUTELY, so the raw strings are not comparable and only the physical path
# is. Nothing here creates a directory.
aid_gate_row_home() {
  local d="${1:-}"
  [[ -n "$d" && -d "$d" ]] || return 0
  ( cd "$d" 2>/dev/null && pwd -P ) || true
}

# aid_gate_row_run_key <evidence_dir> — the run's own gate-row secret.
#
# LIFECYCLE, stated in full because the previous version had none:
#   created      — on first use, by whichever of the two writers (`run-all` or
#                  `resume`) reaches an EXISTING evidence directory first.
#   reused       — by every later invocation of that run: a re-run, a resume and
#                  the restore pass all have to agree, and re-keying mid-run
#                  would invalidate every row the run already wrote.
#   regenerated  — never. A key file that is not a key is refused, not replaced
#                  (see below), and a valid one is never rewritten.
#   removed      — never on its own, and deliberately so: the key is the binding
#                  for the `gates_rows/*.json` checkpoints beside it, so deleting
#                  it while they exist would silently invalidate a crashed run's
#                  own evidence — the one case the checkpoints exist for. Its
#                  lifetime is the evidence directory's, and it dies with it.
#   copied       — inert. The binding below is taken over the checkpoint's HOME
#                  directory, so a key that travels with an archived or copied
#                  evidence tree verifies nothing at the new path: every row in
#                  the copy is refused as `row_not_written_by_this_run`. Nothing
#                  in this codebase copies the file — the two archive sites move
#                  a job directory (`jobs/<id>.superseded-*`) and the pointer
#                  (`.claimed-*`), neither of which is near it — and if a future
#                  one does, it carries no authority with it.
#
# WHY: a checkpointed gate row is replayed into a report as a gate RESULT, and
# `_checkpoint.head` alone cannot establish that the run's own writers produced
# it — `git rev-parse HEAD` is public and guessable, so any actor that can write
# the row file can satisfy it. The binding below is a keyed digest over a 256-bit
# value this run generated, so a hand-written row is refused.
#
# HONEST LIMIT, stated because a guard nobody understands is a guard nobody
# maintains: this is not a cryptographic authority boundary. The key file lives
# in the same evidence tree as the rows, so an actor that can READ that tree can
# still forge a row. What it does defeat is the case that was demonstrated —
# writing a plausible row file (plus a public HEAD) and having it accepted — and
# it makes forgery require reading a specific 0600 file rather than running
# `git rev-parse`.
#
# Echoes the key, or nothing when the directory does not exist or is unwritable.
# Nothing here ever CREATES an evidence directory (the same discipline the
# execution ledger and the row checkpoints follow).
aid_gate_row_run_key() {
  local evidence_dir="${1:-}" f key=""
  [[ -n "$evidence_dir" && -d "$evidence_dir" ]] || return 0
  f="${evidence_dir}/${AID_GATE_ROW_KEY_BASENAME}"
  if [[ -f "$f" ]]; then
    key="$(tr -d '[:space:]' < "$f" 2>/dev/null || true)"
    [[ "$key" =~ ^[0-9a-f]{64}$ ]] && { printf '%s' "$key"; return 0; }
    # A key file that is not a key is NEVER silently replaced: overwriting it
    # would invalidate every row this run already wrote, and inventing a new one
    # over a corrupt file is exactly the "repair and continue" behaviour the
    # active-runs writer is fail-closed about. Refuse instead.
    return 0
  fi
  key="$(head -c 32 /dev/urandom 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1 || true)"
  [[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 0
  local tmp
  tmp="$(mktemp "${f}.XXXXXX" 2>/dev/null)" || return 0
  chmod 0600 "$tmp" 2>/dev/null || true
  if printf '%s\n' "$key" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null; then
    printf '%s' "$key"
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 0
}

# aid_gate_row_binding_key <run_key> <gate> <head> <tree> <home> — the value
# stored as `_checkpoint.key` and re-derived by the restore pass. Keyed over the
# run secret AND the gate name AND the revision AND the checkpoint's home
# directory, so a row cannot be moved between gates, between revisions, or
# between directories. Empty run key → EMPTY result, so a run that could not
# establish a key can neither write a binding nor accept one (the restore pass
# refuses on an empty expectation — fail closed, never fail open).
#
# `home` is what makes a copied evidence tree inert rather than portable. It is
# NOT an answer to the accepted residual (an actor that can read the key file can
# still forge a row in place, and that is a deliberate stopping point) — it is
# the lifecycle property: authority does not travel with a copy.
aid_gate_row_binding_key() {
  local key="${1:-}" gate="${2:-}" head="${3:-}" tree="${4:-}" home="${5:-}"
  [[ -n "$key" ]] || return 0
  printf '%s\0%s\0%s\0%s\0%s\0' "$key" "$gate" "$head" "$tree" "$home" \
    | sha256sum 2>/dev/null | cut -d' ' -f1
}
