# Claude reviewers of a review round — controller instruction

The Agent tool is not callable from bash, so the controller dispatches every
reviewer whose provider is `claude`, at every checkpoint: the plan review
(`commands/aid-plan.md` "Plan review (CP1)") and the step, EPIC and fast-mode
reviews (`commands/aid-run.md` "Step review (CP2) and EPIC review (CP3)",
`commands/aid-do.md`) include this text verbatim. `<round dir>` is the
directory `prepare` printed, and `prepare` prints each role's `<focus>` next
to its prompt: `cp1-<role>` for a plan, `cp2-step-<N>-<role>` for a step,
`cp3-<role>` for an EPIC, `cp6-<role>` in fast mode, `cp7-<role>` at plan
close, the role with `_` replaced by `-` (the dispatch wrapper allows no
underscore in `--focus` or `--agent-id`).

For EACH expected role with `provider: claude` in `<round dir>/round.json`,
one at a time:

1. Open the dispatch:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus <focus> \
     --agent-id aid-orchestrator:review --evidence-dir <round dir>
   ```

2. Dispatch the reviewer with this one-line prompt, never the file's content
   (a packet runs to hundreds of kilobytes; pasted copies would fill the
   controller's own context):

   ```
   Agent(subagent_type: <the agent prepare printed next to the role's prompt>, model: <the model printed there>,
         prompt: "Your complete instructions are in <round dir>/prompt-<role>.md. Read that whole file first and follow it exactly.")
   ```

   A harness that does not know `aid-orchestrator:reviewer-light` yet (an older
   installed plugin) takes `general-purpose` at the same model.

   The reviewer writes `<round dir>/reviewer-<role>.json` itself. Note the
   `subagent_tokens` figure the Agent result reports; when the result shows
   none, the value is `unknown`.

3. Close the dispatch. `<answer>` is `<round dir>/reviewer-<role>.json`; when
   the reviewer wrote no file, create the empty marker
   `<round dir>/reviewer-<role>.missing` and use that path instead:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus <focus> \
     --output-file <answer> --evidence-dir <round dir>
   ```

   A step round's `close` refuses a reviewer file with no such start/complete
   bracket in `<round dir>/timeline.jsonl` (`no_dispatch_record`): a file
   nobody dispatched does not close a round. Only a round prepared with
   `--stub` by the acceptance suite skips that check, and the FSM refuses to
   advance on such a round.

## Stand-in for a Codex role

When `dispatch --provider codex` prints a line starting `STAND-IN:`, no codex
answer came (absent, outdated, over its usage limit, or a run that left no
answer) and the round records `fallback: "claude"` for that role. Dispatch it
exactly as above — the same prompt file, the same start/complete bracket — as
the agent and at the model the STAND-IN line names (`stand_in_model` of the
checkpoint's block), and tell the reviewer to write `"provider": "claude"` in its answer.
`collect` accepts a claude answer for a codex role ONLY with that record, and
counts a stand-in nobody dispatched as missing, which makes the round invalid.
Pass its token figure to `close` like any claude role. The PM card names the
stand-in and the reason in one line; the PM is told, not asked.

After ALL reviewers of the round (claude and codex) have been dispatched, run
`collect`. Only when `collect` exits 0, run `close` once with a token value for
every claude role; when it reports the round invalid, retry the roles it names
first (`close` refuses an invalid round). `<review>` is `--plan <plan>` for
CP1, `--checkpoint cp2 --evidence-dir <run dir> --step <N>` for a step,
`--checkpoint cp3 --evidence-dir <run dir>` for an EPIC:

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" collect <review> --round K
bash "$AID_PLUGIN_PATH/scripts/aid-review-round.sh" close <review> --round K \
  --tokens <role>=<n|unknown> ...
```

When `close` reports `fail` on a step or EPIC round and a round remains
(`rounds_default`, or the PM's `override`), the fix is the step's own role's:

```
Agent(subagent_type: <"aid-orchestrator:implementer-light" when the step's role card says **Effort:** low, else "aid-orchestrator:implementer">,
      model: <the **Model:** of the step's role card in skills/role-cards.md>,
      prompt: "fix_of: <round dir>; role: <the step's role card name>. Read <round dir>/merged.json, fix every finding with status open (blocker and major first), commit with the message prefix fix(review):, and report the finding fingerprints you addressed. Touch nothing a finding does not name.")
```

Then `aid-step-check.sh` again (the range now ends at the fix commit) and
`prepare --round K+1`: the confirmation round asks only the reporters of what
stayed open and shows them the open findings and the fix diff. Record the
fixer's model and tokens on the next `close` with
`--fixer <role>=<model>:<tokens_in>:<tokens_out>`.

When `close` reports `fail` on the LAST allowed round, it has already written
what stays open where the plan-final boundary reads it: a blocker or major a
later step's declared files cover becomes a carried obligation
(`carried` in merged.json); any other, and every one at cp3, is routed to the
EPIC (`routed`) and done-advance refuses until the PM resolves or backlogs it
(`skills/pipeline.md` §13). Say so on the PM card; do not route by hand what
`close` routed.

Never edit a reviewer's file, never write one on a reviewer's behalf, and never
dispatch a role twice: a role `collect` lists as invalid or missing goes
through `retry`, then this procedure for that role alone. A reason that starts
`form:` means a finding would have been dropped for its form: quote that reason
to the same reviewer; it is asked once, and a second malformed finding is dropped.
