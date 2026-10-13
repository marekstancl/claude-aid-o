#!/usr/bin/env bats
# aid-tier: t2
# test-owned-jobs-docs-closure.bats — P076 Step 17: the release metadata and the
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
  # Since 2026-09-20 entries before 2.90.0 live in CHANGELOG-archive.md, and
  # P076 shipped as 2.80.0 — so the entry this suite reads is in the archive.
  ARCHIVE_CL="$REPO_ROOT/CHANGELOG-archive.md"; export ARCHIVE_CL
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
# as test-deferred-work-registration.bats: §16 ends at the next `## ` heading (§16a),
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

@test "2: the two CHANGELOGs are byte-identical" {
  run cmp -s "$ROOT_CL" "$PLUGIN_CL"
  [ "$status" -eq 0 ] || {
    echo "FAIL: CHANGELOG.md and plugins/aid-orchestrator/CHANGELOG.md differ; CLAUDE.md requires them identical. First differences:" >&2
    diff "$ROOT_CL" "$PLUGIN_CL" | head -40 >&2
    false
  }
}
