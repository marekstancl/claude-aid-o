# CP1-deep — C0 lens dep_api_grounding — P082

I read all 551 lines and then exercised every external-tool assumption the plan makes on this machine. Installed versions: `jq-1.6`; `yq` mikefarah v4.53.2; `Bats 1.8.2`; `/bin/grep` = GNU grep 3.8 (note: the interactive Claude shell shadows `grep` with a function routing to `ugrep 7.5.0 +pcre2jit` — scripts and bats invoke `/bin/grep`, so GNU 3.8 is the real target); GNU sed 4.9; coreutils 9.1 (`date`, `stat`, `mktemp`); git 2.39.5; gh 2.23.0; codex-cli 0.146.0; bash 5.2.15. CI is not a hosted image — every job in `.github/workflows/ci.yml` and `nightly-tests.yml` is `runs-on: [self-hosted, eco-dev]` with `actions/checkout@v5` / `upload-artifact@v4`, so the runner toolchain is exactly the one measured above; the workflows install `jq`, `bats`, `yq` (mikefarah release binary) and `python3-jsonschema` when absent. Things I verified as GROUNDED, not findings: `yq -r '.gate_profiles[strenv(PROFILE)].include // [] | .[]'` and `yq -e '.gate_profiles'` (the two filters Step 2 depends on) both run correctly on v4.53.2 against the live `.aid-o/config/execution.yaml`; `plugins/aid-orchestrator/defaults/execution.yaml` parses clean under `yq -e '.'` and genuinely lacks `gate_profiles` (`grep -n '^gate_profile'` → exit 1, `yq -e` → exit 1), so Step 2's premise holds; `git rev-parse --path-format=absolute --git-common-dir` (Step 10's stated mechanism, git ≥ 2.31) returns `/opt/eco/projects/aid-orchestrator/.git` on git 2.39.5, and `aid-check-deps.sh` declares no git floor that would conflict; the bats suites use no `bats_load_library`/`bats-support`/`bats-assert`/`bats_require_minimum_version` at all, so nothing in the plan's four new suites can outrun 1.8.2; `aid-release.sh:341` is really `grep -m1 -oP "$pattern"` as the plan states; `aid-review-signals.sh:24-25` really uses `grep -qP` twice, and its `if grep -qP … && …` shape means an exit-2 (no-PCRE) grep does fall through to "not disabled", as Step 5 claims; the AC8 command as written today returns 1 (violations present) and will return 0 once those two lines are converted. `jq` is not asked to run any filter by this plan. Findings below are all about grep/regex dialect, which is this plan's own subject matter.

stop_rule_blockers: []

findings:

  - severity: high
    ref: C0-DAG-1
    summary: >
      The plan's only executable PCRE-detection pattern — AC8's
      `grep[^|;]*-[A-Za-z]*P\b` — cannot match two of the four spellings Step 5
      explicitly promises to catch. Step 5 line 207 says "The widened pattern
      tolerates flag order and combination (`-oP`, `-qP`, `-Pq`,
      `--perl-regexp`); the self-test asserts the detector catches each". I put
      all four spellings in a fixture and ran the AC8 pattern with GNU grep 3.8:
      it matched only `-qP` and `-oP`. `-Pq` fails because `\b` requires a
      non-word char after `P` and `q` is a word char; `--perl-regexp` fails
      because it contains no capital `P` at all. If the implementer reuses AC8's
      pattern as "the widened detector" for Step 5 (it is the only concrete
      pattern the plan supplies), the rebuilt guard reproduces exactly the defect
      the plan exists to fix — a green scan with live evading call sites — and
      the required self-test would then have to be written to a weaker spec than
      the prose states.
    evidence: |
      $ printf 'a() { grep -Pq "x" f; }\nb() { grep --perl-regexp "x" f; }\nc() { grep -qP "x" f; }\nd() { grep -oP "x" f; }\n' > /tmp/pcre-fixture.sh
      $ /bin/grep -nE 'grep[^|;]*-[A-Za-z]*P\b' /tmp/pcre-fixture.sh
      3:c() { grep -qP "x" f; }
      4:d() { grep -oP "x" f; }
      exit=0        # lines 1 (-Pq) and 2 (--perl-regexp) NOT matched
      Plan quote: line 543 (AC8 cmd) vs line 207 (Step 5 Implementation Detail).
    suggested_fix: >
      Replace AC8's pattern with one that has no trailing-`\b` dependency and
      covers the long form, e.g.
      `grep([[:space:]]+-[A-Za-z]*P([[:space:]]|$)|[[:space:]]+--perl-regexp)`,
      and state in Step 5 that the self-test fixture MUST contain all four
      spellings from line 207 (a fixture-completeness assertion), so the detector
      cannot be re-narrowed later.

  - severity: medium
    ref: C0-DAG-2
    summary: >
      AC8 — the acceptance criterion whose entire purpose is proving that a
      GNU-only grep feature has been removed — is itself written with a GNU-only
      regex extension. `\b` is not in POSIX ERE; GNU grep supports it as an
      extension. Verified by running the same pattern through a POSIX-ERE engine
      (mawk): no match, while GNU grep -E matches. On a non-GNU grep the AC8
      command therefore either errors or silently fails to match, and because AC8
      is phrased as a negation (`! grep …`), a non-match is reported as PASS —
      a false green on precisely the hosts the invariant exists to protect. The
      same dialect trap sits in Step 5's instruction to convert the two
      `grep -qP` calls to "POSIX equivalents": the current patterns use `\s`,
      which is also a GNU-only ERE extension, so a naive `-qP` → `-qE` keeps the
      portability defect while satisfying the plan's text.
    evidence: |
      $ echo 'grep -oP x' | awk '/grep[^|;]*-[A-Za-z]*P\b/ {print "awk MATCHED"}'
      (no output — POSIX ERE engine does not honour \b)
      $ echo 'grep -oP x' | /bin/grep -E 'grep[^|;]*-[A-Za-z]*P\b' && echo "GNU grep -E MATCHED"
      grep -oP x
      GNU grep -E MATCHED
      Plan quotes: line 543 (`grep[^|;]*-[A-Za-z]*P\\b`); line 201
      ("the two `grep -qP` calls become POSIX equivalents").
    suggested_fix: >
      Drop `\b` in favour of `([[:space:]]|$)` (see C0-DAG-1) and add an explicit
      instruction to Step 5 that the replacement patterns in
      `aid-review-signals.sh` use `[[:space:]]` rather than `\s`, with the
      resulting regexes stated in the step so the conversion is checkable.

  - severity: medium
    ref: C0-DAG-3
    summary: >
      Step 5 widens the detector's *spelling* but leaves its *file glob*
      untouched, and the existing scanner only walks `*.sh`. The live scanner is
      `_imp274_scan`, which does `find "$dir" -name '*.sh' -type f`. Two
      non-comment `grep -oP` call sites already sit in a `.bats` file under the
      same tree and are invisible to it today and after the proposed widening —
      so AC "The scan is green over the tree" (line 222) and the objective "The
      `grep -oP` invariant is actually enforced" (line 197) will still be
      satisfied by a scan that cannot see part of the tree.
    evidence: |
      test-aid-plan-release-boundary.bats:7224:
        n="$(grep -n 'grep -oP' "$f" 2>/dev/null | grep -cv ':[[:space:]]*#')"
      test-aid-plan-release-boundary.bats:7222 (scan source):
        find "$dir" -name '*.sh' -type f
      $ /bin/grep -rnE 'grep[^|;]*-[A-Za-z]*P\b' plugins/aid-orchestrator/scripts/tests/bats/test-aid-release.bats
      56:  header=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$TEST_PROJECT_ROOT/CHANGELOG.md" | head -1)
      92:  header=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$TEST_PROJECT_ROOT/CHANGELOG.md" | head -1)
    suggested_fix: >
      Say in Step 5's Files bullet that the scan's file set widens to `*.sh` and
      `*.bats` (and, if the consumer surface matters, `defaults/hooks/*`), and
      allowlist the two `test-aid-release.bats` sites with a written reason —
      or convert them, since `\K` there is a pure convenience.

  - severity: low
    ref: C0-DAG-4
    summary: >
      The guard's per-file allowlist is already numerically stale in a way that
      makes Step 5's "the per-file allowlist is re-derived from the widened
      scan" (line 200) more than bookkeeping: `aid-release.sh` is allowlisted at
      max 3 literal `grep -oP` lines, but its literal count today is 0 and its
      count under the widened pattern is 1 (the `grep -m1 -oP` probe at line
      341, which the literal detector never saw). Re-deriving must therefore
      start from measured counts under the new pattern, not from the existing
      numbers, or the allowlist will silently grant three slots where one site
      exists.
    evidence: |
      $ /bin/grep -c 'grep -oP' plugins/aid-orchestrator/scripts/aid-release.sh
      0
      $ /bin/grep -cE 'grep[^|;]*-[A-Za-z]*P\b|--perl-regexp' plugins/aid-orchestrator/scripts/aid-release.sh
      1
      Allowlist (test-aid-plan-release-boundary.bats:~7238): ["aid-release.sh"]=3
    suggested_fix: >
      Add to Step 5's Acceptance Criteria that each allowlist entry equals the
      measured count under the widened pattern (no headroom), so a shrunk site
      cannot leave a spare slot behind.

confidence: high
