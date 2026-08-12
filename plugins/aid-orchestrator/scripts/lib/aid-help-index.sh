#!/usr/bin/env bash
# =============================================================================
# aid-help-index.sh — the two readers behind AID's help-coverage enforcement.
#
# WHY THIS EXISTS: `defaults/help-index.yaml` claims to be the authority on
# AID's public surfaces, and `commands/aid-help.md` claims to route to them.
# A claim nobody reads mechanically is a comment. These two functions are the
# mechanical readers — one enumerates what the repo ACTUALLY ships, the other
# reads what the index SAYS — so a test can compare them instead of a human
# noticing months later that four commands were never advertised anywhere.
#
# NO YAML FRONTMATTER PARSER: the enumerator scans a fixed leading line window
# for `user_invocable:`, the same approach `scripts/aid-lint-skill.sh` has
# shipped with since it was written (see its skill/command frontmatter blocks).
# Every command file in this repo has uniform frontmatter shape, so a parser
# would be new surface area buying nothing.
#
# CONTRACT
#   aid_help_enumerate_surfaces <plugin_root>
#     Prints one TSV row per PUBLIC surface, sorted by slash name:
#         <command>\t<plugin-root-relative path>\t<user_invocable value>
#     Two enumeration rules, and only two:
#       1. `commands/*.md` — a surface IFF its leading 6 lines carry
#          `user_invocable: true`. A command declaring `false` is deliberately
#          not a surface and is not printed (the index still gives it a row,
#          as `intentionally_internal`).
#       2. `skills/*/SKILL.md` — the glob, unconditionally. `/visual-companion`
#          is a surface without being a command file. Flat `skills/*.md` files
#          are agent-loaded reference documents, not surfaces, and a skill
#          directory without SKILL.md (e.g. `skills/setup/`) is not one either.
#     The third column reports the declared flag verbatim (`true`, `false` or
#     empty when absent) so a caller can tell a user-invocable surface from one
#     enumerated by the glob alone.
#     Paths are relative to <plugin_root>; help-index.yaml records them
#     relative to the REPO root, so a caller resolving both compares realpaths.
#     Returns 1 if <plugin_root> is not a directory.
#
#   aid_help_index_rows <index_path>
#     Prints one TSV row per `surfaces[]` entry, in file order:
#         <command>\t<file>\t<topic>\t<audience>\t<disposition>\t<final_turn>\t<purpose>\t<writes type tag>
#     An absent key prints its type tag rather than shifting the columns, so a
#     caller can fail on it explicitly. Requires `yq` (a repo-wide hard
#     dependency): missing yq or a missing/unparsable index returns 1 with a
#     message on stderr, never an empty success.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (aid-test-tier.sh header convention).
#
# Dependencies: bash, awk, sort, yq.
#
# **Last Updated:** 2026-08-11
# =============================================================================

if [[ -n "${_AID_HELP_INDEX_SH_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_AID_HELP_INDEX_SH_SOURCED=1

# The leading line windows scanned for frontmatter. Same shape as
# aid-lint-skill.sh: commands are checked over `sed -n '1,6p'`, skills over
# `sed -n '1,8p'` (their `description:` runs long enough to push the flag down).
AID_HELP_COMMAND_FM_LINES="${AID_HELP_COMMAND_FM_LINES:-6}"
AID_HELP_SKILL_FM_LINES="${AID_HELP_SKILL_FM_LINES:-8}"

# _aid_help_fm_scan <window> <file>… — one awk pass over MANY files, printing
# `<file>\t<declared user_invocable value>` for each. One pass rather than one
# process per file on purpose: this runs inside a merge-path test suite, and
# ~15 awk spawns measured 350 ms per bats case on the reference host — real
# money for a job that is grepping one line out of each of thirteen files.
# An absent flag prints as empty. Never guesses a default: an absent flag and
# `false` are different facts, and the caller decides what each means.
# `FNR <= win` rather than `nextfile` — mawk has no `nextfile`.
_aid_help_fm_scan() {
  local win="$1"; shift
  [[ $# -gt 0 ]] || return 0
  awk -v win="$win" '
    FNR == 1 { flag[FILENAME] = ""; late[FILENAME] = ""; order[++n] = FILENAME }
    # Match the KEY by regex, not by field equality: `user_invocable:true` with no
    # space is one awk field, so `$1 == "user_invocable:"` silently missed it and the
    # surface vanished from the enumeration — the one failure mode this whole suite
    # exists to make impossible.
    /^[[:space:]]*user_invocable[[:space:]]*:/ {
      v = $0; sub(/^[[:space:]]*user_invocable[[:space:]]*:/, "", v)
      gsub(/[[:space:]"'"'"']/, "", v)
      if (FNR <= win) { if (flag[FILENAME] == "") flag[FILENAME] = v }
      else            { if (flag[FILENAME] == "" && late[FILENAME] == "") late[FILENAME] = v }
    }
    # A flag sitting past the scan window is NOT the same as no flag. Reporting it as
    # absent would drop a real public command out of the bijection without a word;
    # `__late__` makes the caller fail loudly instead of guessing.
    END {
      for (i = 1; i <= n; i++) {
        f = order[i]
        printf "%s\t%s\n", f, (flag[f] != "" ? flag[f] : (late[f] != "" ? "__late__" : ""))
      }
    }
  ' "$@" 2>/dev/null
}

aid_help_enumerate_surfaces() {
  local root="${1:-}"
  if [[ -z "$root" || ! -d "$root" ]]; then
    printf 'aid_help_enumerate_surfaces: not a directory: %s\n' "$root" >&2
    return 1
  fi

  local -a cmd_files=() skill_files=()
  local f
  for f in "$root"/commands/*.md;      do [[ -f "$f" ]] && cmd_files+=("$f");   done
  for f in "$root"/skills/*/SKILL.md;  do [[ -f "$f" ]] && skill_files+=("$f"); done

  # THE SCAN'S EXIT STATUS IS CHECKED, because it used to be thrown away. Read
  # from `< <(_aid_help_fm_scan …)` the awk process's failure — an unreadable
  # command file is a fatal error that kills the whole pass — reached nobody:
  # the process substitution's status is not part of the `while` loop's, so
  # EVERY command silently vanished from the enumeration while this function
  # returned 0. A silent hole in the inventory is the one failure mode this
  # file exists to make impossible, so the scan output is captured first and a
  # failure is a hard error naming the surface set that could not be read.
  local cmd_rows="" skill_rows=""
  if ! cmd_rows="$(_aid_help_fm_scan "$AID_HELP_COMMAND_FM_LINES" ${cmd_files[@]+"${cmd_files[@]}"})"; then
    printf 'aid_help_enumerate_surfaces: frontmatter scan failed over %s/commands (unreadable file?) — refusing to report a partial surface list\n' "$root" >&2
    return 1
  fi
  if ! skill_rows="$(_aid_help_fm_scan "$AID_HELP_SKILL_FM_LINES" ${skill_files[@]+"${skill_files[@]}"})"; then
    printf 'aid_help_enumerate_surfaces: frontmatter scan failed over %s/skills (unreadable file?) — refusing to report a partial surface list\n' "$root" >&2
    return 1
  fi

  local file flag name
  {
    while IFS=$'\t' read -r file flag; do
      # `__late__` is emitted when the flag exists but sits past the scan window. It
      # is deliberately NOT filtered out here: dropping it would restore the silent
      # hole in a second place. It is enumerated with its marker value so the caller
      # sees a surface it cannot classify, and fails, instead of never hearing of it.
      [[ "$flag" == "true" || "$flag" == "__late__" ]] || continue
      name="${file##*/}"; name="${name%.md}"
      printf '/%s\tcommands/%s.md\t%s\n' "$name" "$name" "$flag"
    done <<<"$cmd_rows"

    while IFS=$'\t' read -r file flag; do
      # An empty capture is one empty line through a here-string, not zero
      # lines — without this guard a root with no skills printed `//SKILL.md`.
      [[ -n "$file" ]] || continue
      name="${file%/SKILL.md}"; name="${name##*/}"
      printf '/%s\tskills/%s/SKILL.md\t%s\n' "$name" "$name" "$flag"
    done <<<"$skill_rows"
  } | LC_ALL=C sort
}

aid_help_index_rows() {
  local index="${1:-}"
  if [[ -z "$index" || ! -f "$index" ]]; then
    printf 'aid_help_index_rows: no such index file: %s\n' "$index" >&2
    return 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    printf 'aid_help_index_rows: yq is required and was not found on PATH\n' >&2
    return 1
  fi

  local out
  # `writes` is emitted LAST and as a marker rather than a value: it is a list, so
  # it cannot share a @tsv row with scalars, but leaving it out of the reader
  # entirely meant nothing read it at all — the header calls it a required column
  # while ten of thirteen rows could lose it with every test still green. That is
  # the "declared but unenforced" defect this plan exists to kill, sitting inside
  # the file meant to prevent it, in the very column Step 5 writes its ownership
  # decisions into. The value is yq's TYPE TAG: `!!seq` for a real list (empty or not), `!!null` when the key is absent. The caller asserts the tag, so a scalar in that column — `writes: "read-only"`, `writes: 5` — is a violation rather than a filled-in field.
  out="$(yq -r '.surfaces[] | [.command, .file, .topic, .audience, .disposition, .final_turn, .purpose, (.writes | tag)] | @tsv' "$index" 2>&1)" || {
    printf 'aid_help_index_rows: yq failed to read %s: %s\n' "$index" "$out" >&2
    return 1
  }
  if [[ -z "$out" ]]; then
    printf 'aid_help_index_rows: %s has no surfaces[] rows\n' "$index" >&2
    return 1
  fi
  printf '%s\n' "$out"
}
