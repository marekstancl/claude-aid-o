# C0 lens: dep_api_grounding — P080 (observe, advisory)

_generated_by: aid-orchestrator:verifier@c0-lens-dep_api_grounding
_generated_at: 2026-08-11T04:32:00Z
Reviewed-Head: cd1ab4af145b5272b200741ed41818ae058b2a18

**Head note:** dispatch named `6154ebd714cc69ffa4dd222542cf1e820e078ab8`; the working
checkout was already at `cd1ab4a` when this lens started. Delta verified as
docs-only and irrelevant to every claim below:
`git diff --stat 6154ebd..cd1ab4a` →
`docs/plans/.../2026-07-23-POST-P064-TO-E10-EXECUTION-CHECKLIST.md | 19 ++++-` (1 file).
All commands below were run against `cd1ab4a`.

## Environment baseline (all commands run on this host)

```
$ yq --version   → yq (https://github.com/mikefarah/yq/) version v4.53.2
$ jq --version   → jq-1.6
$ bats --version → Bats 1.8.2
$ awk -W version → mawk 1.3.4 20200120        (/usr/bin/awk -> /usr/bin/mawk; no gawk)
$ git --version  → git version 2.39.5
$ date -u +%Y-%m-%dT%H:%M:%SZ → 2026-08-11T04:25:55Z   (GNU coreutils)
$ which sha256sum → /usr/bin/sha256sum
```

stop_rule_blockers:
  - id: C0-DAG-1
    step: 6
    claim: >-
      Step 6 states the authoritative preset set read from
      `defaults/policies/permissions.yaml` is "(grounded: autonomous, aspirin,
      steroids + custom overlay)" and directs replacing
      `skills/setup/permissions.md`'s "Two presets: autonomous (default), custom"
      line with that list; AC2 then demands the same preset names appear in all
      four touched surfaces and AC1 demands
      `grep -rn 'Two presets' skills/setup/permissions.md` return nothing.
      The policy file defines exactly ONE preset — `autonomous`. `aspirin` and
      `steroids` do not exist anywhere in it; they appear only as a claim in
      `commands/aid-setup.md:80`. Applying the step as written either writes two
      non-existent preset names into four surfaces, or (if the step's own
      "policy file WINS" tiebreak is honoured) deletes a sentence that is
      currently ACCURATE ("autonomous + custom" is exactly what ships) and
      replaces it with the same content, making AC1 a directive to churn a
      correct line. The real defect is one line — aid-setup.md:80 — not four.
    evidence: |
      $ cd /opt/eco/projects/aid-orchestrator/plugins/aid-orchestrator
      $ yq '.presets | keys' defaults/policies/permissions.yaml
      - autonomous
      $ yq '.active_preset' defaults/policies/permissions.yaml
      autonomous
      $ grep -rn 'aspirin\|steroids' defaults/policies/permissions.yaml \
          commands/aid-setup.md skills/setup/permissions.md commands/aid-init.md
      commands/aid-setup.md:80:- `defaults/policies/permissions.yaml` — preset definitions (autonomous, aspirin, steroids)
      $ grep -rn 'Two presets' skills/setup/permissions.md
      60:- Two presets: autonomous (default), custom
    recommendation: >-
      Rewrite Step 6's Implementation Detail to state the ground truth
      (policy file ships one preset, `autonomous`, plus the `custom` overlay that
      `skills/setup/permissions.md:39` writes), drop the "aspirin, steroids"
      parenthetical, retarget the fix to `commands/aid-setup.md:80` (the only
      surface naming non-existent presets), and replace AC1's `Two presets`
      absence grep with an assertion that no surface names a preset absent from
      `yq '.presets | keys'`.

findings:
  - id: C0-DAG-F1
    severity: high
    step: 2
    finding: >-
      The bats plugin-root discovery precedent cited by Step 2
      ("The test discovers the plugin root via `$AID_PLUGIN_PATH` like sibling
      bats suites (`test-aid-test-scheduler.bats:26` precedent)") is a dangling
      cite — that suite was deleted by the P078 parallelism removal. Worse, the
      wording implies `AID_PLUGIN_PATH` is an ambient variable the harness
      provides; it is not. In every surviving suite it is DERIVED inside
      `setup()` from `BATS_TEST_DIRNAME` and then exported. An implementer
      reading the step literally would write a suite that fails under a bare
      `bats <file>` invocation.
    evidence: |
      $ find . -name '*test-aid-test-scheduler*' -not -path './.git/*'   → (no match)
      $ git log --oneline --diff-filter=D -3 -- '*test-aid-test-scheduler.bats'
      2ce139c P078 Ring 1: remove the test-parallelism machinery
      $ grep -rl 'AID_PLUGIN_PATH' scripts/tests/bats/*.bats | wc -l   → 95
      $ grep -rl 'BATS_TEST_DIRNAME' scripts/tests/bats/*.bats | wc -l → 142
      $ grep -n 'AID_PLUGIN_PATH' scripts/tests/bats/test-reporter-boundary.bats
      21:  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
      22:  export AID_PLUGIN_PATH
    recommendation: >-
      Repoint the precedent to a live suite and state the derivation explicitly:
      `AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"` per
      `scripts/tests/bats/test-reporter-boundary.bats:21-22` (or the plain
      `PLUGIN_ROOT=` form at `test-aid-gate-waiver.bats:22`). Same wording fix
      applies to Steps 7, 10, 11, 12 which inherit the convention implicitly.

  - id: C0-DAG-F2
    severity: high
    step: 10
    finding: >-
      The plan is a consumer of the Claude **Artifact tool** contract (Steps 10-12
      produce `.html` bodies the controller publishes; Step 16 ships a spec page
      about it) but records none of that tool's binding input constraints. The
      tool wraps the supplied file in its own
      `<!doctype html>…<head>…</head><body>` skeleton — a file that carries its
      own `<!DOCTYPE>`/`<html>`/`<head>`/`<body>` is malformed for it; a favicon
      emoji is REQUIRED to publish; the page title comes from a `<title>` tag or
      the `title` parameter; and a strict CSP blocks every external host (fonts,
      CDN, images). Step 10 instead says the lib "emits a self-contained styled
      HTML artifact **page**" with a "HTML/CSS **skeleton**" vendored from
      agent-report.py — phrasing that invites exactly the wrong shape. The named
      vendor source happens to be body-content-only, so verbatim copying is safe
      by luck, not by a stated rule, and no AC pins it.
    evidence: |
      $ grep -n '<!DOCTYPE\|<!doctype\|<html\|<head>\|</head>\|<body' \
          /opt/eco/services/agent-runtime/agent-report.py
      (no matches — the shipped template emits body content only, starting at
       line 424 with `<h1>…</h1><span class="when">…`)
      Artifact tool contract (tool description, this session): "The file is
      wrapped in a <!doctype html>…<head></head><body> skeleton at publish time,
      so write the page content directly — no <!DOCTYPE>, <html>, <head>, or
      <body> tags of your own"; "Favicon (required)"; "A strict CSP blocks
      requests to any external host".
    recommendation: >-
      Add one sentence to Step 10's Implementation Detail ("the rendered body is
      page CONTENT only — no doctype/html/head/body wrapper, all CSS inline, no
      external asset references, per the Artifact tool contract"), add a Step 10
      AC grepping the golden for the absence of `<!doctype`/`<html`, and name the
      favicon + title + description values the controller passes in the Steps 11/12
      wiring text so publication is deterministic rather than improvised per run.

  - id: C0-DAG-F3
    severity: medium
    step: 13
    finding: >-
      Every `aid-fsm.sh` line anchor Step 13 cites for the `_fsm_human_step` seam
      is wrong on the reviewed head — off by ~300 lines for the helper and by
      400-1300 for the call sites. The plan already carries a P076-rebase caveat,
      but this drift is NOT from P076: it predates it (P078 removals shifted the
      file). The helper's SIGNATURE is compatible with the plan's intent
      (`<current> <total>` → "Plan Step N of T"), and the call-site COUNT (3)
      matches the plan's Context claim — only the anchors are stale.
      The cited `verify-state` JSON payload site at `:4141` also does not exist
      at that line.
    evidence: |
      $ grep -n '_fsm_human_step' scripts/aid-fsm.sh
      1128:# _fsm_human_step <current> <total> — echoes " (human: ...)" or nothing.
      1132:_fsm_human_step() {
      2858:        echo "PRECONDITION FAIL: current_step=${current} == total_steps=${total}$(_fsm_human_step ...
      2870:        echo "PRECONDITION FAIL: current_step=${current} < total_steps=${total}$(_fsm_human_step ...
      5246:    echo "ERROR: advance-to-gates requires current_step ($current_step) >= total_steps ...
      (plan claims helper at 819-840/830-840 and call sites 2430/2442/3935/3945,
       verify-state JSON at 4141)
    recommendation: >-
      Restate Step 13's anchors as literals ("the `_fsm_human_step` definition
      block", "each `PRECONDITION FAIL: current_step=` echo", "the
      `advance-to-gates requires current_step` echo") and drop the numeric line
      cites, consistent with how Step 16 already forbids line numbers in the
      ownership table. The sweep method (`grep -n 'current_step'`) is sound as-is.

  - id: C0-DAG-F4
    severity: medium
    step: 10
    finding: >-
      Two drifts against the external artifact standard the plan consumes.
      (a) The standard delegates agent-report structure to a named sub-spec,
      `../ai-agents/report-spec.md` ("Report z běhu agenta — přesná struktura pro
      agentní reporty"), which does NOT exist in the docs tree; the plan never
      mentions it, so an implementer told to "implement the ecosystem artifact
      standard" will follow a dangling pointer. (b) The plan's ~220 chars/sentence
      cap matches the STANDARD but not the template it vendors from — the shipped
      renderer clips at 300 and 320 chars. Goldens copied from the implementation
      will therefore not satisfy a 220-char assertion.
      Otherwise the plan's grounding of the spec is accurate and current: the
      7-block skeleton, block-6-always-present rule, the "≤5 findings / ≤3 next
      steps" caps, "čísla se počítají, netvrdí", the missing-summary warning and
      the "stejný layout pokaždé" rule all match the published file (updated
      2026-08-09). The class names Step 10's ACs grep for all exist in the vendor
      source, including the three-state theme guards.
    evidence: |
      $ ls -la /opt/eco/docs/docs/ecosystem/specs/artifact-standard.md
      -rw-rw-r-- 5917 Aug  9 09:44   (status: published, updated: 2026-08-09)
      $ ls -la /opt/eco/docs/docs/ai-agents/report-spec.md
      ls: cannot access '...': No such file or directory
      $ grep -c 'state-ok|state-warn|state-critical|golink|masthead|eyebrow' → 1/1/1/4/3/3
      $ grep -n 'prefers-color-scheme\|data-theme' /opt/eco/services/agent-runtime/agent-report.py
      50:@media (prefers-color-scheme: dark){
      51:  :root:not([data-theme="light"]){
      59::root[data-theme="dark"]{
      $ grep -n '_clip(' agent-report.py | grep -o '[0-9]\{3\}' | sort -u → 300, 320
    recommendation: >-
      Note in Step 10 that the sibling `report-spec.md` is currently absent so the
      parent standard is the sole binding source, and state explicitly that the
      220-char cap comes from the STANDARD and deliberately tightens the vendored
      renderer's 300/320 clip (so the divergence is a decision, not a bug found
      later in review).

  - id: C0-DAG-F5
    severity: low
    step: 2
    finding: >-
      The system awk is mawk 1.3.4, not gawk. All awk the plan reuses is
      POSIX-safe (the `fenced_stripped()` pattern and the fixed-line-window
      frontmatter scan both are), but the plan's "awk over lines 1-6" /
      "awk from `### Topic:` to next `###`" instructions give an implementer no
      warning against gawk-isms (`gensub`, `asort`, `\s`, `length(arr)` on older
      mawk, `--re-interval` assumptions), which would pass on a gawk dev box and
      fail here and in CI.
    evidence: |
      $ awk -W version → mawk 1.3.4 20200120
      $ readlink -f /usr/bin/awk → /usr/bin/mawk
      $ sed -n '39,44p' scripts/aid-lint-skill.sh   (the pattern the plan reuses)
      fenced_stripped() { awk '/^[[:space:]]*```/ { infence = !infence; print ""; next }
                               { if (infence) print ""; else print }' "$file"; }
      → POSIX-only, mawk-safe
    recommendation: >-
      One line in the Constraints section: "awk here is mawk (POSIX) — no gawk
      extensions", alongside the existing "bash, jq, yq, awk only" sentence.

  - id: C0-DAG-F6
    severity: low
    step: 10
    finding: >-
      jq on this host is 1.6 (2018). Steps 4, 10, 11, 12 all specify jq as the
      extraction engine but no step pins a minimum, and `aid-check-deps.sh`
      guards the yq VARIANT (mikefarah) without guarding any jq version. jq 1.7
      builtins an implementer would reasonably reach for — `pick`, `abs`,
      `toarray`, `have_decnum`, `ltrimstr` on arrays, `--raw-output0` — are all
      absent in 1.6 and fail at runtime, not at parse time in some cases.
    evidence: |
      $ jq --version → jq-1.6
      $ grep -n 'yq' scripts/aid-check-deps.sh
      63:check_required yq   "mikefarah Go variant ... NOT the Python kislyuk/yq PyPI package."
      64:                    "yq --version 2>&1 | grep -qi mikefarah"
      (no equivalent jq version assertion anywhere in the file)
    recommendation: >-
      Add "jq expressions must be 1.6-compatible" to Constraints, or have Step 16
      add a jq-minimum check to `aid-check-deps.sh` alongside the existing yq
      variant guard.

  - id: C0-DAG-F7
    severity: low
    step: 16
    finding: >-
      The Docusaurus target is grounded and reachable, with one wrinkle: the
      plan's IN-REPO fallback path `plugins/aid-orchestrator/docs/` does not
      exist as a directory — the repo's contributor docs live at repo-root
      `docs/` (which is where Step 16's own `docs/extending-aid.md` edit goes).
      The fallback would therefore create a brand-new, otherwise-unused docs
      location inside the distributed plugin tree.
    evidence: |
      $ ls /opt/eco/docs/docs/aid/
      agents architecture commands configuration contributing getting-started
      intro.md skills troubleshooting            → /aid/ namespace confirmed
      $ ls /opt/eco/docs/docs/aid/specs/ → No such file or directory  (plan anticipates this)
      $ test -w /opt/eco/docs/docs/aid && echo writable → writable
      $ git -C /opt/eco/docs rev-parse --abbrev-ref HEAD → main
      $ ls /opt/eco/docs/docs/ecosystem/specs/_category_.json → exists (sibling shape confirmed)
      $ ls -d plugins/aid-orchestrator/docs → No such file or directory
    recommendation: >-
      Point the fallback at the repo's existing docs root
      (`docs/artifact-templates-spec.md`) rather than creating
      `plugins/aid-orchestrator/docs/`, keeping the plugin distribution tree
      unchanged when the cross-repo write is refused.

  - id: C0-DAG-F8
    severity: low
    step: 2
    finding: >-
      Step 2's AC3 ("auto-discovered by run-all-tests.sh, no registration needed")
      is CORRECT for discovery, but two adjacent registration surfaces the plan
      never mentions will drift when six new suites land: the `DELEGATED_SUITES`
      map (a slow suite must be delegated to its own CI job or it eats the
      aggregate job's budget) and `.aid-o/config/test-catalog.yaml`
      (156 run_units, one per suite, consumed by the selector). Neither is a hard
      gate today — no completeness assertion was found — so this is informational.
    evidence: |
      $ sed -n '172,186p' scripts/tests/run-all-tests.sh
      for f in "$SCRIPT_DIR"/test-*.sh; do ... SUITES+=("$f"); done
      for f in "$SCRIPT_DIR"/bats/test-*.bats; do ... SUITES+=("$f"); done
      → auto-discovery confirmed for both harness types
      $ sed -n '150,166p' scripts/tests/run-all-tests.sh
      declare -A DELEGATED_SUITES=( [test-aid-plan-release-boundary.bats]=... ×5 )
      $ yq '.run_units | length' .aid-o/config/test-catalog.yaml → 156
      $ grep -rn 'not in catalog\|uncatalogued\|catalog_miss' scripts/*.sh scripts/lib/*.sh
      (no match — no mechanical completeness gate)
    recommendation: >-
      One sentence in the Testing Strategy: new suites are auto-discovered; only
      a suite that runs long enough to threaten the aggregate job needs a
      `DELEGATED_SUITES` row plus its CI job; catalog regeneration is a separate,
      non-blocking chore.

  - id: C0-DAG-F9
    severity: low
    step: 10
    finding: >-
      Internal contradiction in the artifact renderer's escaping contract:
      Implementation Detail says "HTML-escape all substituted values", Edge Cases
      says "facts are inserted **raw** (no re-expansion)". The vendor source
      escapes everything (`_html.escape` on every slot). A gate name or waiver
      reason containing `<` or `&` would silently corrupt the page under the raw
      reading.
    evidence: |
      $ grep -c '_html.escape' /opt/eco/services/agent-runtime/agent-report.py → escapes on
        every substitution site (lines 193, 205-206, 212, 365, 373, 382-383, 396-397, 410,
        424, 428, 435, 441, 445)
    recommendation: >-
      Reword the edge case to what it actually means: values are escaped, and
      escaping is single-pass so an escaped `{{` in a fact is never re-expanded
      as a placeholder.

  - id: C0-DAG-F10
    severity: low
    step: 1
    finding: >-
      Positive grounding, recorded so later steps do not re-litigate it: the yq
      dependency assumptions hold exactly. The host yq is mikefarah Go v4.53.2 —
      the variant `aid-check-deps.sh` already hard-requires — and both plan
      invocation shapes (`yq '.surfaces | length' <file>` in Step 1 AC1,
      `yq -o=json` + jq iteration in Step 4) are valid v4 syntax matching 108
      existing yq call sites in the repo. The Step 1 AC1 expected value of 13 is
      also exact.
    evidence: |
      $ yq --version → mikefarah v4.53.2
      $ grep -n 'yq' scripts/aid-check-deps.sh:63-64 → mikefarah variant enforced
      $ grep -rl 'yq ' scripts/ | wc -l → 108
      $ grep -rn 'yq -o=json' scripts/ | head → 10+ live call sites (identical form)
      $ ls plugins/aid-orchestrator/commands/*.md | wc -l → 12, all `user_invocable: true`
      $ ls plugins/aid-orchestrator/skills/*/SKILL.md → skills/visual-companion/SKILL.md only
        (skills/setup/ has no SKILL.md — matches the plan's stated edge case)
      → 12 + 1 = 13
    recommendation: none — no change needed.

confidence: high
