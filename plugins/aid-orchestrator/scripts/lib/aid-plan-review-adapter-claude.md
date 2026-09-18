# Claude reviewers of a plan-review round — controller instruction

The Agent tool is not callable from bash, so the controller dispatches every
reviewer whose provider is `claude`. `commands/aid-plan.md` "Plan review (CP1)"
includes this text verbatim. `<round dir>` is the directory `prepare` printed.

For EACH expected role with `provider: claude` in `<round dir>/round.json`,
one at a time (`<focus>` is `cp1-` plus the role with `_` replaced by `-`, for
example `cp1-generalist-a`, `cp1-behaviour-edges`; the dispatch wrapper allows
no underscore in `--focus` or `--agent-id`):

1. Open the dispatch:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus <focus> \
     --agent-id aid-orchestrator:plan-review --evidence-dir <round dir>
   ```

2. Dispatch the reviewer with the prompt file's full content, unchanged:

   ```
   Agent(subagent_type: "general-purpose", model: <the role's model from review_checkpoints.plan_review>,
         prompt: <content of <round dir>/prompt-<role>.md>)
   ```

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

After ALL reviewers of the round (claude and codex) have been dispatched, run
`collect`. Only when `collect` exits 0, run `close` once with a token value for
every claude role; when it reports the round invalid, retry the roles it names
first (`close` refuses an invalid round):

```bash
bash "$AID_PLUGIN_PATH/scripts/aid-plan-review-round.sh" collect <plan> --round N
bash "$AID_PLUGIN_PATH/scripts/aid-plan-review-round.sh" close <plan> --round N \
  --tokens generalist_a=<n|unknown> behaviour_edges=<n|unknown> ...
```

Never edit a reviewer's file, never write one on a reviewer's behalf, and never
dispatch a role twice: a role `collect` lists as invalid or missing goes
through `retry`, then this procedure for that role alone.
