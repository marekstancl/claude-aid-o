# Problems with the AID plugin

<!-- created by aid-orchestrator v{{PLUGIN_VERSION}} on {{CREATED_DATE}} -->

One file per project, for every plan it runs. Read by the plugin owner
(`aid-orchestrator`), who collects these files across projects and decides
there — nothing else reads this file, nothing is enforced by it.

## When to write here (and when not)

WRITE when the thing misbehaving is AID itself:
- a gate or precondition refuses a state that is valid;
- a script crashes, or its message tells you to do something that is already true;
- two AID tools contradict each other (one produces what another refuses);
- you had to `--force`, `amend-scope`, or work around AID to finish real work;
- an external reviewer (Codex) reports a plugin defect — the controller writes it.

DO NOT write: defects of the project, of the plan, of the code under test, or
anything already in the project backlog. Those go where they always went.

## How to write

```
### N. <one sentence: what happened>
**Date:** YYYY-MM-DD · **Plugin:** vX.Y.Z · **Doing:** <command / phase, e.g. `/aid-run --auto E-012-2_3`, step 4>
**What happened:** <the message or behaviour, verbatim where short>
**What it caused:** <time lost, wrong state, what had to be redone>
**What I did:** <workaround / --force with reason / gave up>
```

The plugin version is what makes an entry readable a month later ("was this
already fixed?"); read it with
`jq -r .version "$AID_PLUGIN_PATH/.claude-plugin/plugin.json"` — the Stop-hook
reminder prints it too. Facts, not proposals — the fix is decided on the owner's side. The owner marks
each entry `> **PŘEVZATO <date>**` when collected and later `HOTOVO vX.Y.Z` or
`ZAMÍTNUTO`; entries are never deleted, this file is the project's own record.

<!-- entries below, newest last -->
