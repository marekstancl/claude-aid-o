---
name: step-review-roles
description: Reviewer contract for the step review (CP2), the EPIC review (CP3) and the fast-mode review (CP6) — the packet, the five reviewer roles with their questions and stop rules, the evidence rule and the output file shape
user_invocable: false
required_roles: none
---

# Step Review Roles

**Last Updated:** 2026-09-19

The step review (CP2) puts one step's diff in front of one or two reviewers
before the step is closed; the EPIC review (CP3) puts the whole EPIC diff in
front of two or three before the EPIC goes to its gates; the fast-mode review
(CP6) reviews a `/aid-do` working tree the same way, advisory. Every reviewer
of a round gets the same packet and the same rules; only the role section
differs. This file is the source of the role sections: the round engine cuts
one `## Role:` section out of it per reviewer and renders it into
`defaults/prompts/review-prompt-v1.md`, the template every checkpoint shares
with the plan review (`skills/plan-review-roles.md`).

## When to Invoke

Invoke when changing what a step or EPIC reviewer is asked, how a finding must
look, or which roles exist. The controller does not read this file during a
round — it follows the "Step review (CP2) and EPIC review (CP3)" section of
`commands/aid-run.md` — and the reviewers get their role section inside the
rendered prompt. Do NOT invoke for the plan review (`skills/plan-review-roles.md`)
or for CP4 (`agents/verifier.md`).

## The Packet

Every reviewer of a round receives the identical packet, appended to its prompt
after the `--- PACKET ---` marker:

| Part | Source | Why the reviewer gets it |
|---|---|---|
| `step-check.json` | `scripts/aid-step-check.sh` | the deterministic script already ran: range, files outside the step's scope, forbidden paths touched, security patterns, tests and their tiers, handler patterns |
| `dod.md` | `plan.json` (the step's objective and acceptance criteria; the EPIC's for CP3; the task text for CP6) | what the change had to deliver |
| `files.json` | `plan.json` (`outputs`, `allowed_paths`, `forbidden_paths`) | what the step was allowed to touch |
| `diff.patch` | `git diff <range>` from `step-check.json` | the change under review |
| `open-findings.json`, `fix.patch` | the previous round (confirmation rounds only) | what was still open, and what the fix changed |

Reviewers may read the repository at the reviewed commit with read-only tools
beyond the packet; the findings worth paying for usually lie in callers and
tests the diff does not show.

## The Evidence Rule

A finding exists only with both:

- `command` — one read-only command that shows the problem. It must start with
  `grep`, `rg`, `ls`, `find`, `sed -n`, `git grep`, `wc`, `head`, `tail` or
  `bash <script> --help`; or it is a reproduction `bash repro/<name>.sh` that
  the reviewer wrote under the round's `repro/` directory, the only place a
  reviewer may write besides the output file.
- `evidence` — `path:line` at the reviewed commit, `<sha>:path:line` for a
  line of a file the diff deleted or moved (the pre-image at that commit), or
  `absent:path` for a file the step should have produced and did not; several
  separated by `;`. Every file used must be cited. The finding stands when at
  least one citation resolves, so cite the exact line: a wrong number wastes
  that citation.

A finding without both is rejected by `scripts/aid-review-adjudicate.sh` and
recorded in `rejected.json` with the reason. Report only what would lead to
different work if fixed: no style remarks, no praise.

Severity ladder, the same for every role:

| Severity | Meaning |
|---|---|
| `blocker` | the change does not deliver its acceptance criteria, breaks an existing behaviour, or touches what it must not |
| `major` | the change delivers, but wrongly or incompletely (a bug, a missing test, a regression risk) |
| `minor` | anything else worth fixing |

Each role's stop rule below narrows what counts as `blocker` for that role.

### The behaviour trace

When `step-check.json` lists `handler_patterns` (the diff adds or changes a
request handler, route, command entry point or job), a generalist's `blocker`
or `major` finding carries a `behaviour_trace`: the request or invocation, the
path through the code, the sink, and each branch with its outcome. The
adjudicator rejects such a finding without one (`trace_missing`).

## The Output File

One JSON object, written to the path named at the end of the prompt, nothing
else. The shape is `defaults/schemas/review-finding.schema.json`:

```json
{"role": "step_generalist", "checkpoint": "cp2",
 "findings": [
   {"id": "step_generalist-1", "checkpoint": "cp2", "step": 3, "severity": "major",
    "claim": "The confirm-path banner reads `ordinal`, a key the backend stopped sending in this diff.",
    "command": "grep -n 'ordinal' ui/src/lib/validationErrors.ts",
    "evidence": "ui/src/lib/validationErrors.ts:223; wan/api/scan.py:4058",
    "fix": "Read `payload_ordinal` in validationErrors.ts or keep emitting `ordinal`.",
    "behaviour_trace": [{"request": "POST /api/scan/confirm", "path": "scan.confirm → _build_om_conflict → 422 detail", "sink": "banner in SessionDetail",
                         "branches": [{"name": "conflict", "outcome": "banner shows undefined ordinal"}]}]}]}
```

With nothing to report, `findings` is empty and the reason is mandatory:

```json
{"role": "step_security", "checkpoint": "cp2", "findings": [], "no_findings_reason": "The diff adds no input boundary, secret, query or shell call; the two matched rules are in test fixtures."}
```

`step` is the step number under review (`null` for CP3 and CP6). `id` is
`<role>-<n>`. `provider` and `model` may be added; the round records them from
configuration either way.

## Role: step_generalist

The step's diff as the colleague who reviews the pull request. This role checks
that the change delivers its acceptance criteria and nothing else, correctly.

### Questions

1. Does the diff deliver every acceptance criterion in behaviour, not only by name (a criterion "met" by a string, a comment or a test that asserts nothing)?
2. Is anything in the diff outside the step's `outputs` and `allowed_paths`, or inside a forbidden path, that `step-check.json` lists or that you find?
3. Is anything added here untested? Is each added test the cheapest sufficient proof, or does an existing test already cover it (name the covering test, file and case, or concede the test is needed)?
4. Does the change break a caller, a consumer of a file it edits or deletes, or a contract another module relies on?
5. Is there an error, retry or concurrency path the change opens that ends in a silent wrong result?
6. Does any name, path, number or claim in the diff (code, comment, doc) disagree with the repository at this commit?

### Stop rule

A blocker is an acceptance criterion not delivered, a forbidden path touched,
or an existing consumer broken.

## Role: step_security

The step's diff as the reviewer who assumes the input is hostile. This role
runs only when `step-check.json` reports a security pattern.

### Questions

1. For each matched rule in `step-check.json`, is the match real code or a fixture, and is the input it handles validated at the boundary?
2. Does any new endpoint, command or job skip authorization, tenant isolation or a permission check its neighbours perform?
3. Is a secret, token or credential written into code, a fixture, a log or an error message?
4. Can an input reach a shell, a query, a template, a file path or a deserializer without being constrained?
5. Does the change widen what a caller can read or write beyond what the acceptance criteria ask?

### Stop rule

A blocker is an exploitable path: unvalidated input reaching a sink, a missing
authorization check, or a secret in the tree.

## Role: epic_generalist

The whole EPIC diff as the reviewer who signs off before the gates. This role
checks that the steps add up to the EPIC.

### Questions

1. Does the EPIC diff deliver every acceptance criterion of the EPIC, end to end, with the steps' outputs wired to each other?
2. Do two steps' changes conflict (one overwrites or undoes another, two definitions of one thing)?
3. Across the whole added test surface, which tests overlap, and which behaviour the EPIC promises has no test?
4. Is anything in the EPIC diff outside every step's scope, or in a forbidden path?
5. Does the diff leave dead code, a stale comment or a document that now disagrees with the code?
6. What did the step reviews route or carry forward, and is it still open?

### Stop rule

A blocker is an EPIC acceptance criterion not delivered, two steps in conflict,
or a forbidden path touched.

## Role: epic_behaviour

Behaviour of what the EPIC built, at its edges. This role asks what happens on
inputs and states the acceptance criteria do not describe.

### Questions

1. For each new or changed handler, command or job, which input makes it misbehave (empty, duplicate, stale, concurrent, oversized)? Trace the request path and every branch.
2. Is every operation that may be repeated or retried idempotent, and is a mutation guarded where the acceptance criteria require at most once?
3. What happens to a half-finished state (started but never completed, edited between two runs, a crash between two writes)?
4. Who has authority over each artifact or resource the EPIC writes, and can the wrong actor or tenant write it?
5. What does the user see when something fails or is degraded, and is it recorded, not only shown?

### Stop rule

A blocker is an edge where the behaviour is undefined or unsafe (silent pass,
double effect, lost data, a write across an ownership boundary).

## Role: epic_security

The whole EPIC diff as the reviewer who assumes the input is hostile; the same
questions as `step_security` over the EPIC's whole surface, plus the joints
between steps.

### Questions

1. For every input boundary the EPIC adds or changes, is the input validated before it reaches a shell, a query, a template, a file path or a deserializer?
2. Does any new endpoint, command or job skip authorization, tenant isolation or a permission check its neighbours perform?
3. Is a secret, token or credential written into code, a fixture, a log or an error message anywhere in the EPIC?
4. Do two steps together open a path that neither opens alone (one adds an input, another adds a sink)?
5. Does the EPIC widen what a caller can read or write beyond what its acceptance criteria ask?

### Stop rule

A blocker is an exploitable path across the EPIC: unvalidated input reaching a
sink, a missing authorization check, or a secret in the tree.

## Anti-patterns

| Wrong | Right |
|---|---|
| A finding that says "might be a problem" with no command | the command that shows it, or no finding |
| Repeating what `step-check.json` already reports | trust the script; review what it cannot see |
| Answering another role's questions | stay in the role; the others cover the rest |
| `evidence` pointing at a directory, a whole file or a line of the diff | `path:line` at the reviewed commit, `<sha>:path:line` for a deleted line, `absent:path` for a missing file |
| "It is probably covered somewhere" as the answer to the test question | the covering test's file and case, or the finding that the test is missing |

**Last Updated:** 2026-09-19
