#!/usr/bin/env bash
# aid-ac-extract.sh — shared Acceptance Criteria extractor (P083 Step 2)
#
# Replaces the two copy-pasted awk blocks in aid-plan-to-epic.sh
# (step_ac / step_ac_raw) that only matched flush-left `- ` lines and
# silently dropped every indented continuation line — truncating a
# multi-line criterion mid-sentence in both the human EPIC section and
# the machine-read `ac[]`.
#
# aid_ac_extract_criteria <step_content_on_stdin>
#   Reads a step's markdown body from stdin, finds the
#   `**Acceptance Criteria**` (with or without a trailing colon) section,
#   and prints ONE LINE PER CRITERION to stdout: the bullet marker and any
#   `[ ]`/`[x]` checkbox stripped, continuation lines joined with a single
#   space. Output is otherwise unprefixed/unwrapped — callers add their own
#   `[role]` tag or checkbox syntax.
#
# Extraction rules (all pinned by
# scripts/tests/bats/test-ac-extraction.bats):
#   - A criterion begins at a flush-left `- ` bullet.
#   - It continues through indented lines (any leading whitespace),
#     joined with a single space each — this includes an indented fenced
#     block and a code span with a leading dash (neither is a flush-left
#     bullet, so neither is mistaken for a new criterion).
#   - It ends at: the next flush-left `- ` bullet, a blank line, a
#     flush-left non-bullet line (prose/heading/fence opener — the
#     criterion ends and a LATER indented line does not resume it), the
#     section terminator (any other `**...**` heading), or end of input.
aid_ac_extract_criteria() {
  awk '
    # Emit the criterion built up so far, if any, and start over.
    function flush() {
      if (accumulating) { print crit; accumulating = 0; crit = "" }
    }
    BEGIN { in_ac = 0; accumulating = 0; crit = "" }
    {
      gsub(/\r$/, "")
      line = $0

      if (line ~ /^\*\*Acceptance Criteria:?\*\*/) {
        flush()
        in_ac = 1
        next
      }
      if (in_ac && line ~ /^\*\*/) {          # section terminator
        flush()
        in_ac = 0
        next
      }
      if (!in_ac) next

      if (line == "") { flush(); next }

      if (line ~ /^-[[:space:]]/) {           # a new criterion starts here
        flush()
        crit = line
        sub(/^-[[:space:]]+/, "", crit)       # drop the bullet
        sub(/^\[[ xX]\][[:space:]]*/, "", crit)   # drop a checkbox if present
        accumulating = 1
        next
      }

      if (line ~ /^[^[:space:]]/) {           # prose/heading/fence opener
        flush()
        next
      }

      # Indented line: continuation of the active criterion, else ignored
      # (an indented line with no active criterion does not resume one) —
      # UNLESS it itself looks like a new section heading (`**...**`), in
      # which case it terminates the criterion rather than being absorbed
      # (Error Handling: "the ambiguity is resolved toward under-joining,
      # never toward swallowing the next section").
      trimmed = line
      sub(/^[[:space:]]+/, "", trimmed)
      if (trimmed ~ /^\*\*/) { flush(); next }
      if (accumulating) {
        crit = crit " " trimmed
      }
    }
    END { flush() }
  '
}
