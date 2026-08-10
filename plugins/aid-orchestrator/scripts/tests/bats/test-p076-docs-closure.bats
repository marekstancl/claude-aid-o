#!/usr/bin/env bats
# test-p076-docs-closure.bats — P076 Step 17: the release metadata and the
# contributor documentation say what shipped.
#
# WHAT THIS PROVES.
#   1. The two CHANGELOGs are byte-identical, which CLAUDE.md makes mandatory
#      and which nothing else in the suite checks.
#   2. The newest CHANGELOG entry actually describes THIS plan's mechanisms —
#      not merely that some entry exists.
#   3. `docs/extending-aid.md` carries the three contributor sections the plan
#      required (owned jobs, declaring services, the recovery policy).
#   4. The §16 STILL OPEN block still carries its IMP tokens — the Step 14
#      regression, re-asserted from this side so an edit to the annotation
#      cannot quietly drop the cross-reference.
#   5. Every skill, command and agent card this plan touched carries a
#      `**Last Updated:**` stamp.
#
# WHY THERE IS NO `skip` ANYWHERE IN THIS FILE. The step's Edge Cases allowed a
# named skip for a checkout with no `docs/`. That premise does not hold and was
# checked rather than assumed: `git ls-files docs/` lists both target documents,
# so `docs/extending-aid.md` and the source document are TRACKED and present in
# every clone that carries this suite — the suite lives in the same repository
# they do. A skip here would therefore only ever fire on a broken checkout, and
# a skip is GREEN. Earlier in this same plan a closure test skipped when its
# target was absent and reported all-passing while checking nothing; that is the
# pattern this file refuses to repeat. Missing target ⇒ loud failure.
#
# WHAT IS DELIBERATELY NOT ASSERTED. The CHANGELOG section HEADER. The entry
# lands unversioned-pending and the plan-final release sub-phase versions it, so
# pinning either form would guarantee a red suite on one side of the release.
# The assertions read the newest `## [` section whatever it is called.
#
# ONE FINDING IS PINNED RATHER THAN HIDDEN — see case 8: `commands/aid-help.md`
# gained content in this plan (commit 2ccc4e0, 2026-08-09) but its stamp still
# reads 2026-08-07. Bumping it from this step would fake evidence that its
# owning step reviewed it, so the staleness is reported to the controller and
# recorded here as a named exception. A SECOND stale file turns case 8 red.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"; export REPO_ROOT
  ROOT_CL="$REPO_ROOT/CHANGELOG.md"; export ROOT_CL
  PLUGIN_CL="$REPO_ROOT/plugins/aid-orchestrator/CHANGELOG.md"; export PLUGIN_CL
  EXTENDING="$REPO_ROOT/docs/extending-aid.md"; export EXTENDING
  SOURCE_DOC="$REPO_ROOT/docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md"
  export SOURCE_DOC
}

_fail() {
  echo "FAIL: $1" >&2
  false
}

# _newest_entry <changelog> — the newest `## [` section, exclusive of the next.
_newest_entry() {
  awk '/^## \[/ { n++ } n == 1 { print } n > 1 { exit }' "$1"
}

# _still_open_block — §16's STILL OPEN blockquote, and nothing else. Same bounds
# as test-p076-backlog-closure.bats: §16 ends at the next `## ` heading (§16a),
# and the block ends at the first line that is not a `>` line, so the STILL OPEN
# blocks of §16a and §17 can never satisfy an assertion here.
_still_open_block() {
  awk '
    /^## 16\. / { in16 = 1; next }
    /^## /      { in16 = 0 }
    in16 && /STILL OPEN after P076/ { inblk = 1 }
    inblk && !/^>/ { inblk = 0 }
    inblk { print }
  ' "$SOURCE_DOC"
}

# The three contributor headings the step required, as literal strings.
_h1='### The owned-job contract'
_h2='### Declaring services'
_h3='### The recovery policy, and how a consumer changes it'

@test "1: every target document exists and is non-empty (never skip — a skip is green)" {
  local f
  for f in "$ROOT_CL" "$PLUGIN_CL" "$EXTENDING" "$SOURCE_DOC"; do
    [ -f "$f" ] || _fail "missing target document '$f' — every one of these is tracked in this repository, so its absence is a defect, not a reason to skip"
    [ -s "$f" ] || _fail "target document '$f' is empty"
  done
}

@test "2: the two CHANGELOGs are byte-identical" {
  run cmp -s "$ROOT_CL" "$PLUGIN_CL"
  [ "$status" -eq 0 ] || {
    echo "FAIL: CHANGELOG.md and plugins/aid-orchestrator/CHANGELOG.md differ; CLAUDE.md requires them identical. First differences:" >&2
    diff "$ROOT_CL" "$PLUGIN_CL" | head -40 >&2
    false
  }
}

@test "3: the byte-identity assertion is not vacuous (a one-byte edit turns it red)" {
  local a="$BATS_TEST_TMPDIR/a.md" b="$BATS_TEST_TMPDIR/b.md"
  cp "$ROOT_CL" "$a"
  cp "$PLUGIN_CL" "$b"
  printf 'x\n' >> "$b"
  run cmp -s "$a" "$b"
  [ "$status" -ne 0 ] || _fail "cmp reported two provably different files as identical — the identity assertion in case 2 proves nothing"
}

@test "4: the newest CHANGELOG entry carries the three sections and describes THIS plan" {
  local entry="$BATS_TEST_TMPDIR/entry.md"
  _newest_entry "$ROOT_CL" > "$entry"
  [ -s "$entry" ] || _fail "no '## [' section found in $ROOT_CL"

  local h
  for h in '### Added' '### Changed' '### Fixed'; do
    grep -qF "$h" "$entry" || _fail "the newest CHANGELOG entry has no '$h' section"
  done

  # Named mechanisms, not adjectives: each of these shipped in this plan and is
  # the one word a reader would search for.
  local token
  for token in 'run_mode' 'auto_resume_required.json' 'auto_controller' \
               'aid-fsm.sh resume' 'needs_services' 'auto-recovery.yaml'; do
    grep -qF "$token" "$entry" \
      || _fail "the newest CHANGELOG entry never mentions '$token' — it does not describe what P076 shipped"
  done

  # Entry-format rule from CLAUDE.md: every bullet is `- **Name** — text`.
  local bad
  bad="$(grep -n '^- ' "$entry" | grep -v '^[0-9]*:- \*\*' || true)"
  [ -z "$bad" ] || _fail "these CHANGELOG bullets do not follow '- **Bold Name** — description':
$bad"
}

@test "5: docs/extending-aid.md carries the three contributor sections" {
  local h
  for h in "$_h1" "$_h2" "$_h3"; do
    grep -qF -- "$h" "$EXTENDING" \
      || _fail "docs/extending-aid.md has no section heading '$h'"
  done
}

@test "6: the section assertion is not vacuous (removing a heading turns it red)" {
  local copy="$BATS_TEST_TMPDIR/extending.md"
  grep -vF -- "$_h2" "$EXTENDING" > "$copy"
  run grep -qF -- "$_h2" "$copy"
  [ "$status" -ne 0 ] \
    || _fail "the heading '$_h2' was still found after being deleted — case 5's grep matches something other than the heading"
}

@test "7: §16's STILL OPEN block still carries an IMP token on every item" {
  local block="$BATS_TEST_TMPDIR/still-open.txt"
  _still_open_block > "$block"
  [ -s "$block" ] || _fail "no 'STILL OPEN after P076' blockquote inside '## 16.' of $SOURCE_DOC — the Step 14 cross-reference is gone"

  # Every bullet line of the block names an IMP number.
  local naked
  naked="$(grep -n '^> - ' "$block" | grep -v 'IMP-[0-9]' || true)"
  [ -z "$naked" ] || _fail "these §16 still-open bullets carry no IMP-<n> token, so they exist only as prose:
$naked"

  # And the five this plan allocated are all still there.
  local n
  for n in 476 477 478 479 480; do
    grep -q "IMP-${n}" "$block" \
      || _fail "IMP-${n} is no longer cross-referenced from the §16 STILL OPEN block"
  done

  # The count is derived, then checked against the plan's five — a sixth
  # deferral added with no number breaks this before anyone recalls the literal.
  local bullets tokens
  bullets="$(grep -c '^> - ' "$block")"
  tokens="$(grep -oE 'IMP-[0-9]+' "$block" | sort -u | wc -l)"
  [ "$bullets" = "$tokens" ] \
    || _fail "the §16 block has ${bullets} still-open bullets but ${tokens} distinct IMP tokens"
  [ "$tokens" = "5" ] || _fail "expected 5 distinct IMP tokens in the §16 block, found ${tokens}"
}

@test "8: every skill, command and agent card P076 touched carries a Last Updated stamp" {
  # The list is the set of instruction files this plan modified across its three
  # EPICs, enumerated at authoring time from `git diff` over the plan branch.
  local rel stamp stale=""
  local -a touched=(
    skills/agent-protocol.md
    skills/pipeline.md
    skills/role-cards.md
    commands/aid-run.md
    commands/aid-status.md
    commands/aid-help.md
    agents/auditor.md
    agents/curator.md
    agents/gate-fixer.md
    agents/implementer.md
    agents/project-scanner.md
    agents/reporter.md
    agents/simplifier.md
    agents/test-portfolio-analyst.md
    agents/verifier.md
  )
  for rel in "${touched[@]}"; do
    local f="$REPO_ROOT/plugins/aid-orchestrator/$rel"
    [ -f "$f" ] || _fail "P076 modified '$rel' but the file is gone"
    stamp="$(grep -oE '\*\*Last Updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
    [ -n "$stamp" ] || _fail "'$rel' was modified by P076 and carries no '**Last Updated:** YYYY-MM-DD' stamp"
    # P076's first instruction-file commit landed 2026-08-09. A stamp older than
    # that was not bumped by the step that changed the file.
    if [[ "$stamp" < "2026-08-09" ]]; then
      stale+="${rel} (${stamp})"$'\n'
    fi
  done

  # The ONE known-stale file, reported to the controller rather than silently
  # re-stamped from this step (a stamp added here would be evidence of nothing).
  local expected="commands/aid-help.md (2026-08-07)"$'\n'
  [ "$stale" = "$expected" ] || _fail "the set of stale Last Updated stamps changed.
expected exactly:
${expected}
found:
${stale:-<none>}"
}
