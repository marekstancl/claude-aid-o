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
#   6. EVERY surface describing `blocked_for_pm` — `aid-run.md`'s state table
#      AND the user-facing `aid-help.md` list — names a writer that really
#      writes the value, pinned from both sides, because that claim's earlier
#      "nothing writes it yet" survived the arrival of its writer unnoticed.
#   7. The CHANGELOG and `docs/extending-aid.md` agree on what the run-mode
#      advice event is PROVEN to do — a claim retracted from one surface for
#      being unprovable may not survive on the other.
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
# The assertions select P076's section by CONTENT (`_p076_entry`), never by its
# heading and never by its position — the next release adds a newer heading on
# top and must not turn this suite red.
#
# THE ONE KNOWN-STALE STAMP IS GONE, AND SO IS THE PIN THAT PROTECTED IT.
# Case 8 used to assert the stale set was EXACTLY `commands/aid-help.md
# (2026-08-07)`: the sweep found the one P076-touched file nobody re-stamped,
# recorded it as expected, and nobody asked what was stale INSIDE it — the false
# `blocked_for_pm` "nothing writes it yet" claim, on the surface a PM actually
# reads. That claim is fixed, the stamp is bumped, case 8 now requires the stale
# set to be EMPTY, and case 9 pins the claim on `aid-help.md` as well as on
# `aid-run.md`. Both assertions now fail on a wrong state, never on a corrected
# one.

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

# _p076_entry <changelog> — THIS PLAN's `## [` section, exclusive of the next.
#
# WHY NOT "the newest section". The previous form took the FIRST `## [` block,
# which pins P076's entry to a POSITION. The next release adds a newer heading
# on top and every content assertion below then fails on unrelated, correct
# work — the file's own header reasons carefully about not pinning the version
# HEADER and then pinned something strictly more fragile. The section is
# selected by CONTENT instead: the one whose body names this plan's continuation
# artifact. It stays correct under any number of later releases, and it goes red
# for the right reason — P076's entry lost its content, or vanished.
_p076_entry() {
  awk '
    /^## \[/ {
      if (started && hit) { printf "%s", buf; exit }
      started = 1; buf = ""; hit = 0
    }
    started { buf = buf $0 "\n" }
    started && /auto_resume_required\.json/ { hit = 1 }
    END { if (started && hit) printf "%s", buf }
  ' "$1"
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

@test "4: THIS plan's CHANGELOG entry carries the three sections and describes what it shipped" {
  local entry="$BATS_TEST_TMPDIR/entry.md"
  _p076_entry "$ROOT_CL" > "$entry"
  [ -s "$entry" ] \
    || _fail "no '## [' section in $ROOT_CL names 'auto_resume_required.json' — P076's CHANGELOG entry is gone or no longer describes the plan"

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
      || _fail "P076's CHANGELOG entry never mentions '$token' — it does not describe what P076 shipped"
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
  for n in 484 485 486 487 488; do
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

  # NO KNOWN EXCEPTIONS. This assertion used to be an exact-equality pin against
  # the one stale file (`commands/aid-help.md (2026-08-07)`), which made it fail
  # on the CORRECT fix — bumping that stamp emptied the set and turned the case
  # red — and, worse, institutionalised the defect it had detected: the sweep
  # found the one P076-touched file nobody re-stamped, recorded it as expected,
  # and nobody asked what was stale INSIDE it. It was the false
  # `blocked_for_pm` "nothing writes it yet" claim, pinned from this side by
  # case 9. The stamp is bumped and the set is now required to be EMPTY, so this
  # fails for a wrong state (a file whose owning step did not re-stamp it) and
  # never merely for a changed one.
  [ -z "$stale" ] || _fail "these instruction files were modified by P076 but still carry a Last Updated stamp older than P076's first instruction commit (2026-08-09) — the step that changed the file did not re-stamp it, so nothing says its content was reviewed:
${stale}"
}

@test "10: the CHANGELOG and extending-aid.md agree on what the run-mode advice is PROVEN to do" {
  # THE REGRESSION THIS CLOSES: the commit that retracted "the gate report is
  # byte-identical with and without it" from the CHANGELOG — on the stated
  # grounds that the A/B comparison was run during implementation but never
  # shipped as a test — left the identical claim standing in the contributor
  # doc. Two closure surfaces then disagreed about what is proven, and the doc
  # was the stronger, unprovable one. A retraction is only a retraction when
  # every copy goes.
  local claim='it writes no gate row, changes no gate verdict and no exit code'
  grep -qF -- "$claim" "$ROOT_CL" \
    || _fail "the CHANGELOG no longer states what the four shipped cases prove about gate_run_mode_advice ('$claim')"
  grep -qF -- "$claim" "$EXTENDING" \
    || _fail "docs/extending-aid.md does not state the CHANGELOG's proven wording for gate_run_mode_advice ('$claim') — the two closure surfaces disagree about what is proven"

  # The retracted claim may not survive in EITHER file, in any phrasing that
  # asserts report identity.
  local f offender
  for f in "$ROOT_CL" "$PLUGIN_CL" "$EXTENDING"; do
    offender="$(grep -niE 'byte-identical (with and without|report)|report is byte-identical' "$f" || true)"
    [ -z "$offender" ] || _fail "'$f' still asserts the gate report is byte-identical with and without the advice event — that claim was retracted because no shipped test proves it:
$offender"
  done

  # The test file the wording now cites must exist and really carry those cases,
  # so the weaker claim is anchored rather than merely weaker.
  local advice="$REPO_ROOT/plugins/aid-orchestrator/scripts/tests/bats/test-run-mode-advice.bats"
  [ -f "$advice" ] || _fail "both surfaces cite test-run-mode-advice.bats, which does not exist"
  # `|| true`: `grep -c` prints `0` and EXITS 1 on no match, so under `set -e`
  # a file with no @test at all aborted this case before its own message could
  # print — the one outcome the assertion exists to report.
  local cases; cases="$(grep -c '^@test' "$advice" || true)"
  [ "$cases" -ge 4 ] \
    || _fail "both surfaces say 'four cases over the real gate runner'; test-run-mode-advice.bats defines ${cases}"
}

@test "9: EVERY surface describing blocked_for_pm names a writer that really writes it" {
  # The row said "Nothing writes it yet" while lib/aid-recovery-ladder.sh had
  # already shipped the writer. Neither half was pinned, so the claim went
  # stale silently. This case pins BOTH directions: the doc may not re-assert
  # that nothing writes the value, and the writer it names must still exist.
  #
  # PINNED ON EVERY SURFACE, not just aid-run.md. The first version of this case
  # pinned the claim in `aid-run.md` alone; the IDENTICAL false claim one file
  # over, in the USER-FACING `commands/aid-help.md`, was unpinned and survived
  # the commit that set out to kill it. A claim is only closed when every copy of
  # it is closed, so both surfaces are asserted here and a third copy appearing
  # in either file is caught by the whole-file scan at the end.
  local runmd="$REPO_ROOT/plugins/aid-orchestrator/commands/aid-run.md"
  local ladder="$REPO_ROOT/plugins/aid-orchestrator/scripts/lib/aid-recovery-ladder.sh"
  [ -f "$runmd" ] || _fail "missing $runmd"
  [ -f "$ladder" ] || _fail "missing $ladder"

  local row
  row="$(grep -F '| `blocked_for_pm` |' "$runmd" || true)"
  [ -n "$row" ] || _fail "aid-run.md no longer has a 'blocked_for_pm' row in the run-states table"

  if grep -qiF 'nothing writes it' <<<"$row"; then
    _fail "aid-run.md's blocked_for_pm row claims nothing writes the value, but lib/aid-recovery-ladder.sh does:
$row"
  fi

  grep -qF 'aid_ladder_escalate' <<<"$row" \
    || _fail "aid-run.md's blocked_for_pm row does not name its writer (aid_ladder_escalate):
$row"

  grep -qE '^aid_ladder_escalate\(\)' "$ladder" \
    || _fail "aid-run.md names aid_ladder_escalate as the writer, but no such function is defined in lib/aid-recovery-ladder.sh"
  grep -qF 'auto_controller blocked_for_pm' "$ladder" \
    || _fail "lib/aid-recovery-ladder.sh no longer writes 'auto_controller blocked_for_pm' — aid-run.md's row is stale again"

  # THE USER-FACING COPY. `/aid-help` is where a PM meets this vocabulary, so a
  # false claim costs the most here. Its `blocked_for_pm` entry is the line in
  # the run-state list plus the lines indented under it, up to the next entry.
  local helpmd="$REPO_ROOT/plugins/aid-orchestrator/commands/aid-help.md"
  [ -f "$helpmd" ] || _fail "missing $helpmd"
  local helpentry
  helpentry="$(awk '
    /^  blocked_for_pm[[:space:]]/ { inblk = 1; print; next }
    inblk && /^  [^ ]/ { inblk = 0 }
    inblk { print }
  ' "$helpmd")"
  [ -n "$helpentry" ] \
    || _fail "aid-help.md no longer lists 'blocked_for_pm' among the auto_controller values"
  grep -qF 'aid_ladder_escalate' <<<"$helpentry" \
    || _fail "aid-help.md's blocked_for_pm entry does not name its writer (aid_ladder_escalate):
$helpentry"

  # And NEITHER file may carry the retracted claim anywhere, in any wording that
  # says nothing/nobody writes the value — the copy this pin exists to kill.
  local f offender
  for f in "$runmd" "$helpmd"; do
    offender="$(grep -niE '(nothing|nobody|no one) (else )?(writes|sets|stamps) it( yet)?' "$f" \
                 | grep -viE 'awaiting_host_resume|derived' || true)"
    [ -z "$offender" ] || _fail "'$(basename "$f")' claims a state value is written by nothing, but lib/aid-recovery-ladder.sh writes blocked_for_pm:
$offender"
  done
}
