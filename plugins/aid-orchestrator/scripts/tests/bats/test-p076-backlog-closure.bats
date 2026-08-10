#!/usr/bin/env bats
# test-p076-backlog-closure.bats — P076 Step 14: the deferred-work registry.
#
# WHAT THIS PROVES. Every item P076 consciously deferred exists as a numbered
# IMP entry in the project backlog AND is cross-referenced from the source
# document's §16 STILL OPEN block. Nothing survives only in chat or plan prose.
#
# WHY THERE IS NO `skip` ANYWHERE IN THIS FILE. Earlier in this same plan a
# closure test SKIPPED when its target document was absent — and a skip is
# green, so a clone reported "all passing" while checking nothing. Both target
# documents are TRACKED, so their absence is a real defect, not an environment
# quirk. Case 1 therefore FAILS loudly when either file is missing, and every
# later case re-asserts readability instead of assuming it. If this suite is
# green, it checked something.
#
# WHAT IS ASSERTED, AND AT WHICH ALTITUDE.
#   - Token PRESENCE, never table layout: the backlog's format may drift, so
#     the tests grep for `IMP-<n>` headings and `file:line` shapes rather than
#     for columns, bullets or heading levels (step Edge Cases).
#   - The §16 count is DERIVED, not transcribed: the block's own still-open
#     bullet lines are counted, and the number of distinct IMP tokens must
#     equal it. The plan-level "five deferrals" is then asserted once, on top
#     of the derived number, so a sixth deferral added without a backlog entry
#     breaks case 4 before anyone has to remember the literal 5.
#   - Hook points must be REAL-SHAPED: each of the five entries must cite at
#     least one `path:line`. This suite cannot know whether the cited line
#     still says what the entry claims (line numbers drift with every commit);
#     it asserts the citation exists and names an in-repo path that exists.
#     Content of the cited lines was verified by hand at authoring time.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"; export REPO_ROOT
  BACKLOG="$REPO_ROOT/docs/plans/2026-06-29-BACKLOG.md"; export BACKLOG
  SOURCE_DOC="$REPO_ROOT/docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md"
  export SOURCE_DOC
  BLOCK="$BATS_TEST_TMPDIR/still-open-16.txt"; export BLOCK
}

# _extract_block — the §16 STILL OPEN block, and nothing else.
#
# §16 is bounded by its own heading and the next `## ` heading (§16a). Inside
# it, the block runs from the `STILL OPEN after P076` marker to the end of that
# blockquote (the first line that is not a `>` line). Other sections of this
# document carry their own STILL OPEN blocks (§16a, §17) — they are deliberately
# outside these bounds, so a stray IMP token there can never satisfy this suite.
_extract_block() {
  awk '
    /^## 16\. / { in16 = 1; next }
    /^## /      { in16 = 0 }
    in16 && /STILL OPEN after P076/ { inblk = 1 }
    inblk && !/^>/ { inblk = 0 }
    inblk { print }
  ' "$SOURCE_DOC" > "$BLOCK"
}

@test "1: both target documents exist and are non-empty (never skip — a skip is green)" {
  [ -f "$BACKLOG" ] || {
    echo "FAIL: backlog missing at $BACKLOG — this file is tracked; its absence is a defect, not a reason to skip" >&2
    false
  }
  [ -f "$SOURCE_DOC" ] || {
    echo "FAIL: source document missing at $SOURCE_DOC — this file is tracked; its absence is a defect, not a reason to skip" >&2
    false
  }
  [ -s "$BACKLOG" ]
  [ -s "$SOURCE_DOC" ]
}

@test "2: §16 carries a STILL OPEN block naming P076" {
  _extract_block
  [ -s "$BLOCK" ] || {
    echo "FAIL: no 'STILL OPEN after P076' blockquote found inside '## 16.' of $SOURCE_DOC" >&2
    false
  }
  grep -q 'STILL OPEN after P076' "$BLOCK"
}

@test "3: every still-open line in the §16 block carries an IMP-number token" {
  _extract_block
  # A still-open line is a bullet inside the block. Every one of them must name
  # an IMP number — that is the whole promise "each registered as an IMP entry".
  local bullets naked
  bullets="$(grep -c '^> - ' "$BLOCK" || true)"
  [ "$bullets" -gt 0 ] || {
    echo "FAIL: the §16 STILL OPEN block has no bullet lines at all" >&2
    false
  }
  naked="$(grep '^> - ' "$BLOCK" | grep -vc 'IMP-[0-9][0-9]*' || true)"
  if [ "$naked" -ne 0 ]; then
    echo "FAIL: $naked still-open bullet(s) in §16 carry no IMP-number token:" >&2
    grep '^> - ' "$BLOCK" | grep -v 'IMP-[0-9][0-9]*' >&2
    false
  fi
}

@test "4: the block enumerates exactly five distinct IMP tokens, and the count is derived from the block itself" {
  _extract_block
  local bullets tokens
  bullets="$(grep -c '^> - ' "$BLOCK" || true)"
  tokens="$(grep -o 'IMP-[0-9][0-9]*' "$BLOCK" | sort -u | wc -l | tr -d ' ')"

  # Derived assertion: one distinct IMP per still-open bullet. Add a sixth
  # deferral and this fails until it, too, gets its own number.
  [ "$tokens" -eq "$bullets" ] || {
    echo "FAIL: $bullets still-open bullet(s) but $tokens distinct IMP token(s) — every bullet needs its own entry" >&2
    grep '^> - ' "$BLOCK" >&2
    false
  }

  # Plan-level assertion, on top of the derived number: P076 deferred five items.
  [ "$tokens" -eq 5 ] || {
    echo "FAIL: expected the five P076 deferrals, found $tokens: $(grep -o 'IMP-[0-9][0-9]*' "$BLOCK" | sort -u | tr '\n' ' ')" >&2
    false
  }
}

@test "5: every IMP number named in the §16 block exists as an entry in the backlog" {
  _extract_block
  local missing=0 imp
  while read -r imp; do
    if ! grep -qE "^#+ .*\b${imp}\b" "$BACKLOG"; then
      echo "FAIL: ${imp} is cross-referenced from §16 but has no entry heading in $BACKLOG" >&2
      missing=$((missing + 1))
    fi
  done < <(grep -o 'IMP-[0-9][0-9]*' "$BLOCK" | sort -u)
  [ "$missing" -eq 0 ]
}

@test "6: each of the five entries states what shipped instead, why it was deferred, and a file:line hook point" {
  _extract_block
  local imp body bad=0
  while read -r imp; do
    # The entry body: from its own heading to the next heading of any level.
    body="$(awk -v imp="$imp" '
      $0 ~ "^#+ .*" imp "[^0-9]" { inblk = 1; print; next }
      inblk && /^#+ / { inblk = 0 }
      inblk { print }
    ' "$BACKLOG")"
    [ -n "$body" ] || { echo "FAIL: empty entry body for ${imp}" >&2; bad=$((bad + 1)); continue; }

    grep -qi 'shipped instead' <<<"$body" || {
      echo "FAIL: ${imp} does not say what shipped instead" >&2; bad=$((bad + 1)); }
    grep -qi 'why deferred' <<<"$body" || {
      echo "FAIL: ${imp} does not say why it was deferred" >&2; bad=$((bad + 1)); }
    grep -qi 'hook point' <<<"$body" || {
      echo "FAIL: ${imp} names no hook point" >&2; bad=$((bad + 1)); }

    # A hook point is a path:line, and the path must exist in this repository.
    local cite path
    cite="$(grep -oE '[A-Za-z0-9._/-]+\.(sh|md|bats|yaml|json|js):[0-9]+' <<<"$body" | head -1 || true)"
    [ -n "$cite" ] || {
      echo "FAIL: ${imp} cites no file:line hook point" >&2; bad=$((bad + 1)); continue; }
    path="${cite%:*}"
    [ -f "$REPO_ROOT/$path" ] || {
      echo "FAIL: ${imp} cites '${cite}' but '$path' does not exist in the repository" >&2
      bad=$((bad + 1)); }
  done < <(grep -o 'IMP-[0-9][0-9]*' "$BLOCK" | sort -u)
  [ "$bad" -eq 0 ]
}

@test "7: the five IMP numbers are newly allocated — no duplicate entry headings in the backlog" {
  _extract_block
  local imp count bad=0
  while read -r imp; do
    count="$(grep -cE "^#+ .*\b${imp}\b" "$BACKLOG" || true)"
    if [ "$count" -ne 1 ]; then
      echo "FAIL: ${imp} has ${count} entry headings in the backlog (expected exactly 1)" >&2
      bad=$((bad + 1))
    fi
  done < <(grep -o 'IMP-[0-9][0-9]*' "$BLOCK" | sort -u)
  [ "$bad" -eq 0 ]
}
