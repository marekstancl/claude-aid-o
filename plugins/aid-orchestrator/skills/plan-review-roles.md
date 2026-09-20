---
name: plan-review-roles
description: Reviewer contract for plan review (CP1) — the packet, the six reviewer roles with their questions and stop rules, the evidence rule and the output file shape
user_invocable: false
required_roles: all
distinct_models: [generalist_a, generalist_b]
---

# Plan Review Roles

**Last Updated:** 2026-09-20

Plan review (CP1) puts a written plan in front of six reviewers before any EPIC
is generated. Every reviewer gets the same packet and the same rules; only the
role section differs. This file is the source of the role sections:
`scripts/aid-review-round.sh prepare --plan` cuts one `## Role:` section out of
it per reviewer and renders it into `defaults/prompts/review-prompt-v1.md`, the
template every review checkpoint shares (the step and EPIC roles live in
`skills/step-review-roles.md`).

## When to Invoke

Invoke when changing what a reviewer is asked, how a finding must look, or which
roles exist. The controller does not read this file during a round — it follows
the "Plan review (CP1)" section of `commands/aid-plan.md`, and the reviewers get
their role section inside the rendered prompt. Do NOT invoke for CP2 to CP6
(`skills/review-checkpoint-contracts.md`).

## The Packet

Every reviewer of a round receives the identical packet, appended to its prompt
after the `--- PACKET ---` marker:

| Part | Source | Why the reviewer gets it |
|---|---|---|
| `plan-check.json` warnings | `scripts/aid-plan-check.sh` | the deterministic script already ran; a reviewer does not repeat its findings |
| `standards.md` | `scripts/lib/aid-standards-map.sh` for the plan's declared paths | the project standards the plan is bound by |
| `plan.md` | the plan snapshot the round was prepared from | the text under review, cited as `plan.md:<line>` |

The packet is built only when `plan-check.json` matches the plan's sha256, so
reviewers always review what the script saw. Reviewers may read the repository
with read-only tools beyond the packet; the findings worth paying for usually
lie in files the plan names but does not quote.

## The Evidence Rule

A finding exists only with both:

- `command` — one read-only command that shows the problem. It must start with
  `grep`, `rg`, `ls`, `find`, `sed -n`, `git grep`, `wc`, `head`, `tail` or
  `bash <script> --help`; or it is a reproduction, either `bash repro/<name>.sh`
  under the round's `repro/` directory or inline as `bash -c '<pipeline>'` whose every segment starts with one of `grep rg ls git
  wc head tail cat printf echo jq test [[ [` (`git` only with
  `grep|log|show|diff|blame|rev-parse|status`), with no redirection, no command
  substitution, no process substitution, no newline, no backslash, no in-place
  flag, and no verb that has a write mode at all. The list is closed: a verb that is not on it
  is refused whatever it does, which is how `mkdir`, `sed`, `find`, `yq` and
  the words `if`, `for` and `do` are kept out. A reproduction that needs any of
  them is a `repro/<name>.sh` file.
- `evidence` — `path:line` or `path:first-last` inside the repository,
  `absent:path` for a file the plan presumes and the repository lacks, or
  `plan.md:line` for the plan itself; several separated by `;`. Every file used
  must be cited. A range stands on its first line.

A finding without both is rejected by `scripts/aid-review-adjudicate.sh`
and recorded in `rejected.json` with the reason. Report only what would lead to
different work if fixed: no style remarks, no praise.

Severity ladder, the same for every role:

| Severity | Meaning |
|---|---|
| `blocker` | the plan as written cannot be implemented, or it breaks an existing behaviour |
| `major` | a step will produce wrong or incomplete work |
| `minor` | anything else worth fixing |

Each role's stop rule below narrows what counts as `blocker` for that role.

## The Output File

One JSON object, written to the path named at the end of the prompt, nothing
else. The shape is `defaults/schemas/review-finding.schema.json` (an answer
without a `checkpoint` is a plan-review answer):

```json
{"role": "reuse",
 "findings": [
   {"id": "reuse-1", "step": 3, "severity": "major",
    "claim": "Step 3 founds a packet library although the dispatch contract already assembles the same envelope.",
    "command": "grep -n packet scripts/lib/aid-dispatch-contract.sh",
    "evidence": "scripts/lib/aid-dispatch-contract.sh:40; plan.md:295",
    "fix": "Step 3 reuses aid-dispatch-contract.sh or states why it cannot."}]}
```

With nothing to report, `findings` is empty and the reason is mandatory:

```json
{"role": "reuse", "findings": [], "no_findings_reason": "Every Create bullet was searched by behaviour; nothing reusable exists."}
```

`step` is the plan step number, or `null` for a plan-level finding. `id` is
`<role>-<n>`. `provider` and `model` may be added; the round records them from
configuration either way.

## Role: generalist_a

The whole plan as a reader who must implement it tomorrow. This role checks that
every step can be started from what is written and that the parts agree.

### Questions

1. Is any step impossible to start from what is written (a missing file, function or contract it presumes)?
2. Do the step order and the `Depends on` lines match what each step actually needs from earlier ones?
3. Are there acceptance criteria that cannot be checked mechanically as written?
4. Does the plan contradict itself (Data Model against a step, Scope against Files, Architecture against a command)?
5. Is anything in Scope delivered by no step, or delivered by a step while declared out of scope?
6. Is every section the plan template requires present and filled (Goal, Scope, Files, Acceptance Criteria, Testing Strategy, Risks)?

### Stop rule

A blocker is a step that cannot be implemented as written, or a contradiction
between two parts of the plan.

## Role: generalist_b

The whole plan as an opponent who wants it to fail in production. This role
looks for promises without mechanism and for damage to what already works.

### Questions

1. Where would an agent following this plan produce something that looks done but is not enforced (prose instead of mechanism)?
2. Which existing behaviour does the plan silently change or break (consumers of files it deletes or rewrites)?
3. Which numbers, names or paths are asserted but not grounded in the repository?
4. What does Goal or Success Criteria promise that no step's acceptance criteria covers?
5. Where is the plan larger than it needs to be (a step that delivers nothing a later step or the Goal needs)?

### Stop rule

A blocker is a promise with no mechanism behind it, or a break of an existing
consumer.

## Role: behaviour_edges

Behaviour of what the plan builds, at its edges. This role asks what happens on
inputs and states the plan does not describe.

### Questions

1. For each new command, endpoint or handler, which input makes it misbehave that the plan does not name (empty, duplicate, stale, concurrent)?
2. Is every operation that may be repeated or retried idempotent as described, and is a mutation guarded where the acceptance criteria require at most once?
3. What happens to a half-finished state (started but never completed, edited between two runs)?
4. Who has authority over each artifact or resource the plan writes, and can the wrong actor or tenant write it?
5. Does any decision depend on state that a later step can change without the decision being taken again?
6. What does the user or PM see when something fails, is degraded or is overridden, and is that recorded in a file, not only in chat?

### Stop rule

A blocker is an edge where the described behaviour is undefined or unsafe
(silent pass, double effect, lost evidence, a write across an ownership
boundary).

## Role: feasibility_deps

Can each step be built against the real repository and its dependencies. This
role checks every interface the plan relies on.

### Questions

1. For every function, script, schema, key or file the plan reuses, does it exist with the interface the plan assumes (arguments, outputs, exit codes)?
2. For every file the plan modifies with line ranges, is the content at those lines what the plan describes?
3. Are there callers of the files the plan rewrites or deletes that it does not list?
4. Does a step consume an output, field or artifact that no earlier step produces?
5. Does any step depend on a tool, key or behaviour that another step removes earlier or creates later?
6. Does the plan use a library or external API method, parameter or response shape that the version in use does not have?

### Stop rule

A blocker is a reused interface that does not exist as assumed, a consumer that
reads before its producer exists, or an unlisted caller of a deleted file.

## Role: reuse

Does the plan found things that already exist. This role judges whether each
search for something reusable was wide enough, not whether it was replayed.

### Questions

1. For every `Create:` bullet, is there an existing library, script, schema or skill section that already does the same job? Search by what the thing does, not by its new name.
2. Where the plan founds a variant deliberately, is the stated reason true?
3. Is a `**Reuse check:**` search too narrow (the step's own new name, one directory when the pattern plausibly lives in several)?
4. Is there an existing helper the plan should reuse but does not name?
5. Does planned reuse break the reused component's contract (a different signature, contradictory state, a behaviour change for its other callers)?
6. Do new artifacts duplicate information already recorded elsewhere?

### Stop rule

A blocker is a `Create:` bullet that duplicates an existing mechanism with the
same purpose, or reuse that breaks the reused component's other callers.

## Role: enforcement_tests

Is every claim enforced and testable. This role follows each "refuses",
"blocks", "requires" and "records" to the test that would break it.

### Questions

1. For each mechanism the plan claims, which step's test breaks it, and does that test exercise the refusal path?
2. Are test tiers right (t0 under 2 s per case, t1 under 30 s, t2 otherwise or cross-component), and does the merge path stay green at every step?
3. Does every new enforcement have a registry row with an existing test, and does every row the plan names match the registry's field set?
4. Is any artifact the plan relies on unreachable where it is needed (gitignored, not in CI, a test file the runner never discovers)?
5. Is anything in Success Criteria unreachable by any test the plan names?

### Stop rule

A blocker is a mechanism with no breaking test, a test that cannot run where the
plan says it runs, or an artifact the enforcement needs but cannot see.

## Anti-patterns

| Wrong | Right |
|---|---|
| A finding that says "might be a problem" with no command | the command that shows it, or no finding |
| Repeating a `plan-check.json` warning | trust the script; review what it cannot see |
| Answering another role's questions | stay in the role; the others cover the rest |
| `evidence` pointing at a directory or a whole file | `path:line` or `path:first-last` of the lines that show it |

**Last Updated:** 2026-09-20
