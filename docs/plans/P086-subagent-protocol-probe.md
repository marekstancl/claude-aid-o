---
id: P086-probe
type: probe
status: measured
created: 2026-08-24
author: AI
plan_ref: .aid-o/plans/P086-hooky-a-dva-agenti.md
step: 10
---

# P086 Step 10 — can a hook deliver the current protocol to a subagent?

## Why this is a probe and not a rule

`SubagentStart` is documented as an event that can inject context. What was
**not** verified is that the injected text reaches the subagent at all — and the
whole point of IMP-179 is that a subagent resolves its system prompt from the
*installed plugin cache*, not the live repo, so an out-of-date protocol is
delivered to a role agent three separate times without anyone noticing.

The ecosystem standard requires **measured** event coverage, not assumed
(`/ecosystem/specs/agent-hooks/` rule 7). So this step measures first, and the
registry row exists only if the measurement says it can.

**Three outcomes were possible:** it is seen (wire the rule), it is not seen
(manual pasting stays, and the reason is recorded), it is seen conditionally
(record under what conditions).

## What was measured

**Tool and version — part of the claim:** Claude Code **2.1.238**
(`claude --version`). Note this is NOT the version the ecosystem sheet was
measured on (2.1.226); the sheet's wider matrix does not transfer to it, which
is exactly what `aid-hook-verify.sh` flags as `unmeasured_version`.

**Method.** A throwaway `CLAUDE_CONFIG_DIR`-independent settings file passed with
`--settings`, `--setting-sources user` to cut project and local hooks, a
temporary empty cwd, and:

```
claude -p "<launch exactly one general-purpose subagent, whose prompt asks it to
           report any AID-PROBE-<hex> token it can see, or NO-MARKER>" \
  --settings <probe settings> --setting-sources user \
  --output-format stream-json --include-hook-events --verbose
```

The stream tells us whether the hook ran; the subagent's own answer tells us
whether the text arrived.

### Round 1 — bare stdout

Hook: prints the marker line on stdout, exits 0.

| Observation | Value |
|---|---|
| `SubagentStart:general-purpose` fired | **yes** — `hook_started` then `hook_response` |
| Hook outcome | `success` |
| Hook stdout in the stream | the full marker line, verbatim |
| Subagents spawned | 1, completed 1 |
| **Subagent's answer** | **`NO-MARKER`** |

**Verdict, round 1: the hook runs and its stdout does NOT reach the subagent.**
The event is real, the handler is real, the delivery is not. This is precisely
the shape of failure the ecosystem standard warns about — everything looks
successful from outside.

### Round 2 — the JSON envelope

Round 1 does not distinguish "cannot deliver" from "we used the wrong output
form", and the same run answered that question by accident: the
`SessionStart:startup` hook in the very same stream delivered its text through
`{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext":
"…"}}`, not through bare stdout. So round 2 repeated the probe with that
envelope and `hookEventName: "SubagentStart"`.

| Observation | Value |
|---|---|
| `SubagentStart:general-purpose` fired | **yes** |
| Hook outcome | `success` |
| Hook stdout in the stream | the JSON envelope, verbatim |
| Subagents spawned | 1, completed 1 |
| **Subagent's answer** | **`AID-PROBE-7f3c9a2e`** — the marker |

**Verdict, round 2: delivery works, and only in the envelope.**

Two attempts before this one died on server-side `529 Overloaded` (one of them
after all ten internal retries). Those are recorded here as what they are — no
evidence either way about Claude Code's behaviour — and the measurement above is
the third attempt, which completed.

## Verdict, and what follows from it

**Positive, conditional on the output form.** `SubagentStart` injection reaches
a subagent when and only when it is wrapped in
`hookSpecificOutput.additionalContext`. Bare stdout is the failure the ecosystem
standard warns about in its plainest form: the hook runs, the stream says
`outcome: "success"`, and nothing arrives.

**What was wired, on that basis.**

1. `plugins/aid-orchestrator/hooks/hooks.json` declares `SubagentStart`.
2. `defaults/hook-registry.yaml` carries `subagent_protocol_notice`
   (`owner: agent`, `degree: 3`, `failure: open`).
3. `scripts/aid-hook.sh` wraps EVERY injection it emits in the envelope, once,
   in the dispatcher — not in each handler, because two handlers each emitting
   their own JSON object would concatenate into nothing valid. This also fixed a
   latent defect the probe exposed: the continuity capsule was emitting bare
   text on `SessionStart` and may never have been delivered at all.

**What the rule delivers, and why it is a pointer.** It tells a role agent that
its installed protocol and this checkout's copy of the same role DIFFER, and
gives both paths. It does NOT inject the file. Injecting a working tree's file
into an agent's instructions would let a checked-out repository write them —
a prompt-injection surface AID would be creating for itself. A subagent can read
a file; what it could not do before was know that it should.

**What it still does not guarantee.** Degree 3 is a delivery. Nothing here makes
a subagent read the repository's copy, and the row says so. Pasting a role's
protocol verbatim into a dispatch prompt remains the stronger move where the
protocol genuinely matters (IMP-179).

**Re-measure after any Claude Code upgrade** — the version is part of the claim,
and this one (2.1.238) is already not the version the ecosystem sheet was
measured on (2.1.226).

The probe fixture is disposable by design and lives in the session scratchpad,
not in the repo: it carries a settings file that runs a script, and a settings
file that runs a script is executable code
(`/ecosystem/specs/agent-hooks/` rule 3).
