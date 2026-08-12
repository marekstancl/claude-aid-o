# CP1-deep — C0 lens dep_api_grounding — P083

Lens question: does the plan assume behaviour from an external tool that the
installed version does not have? Everything below was executed on this machine;
no claim is repeated from the plan's paraphrase.

## Tool versions found (measured)

| Tool | Version | Note |
|---|---|---|
| grep (`/usr/bin/grep`) | GNU grep 3.8 | `-P` works: `echo abc \| /usr/bin/grep -qP 'a\wc'` → rc=0 |
| grep (interactive shell) | ugrep 7.5.0 (Claude Code shell **function**, `-G` mode) | **not exported** (`export -p \| grep -c BASH_FUNC_grep` → `0`), so scripts get GNU grep |
| awk (`/usr/bin/awk` → alternatives) | **mawk 1.3.4 20200120** — gawk is NOT installed (`command -v gawk` → empty) | `awk --version` errors; `awk -W version` identifies mawk |
| yq | v4.53.2 (mikefarah) | |
| jq | jq-1.6 | |
| bash | 5.2.15(1) | |
| bats | 1.8.2 | |
| git | 2.39.5 | |
| sed | GNU sed 4.9 | |
| coreutils (date/stat/mktemp/timeout/readlink/realpath) | GNU coreutils 9.1 | all GNU |
| busybox | not installed — no second grep/awk implementation available for cross-checking portability locally |

---

stop_rule_blockers: 1

### BLOCKER-1 — Step 5 restores a gate that cannot read this plan's acceptance criteria, and the "measured, exits 0" evidence does not reproduce

Plan quote (line 205, *Implementation Detail — decision made 2026-08-11, restore not remove*):

> Measured before writing this step: `aid-plan-diff.sh --plan <this plan> --evidence-dir <tmp> --base-commit HEAD` **exits 0** and produces a valid `plan-diff.json`, and the machine-verifiable AC convention it executes is alive

and Success Criteria #3 (line 389):

> `plan_diff` **verifies this plan's own criteria** instead of skipping.

Command run:

```
cd /opt/eco/projects/aid-orchestrator
D=$(mktemp -d)
bash plugins/aid-orchestrator/scripts/aid-plan-diff.sh \
  --plan .aid-o/plans/P083-ten-verified-defects.md \
  --evidence-dir "$D" --base-commit HEAD
echo "EXIT=$?"
```

Output:

```
EXIT=1
(no stdout at all — 0 lines)
```

`$D/plan-diff.json`:

```
"ac_count": 11,
results[*]: { "ac_label": "", "ac_text": "", "pattern_type": "cmd",
              "verdict": "absent", "evidence": "exit=1 (expected 0)" }   × 11
"summary": {"present_count": 0, "absent_count": 11, "skipped_count": 0}
"overall_verdict": "fail"
```

Two separate facts here, only the first of which the plan anticipates:

**(a) exit 1 / all-absent is expected pre-fix** (the eleven `bats …` files do not
exist yet). Not a defect. But the plan states the run *exits 0*, which is false
against the plan as written, so the sentence that carries Step 5's whole decision
is not reproducible as stated.

**(b) All eleven `ac_label` and `ac_text` values are EMPTY.** This is a real
contract mismatch, not a consequence of (a). `aid-plan-diff.sh`'s AC recogniser
(`plugins/aid-orchestrator/scripts/aid-plan-diff.sh:167`) is:

```
if ($0 ~ /^- \[[ x]\] AC[0-9]+:/ || $0 ~ /^- \[[ x]\] \[[a-z_]+\]/) {
```

It requires a **colon** after `ACn`. P083 writes its criteria with an em dash
(line 396: `- [ ] AC1 — The streamlined integration review reads …`), so
`ac_label` is never assigned and every row is emitted anonymously by the
`in_yaml` close-fence branch.

Isolated proof — same plan, only `— ` → `: ` on the AC bullets:

```
sed 's/^- \[ \] \(AC[0-9]*\) — /- [ ] \1: /' .aid-o/plans/P083-ten-verified-defects.md > P083-colon.md
bash plugins/aid-orchestrator/scripts/aid-plan-diff.sh --plan P083-colon.md --evidence-dir "$D2" --base-commit HEAD
jq -r '.results[] | "\(.ac_label) | \(.verdict)"' "$D2/plan-diff.json"
```

```
AC1 | absent
AC2 | absent
...
AC11 | absent
```

Labels populate. So the installed `aid-plan-diff.sh` **does not** support the AC
heading style P083 itself uses. Restoring the gate to five merge-path profiles
(Step 5) makes this plan's own DONE review produce eleven unattributable rows —
a reviewer cannot tell which criterion failed. That directly contradicts Success
Criteria #3.

Cheapest resolution, both inside the plan's own scope: either P083 rewrites its
eleven AC bullets to `- [ ] ACn: …`, or Step 5 adds the em-dash form to the
recogniser at `aid-plan-diff.sh:167` (one alternation) with the regression it
already budgets. Silent-anonymous-rows must not ship on the merge path.

---

findings:

### F1 (MEDIUM) — Step 6's "POSIX-portable match" cannot be validated on this machine, and the two constructs most likely to be reached for are the exact P082 irony

Plan quote (line 231):

> `_aid_read_toggle` uses a **POSIX-portable match** instead of `grep -qP`

The current code (`plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:24-25`) is:

```
if grep -qP "^\s{0,4}${section_name}:\s*$" "$exec_yaml" && \
   grep -A5 "${section_name}:" "$exec_yaml" | grep -qP '^\s+enabled:\s+false\s*$'; then
```

The naive translation is `-P` → `-E` keeping `\s`. Measured:

```
echo 'a b' | /usr/bin/grep -qE '\s'          → rc=0
echo 'foo bar' | /usr/bin/grep -qE '\bbar\b' → rc=0
echo 'a b' | /usr/bin/grep -qE '[[:space:]]' → rc=0
```

`\s` and `\b` are **GNU extensions, not POSIX ERE** — they pass here purely
because GNU grep 3.8 is installed, and there is no busybox/BSD grep on this box
to catch it. This is precisely the failure P082's own review found (its
portability fix used GNU-only `\b`). A "portable" fix landed and tested only on
this machine will look green and be wrong for exactly the greps Step 6 exists to
serve.

Verified-portable candidates, exit codes on the real fixture
(`simplifier:\n  enabled: false`):

```
/usr/bin/grep -qE '^[[:space:]]{0,4}simplifier:[[:space:]]*$' y.yaml   → rc=0
/usr/bin/grep -qE '^[[:space:]]+enabled:[[:space:]]+false[[:space:]]*$' y.yaml → rc=0
line='  enabled: false'; [[ "$line" =~ ^[[:space:]]+enabled:[[:space:]]+false[[:space:]]*$ ]] → rc=0 MATCH
```

Bash's own `[[ =~ ]]` is the strongest option because it needs no external tool
at all, and it self-polices: `x='a b'; [[ "$x" =~ \s ]]` → **NO MATCH**, i.e.
bash's ERE genuinely rejects `\s` and would catch the P082 mistake at test time
on this very machine. Ask: Step 6 should name POSIX bracket classes (or bash
`=~`) explicitly and forbid `\s`/`\b`/`\d`/`\w`, and its suite should assert the
pattern string contains no backslash-shorthand — otherwise this machine cannot
tell the fix from the bug.

*Step 6's premise itself is confirmed sound.* Fail-open reproduced with a stub
grep that exits 2 on `-P`:

```
PATH=stub:$PATH bash -c 'source .../aid-review-signals.sh; _aid_read_toggle y.yaml simplifier; echo rc=$?'
→ TOGGLE rc=0   (0 = enabled, with enabled: false in the file)
```

The stub-grep test design the plan specifies (line 232) works — the library calls
bare `grep`, so a PATH-shadowing stub is reached.

### F2 (MEDIUM) — Step 2's shared extractor will run on mawk, not gawk; two common awk constructs are silently unavailable

Plan quote (line 104):

> Create: `plugins/aid-orchestrator/scripts/lib/aid-ac-extract.sh` — the shared
> extractor: a criterion begins at a flush-left `- ` bullet and continues through
> indented lines …

The dialect question: `awk` on this machine is **mawk 1.3.4 20200120**; gawk is
not installed. Two features an author would plausibly reach for do not exist:

```
printf 'aaa\n' | awk '/a{2,3}/{print "INTERVAL-OK"}'     → (no output)
printf 'a{2,3}\n' | awk '/a{2,3}/{print "LITERAL"}'      → LITERAL
```
Regex intervals `{n,m}` are **not supported** — mawk treats the braces literally.

```
printf 'a b\n' | awk '/a\sb/{print "BACKSLASH-S-OK"}'    → (no output)
printf 'asb\n' | awk '/a\sb/{print "S-AS-LITERAL"}'      → S-AS-LITERAL
```
`\s` is **not supported** — it collapses to a literal `s`.

Confirmed working on mawk: `[[:space:]]`, `*`, `+`, `sub()`, `substr()`.

**Does the existing code inherit a gawk-only feature?** No — checked, and this is
good news for the step. The two blocks the plan replaces
(`aid-plan-to-epic.sh:909-925` and `:936-949`) use only `gsub`, `sub` and
`[[:space:]]`. A repo-wide sweep for gawk-only constructs
(`gensub|asort|IGNORECASE|PROCINFO|ENDFILE|BEGINFILE|RT|strtonum|patsplit|switch(`)
over `plugins/aid-orchestrator/scripts/**/*.sh` returns exactly one hit,
`aid-plan-diff.sh:97`, and that hit is inside a **comment** that says the opposite
("Uses portable awk (mawk-compatible) — no gensub()"). So there is nothing
gawk-only to inherit.

Ask: Step 2 should state the mawk constraint in the step (no `{n,m}`, no `\s`),
and its suite should run the extractor under `mawk` explicitly, so the
"indented continuation lines" matcher is not written as `/^[[:space:]]{1,}/`,
which reads correct and silently matches nothing here.

### F3 (LOW) — Step 9's measured numbers do not reproduce; the invocation form in the plan is not the script's interface

Plan quote (line 334):

> Run against this plan before generation existed, it exited 0 in about a second
> and emitted `aid-source-plan-graph/v1` with **11 steps, 2 edges**, no cycles,
> bound to the plan's own sha256.

Command (note: the plan's `--plan` form at line 328 does **not** exist):

```
bash .../aid-generation-readiness.sh --plan <plan> --write-provisional
→ ERROR: unknown option: --plan
→ EXIT=2
```

The interface is positional, and `--write-provisional` takes a path argument
(`aid-generation-readiness.sh:17-27`). Correct invocation:

```
bash .../aid-generation-readiness.sh .aid-o/plans/P083-ten-verified-defects.md \
  --json --write-provisional graph.json
→ EXIT=0, real 0m1.422s
```

Written artifact:

```
schema:            "aid-source-plan-graph/v1"     ✅ as claimed
plan_sha256:       "sha256:eb98a5ed…"             ✅ bound to plan bytes
steps:             10                             ❌ plan says 11 (the plan has 10 steps)
edges:             1  [{"before":"step-3","after":"step-4"}]   ❌ plan says 2
cycles:            []                             ✅
```

One edge, because Step 4 is the only step with a real `Depends on:`. Neither the
"about a second" nor the exit-0 claim is wrong; only the shape numbers are, and
they are the numbers a reviewer would use to sanity-check the artifact.

**Positive contract check (the part that matters most for Step 9):** the producer's
output is accepted by the consumer's validator. `aid-c0-plan-review.sh:336`
computes `reviewed_plan_hash="sha256:$(sha256sum …)"` and `:393` compares it
`==` against the graph's `.plan_sha256` — both carry the `sha256:` prefix, so the
formats match exactly and Step 9's plan does not create a hash-format mismatch.
`:391` requires schema `aid-source-plan-graph/v1` (matches) and `:394` requires
`.steps/.edges/.topological_order/.cycles` all to be JSON arrays — all four are
arrays in the written file. No dependency blocker in Step 9.

One scope note for the C0 lens rather than this one: `build-manifest` seals **two**
graph slots — `c0/plan-graph.json` (`:377`, per-EPIC, produced by
`aid-c0-contract.sh`) and `generation/provisional-graph.json` (`:385`). Step 9's
Files entry only fills the second, while its Architecture Context (line 332)
observes "**both** graph paths as `absent_pre_generation`". AC10 does not say
which. Worth disambiguating before implementation.

### F4 (LOW) — Step 8's "present-but-empty for read compatibility" is not load-bearing under the installed jq, and the "empty on every entry" premise is wrong

Plan quotes (line 297 and line 300):

> the two map fields stay **present-but-empty so a legacy baseline file still reads**

> the live baseline has **empty `*_by_context` maps on every entry**

The reader is jq 1.6 with `// {}` / `// []` defaults
(`aid-gate-runtime-baseline.sh:440-441, 536`). Measured:

```
echo '{"recent_samples_by_context":{}}' | jq -c '.recent_samples_by_context // {}'   → {}
echo '{}'                               | jq -c '.recent_samples_by_context // {}'   → {}
echo '{"recent_samples_by_context":{}}' | jq -c '.recent_samples_by_context["seq"] // []' → []
echo '{"x":{}}'   | jq -c 'if .x then "truthy" else "falsy" end'  → "truthy"
echo '{"x":null}' | jq -c '.x // "DEFAULTED"'                     → "DEFAULTED"
```

Absent and present-but-empty are **indistinguishable** to every reader in that
file: `//` fires on `null` (absent) and `{}` is truthy so it passes through. So
keeping the fields present-but-empty is harmless but buys no read compatibility
that deleting them would lose. The real read-compat risk the step names — another
project's file carrying *populated* maps — is unaffected by this choice and is
correctly identified as where the effort goes.

Second, the premise is factually wrong on the live file:

```
yq -o=json '.' .aid-o/metrics/gate-runtime-baselines.yaml \
 | jq -r '.gates|to_entries[]|"\(.key) rs=\(.value.recent_samples_by_context//"MISSING")"'
```
```
plan_diff rs=MISSING          docs_updated rs={}
bats_fsm rs={}                bats_all rs={}
tests_pass rs=MISSING         lint_pass rs=MISSING
required_gate rs=MISSING      optional_gate rs=MISSING
shell_pipeline_smoke rs=MISSING   ui_calibration_result rs=MISSING
ui_calibration_signoff rs=MISSING targeted_tests rs=MISSING
bats_boundary rs={}
```

4 of 13 entries carry `{}`; **9 carry no such key at all**. "Empty on every entry"
is not what is on disk. The step's conclusion (nothing to migrate) survives, but
its AC ("the live baseline's percentiles are numerically identical before and
after") should be measured against a file where most entries lack the field
entirely — a code path the plan does not currently distinguish.

### F5 (LOW) — Step 5 undercounts the profiles it changes

Plan quote (line 203): "the gate sits in **four** merge-path profiles", and the
Edge Case at line 212 enumerates `release_quarantine` as the fourth.

```
yq -r '.gate_profiles | to_entries[] | select(.value.include[]? == "plan_diff") | .key' .aid-o/config/execution.yaml
```
```
standard
full
release
bats_all_quarantine
release_quarantine
```

Five, not four — `bats_all_quarantine` is unaccounted for. It inherits the same
`skip/no_command` → hard-refusal flip and is not named anywhere in the step.

### F6 (INFO) — AC6's nested-quoting yq expression works exactly as written, including through the plan-diff YAML unescaper

Plan quote (line 435):

```yaml
cmd: "test -n \"$(yq -r '.gates.plan_diff.command // \"\"' .aid-o/config/execution.yaml)\""
```

After YAML unescaping the shell command is
`test -n "$(yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml)"`.
Run verbatim via `bash -c`:

```
rc=1
```
which is the **correct pre-fix result** — the key is genuinely absent today
(`yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml` → empty,
rc=0; the shipped default at `defaults/execution.yaml` returns the full
`aid-plan-diff.sh --plan {plan_path} …` string). yq v4.53.2's `// ""` alternative
operator behaves as the plan assumes on a missing key.

I also confirmed the string survives `aid-plan-diff.sh`'s own
`extract_yaml_val()` backslash unescaping intact — dumping the parser's rows
shows the cmd field byte-correct with its embedded double quotes and single-quoted
yq expression:

```
^_^_cmd^_test -n "$(yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml)"^_^_^_0
```

No dependency finding. AC6 is sound.

### F7 (INFO) — GNU-only flags in the files this plan edits, noted against Step 6's own "portable" framing

Nothing here is a regression the plan introduces, but Step 6 makes portability an
explicit value, and the neighbouring code does not share it:

```
/usr/bin/grep -rnE "sed -i(\s|$)|stat -c|date -d |readlink -f|grep -[oq]?P" <the files P083 modifies>
```
```
aid-release.sh:493,538,575,579,636,668,673   sed -i          (BSD sed needs -i '')
aid-review-signals.sh:24,25                  grep -qP        (the Step 6 target)
aid-c0-plan-review.sh:339                    realpath -m --relative-to   (GNU-only)
```

`aid-release.sh:668` (`sed -i "s/v$CURRENT/v$NEW_VERSION/g"`) and `:673` are
exactly the two lines Step 4 rewrites — if the new structure-aware README updater
is written with `sed -i` it inherits GNU-only behaviour in a file the plugin ships
to consumer projects that may be on macOS. `aid-plan-to-epic.sh` (Step 2),
`aid-run-gates.sh` (Step 5), `aid-init-execution-yaml.sh` (Step 7) and
`aid-gate-runtime-baseline.sh` (Step 8) have **zero** such hits and should stay
that way.

Note for whoever runs the ACs by hand: in an interactive Claude Code shell,
`grep` is a **function wrapping ugrep 7.5.0**, not GNU grep. Step 8's AC1
(line 316, `grep -c 'observe_parallel\|parallel' …`) will run under ugrep `-G`
there and under GNU grep inside scripts. The function is not exported
(`export -p | grep -c BASH_FUNC_grep` → `0`), so `bats` suites are unaffected;
only hand-run ACs see the difference.

---

confidence: high

Every claim above is backed by a command executed in this repo at
`1d5cd048172e88b99ee559821f34e6cf5ad7c41a`, with its real exit code and output
quoted. Confidence is lower on one axis only: this machine has GNU grep, GNU sed
and GNU coreutils and **no** second implementation (no busybox, no BSD tools,
no gawk beside mawk), so F1's portability constructs could only be tested
negatively — by showing that GNU accepts non-POSIX syntax — rather than by
running them under a genuinely POSIX-only tool. That is itself the substance of
F1: this environment cannot fail a bad "portable" fix.
