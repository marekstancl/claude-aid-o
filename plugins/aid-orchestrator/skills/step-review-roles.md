---
name: step-review-roles
description: Reviewer contract for the step review (CP2), the fast-mode review (CP6) and the whole-plan review at plan close (CP7) — the packet, the five reviewer roles with their questions and stop rules, the evidence rule and the output file shape
user_invocable: false
required_roles: none
---

# Step Review Roles

**Last Updated:** 2026-09-20

The step review (CP2) puts one step's diff in front of one or two reviewers
before the step is closed; the fast-mode review
(CP6) reviews a `/aid-do` working tree the same way, advisory; the whole-plan
review (CP7) reads the range of a finished plan once before the decision to
merge. (The EPIC review, CP3, and its three roles were removed in 3.0.0 with
the EPIC path, P114.) Every reviewer
of a round gets the same packet and the same rules; only the role section
differs. This file is the source of the role sections: the round engine cuts
one `## Role:` section out of it per reviewer and renders it into
`defaults/prompts/review-prompt-v1.md`, the template every checkpoint shares
with the plan review (`skills/plan-review-roles.md`).

## When to Invoke

Invoke when changing what a step or whole-plan reviewer is asked, how a finding must
look, or which roles exist. The controller does not read this file during a
round — it follows the "Step review (CP2)" section of
`commands/aid-run.md` — and the reviewers get their role section inside the
rendered prompt. Do NOT invoke for the plan review (`skills/plan-review-roles.md`).

## The Packet

Every reviewer of a round receives the identical packet, appended to its prompt
after the `--- PACKET ---` marker:

| Part | Source | Why the reviewer gets it |
|---|---|---|
| `step-check.json` | `scripts/aid-step-check.sh` | the deterministic script already ran: range, files outside the step's scope, forbidden paths touched, security patterns, tests and their tiers, handler patterns |
| `dod.md` | `plan.json` (the step's objective and acceptance criteria; the task text for CP6) | what the change had to deliver |
| `files.json` | `plan.json` (`outputs`, `allowed_paths`, `forbidden_paths`) | what the step was allowed to touch |
| `diff.patch` | `git diff <range>` from `step-check.json` | the change under review |
| `open-findings.json`, `fix.patch` | the previous round (confirmation rounds only) | what was still open, and what the fix changed |

At CP7 `dod.md` is the plan's acceptance and success criteria, `files.json`
declares no scope, and the packet adds `plan-diff.json` (which executed test
proves which criterion), `gates_report.json` (the gates at the candidate),
`epic-findings.json` (what the step rounds of each run left open, so it is
not judged twice) and `claims.patch` (the CHANGELOG, README and docs hunks).

**A CP7 confirmation round** (the first round of an attempt after any fix, AID 3.12.0) carries `open-findings.json`
and `fix.patch`. Re-check every open finding wherever it lies. A NEW problem counts only when its FIRST evidence
citation is a line the fix added or changed; a new non-blocker cited elsewhere becomes `follow_up` (it goes to the
project's backlog and does not block the close). A blocker counts from anywhere. `final_criteria` judges the
brief's points as in a full round — a brief point weakened by the fix is never a follow-up.

Reviewers may read the repository at the reviewed commit with read-only tools
beyond the packet; the findings worth paying for usually lie in callers and
tests the diff does not show.

## The Evidence Rule

A finding exists only with both:

- `command` — one read-only command that shows the problem. It must start with
  `grep`, `rg`, `ls`, `find`, `sed -n`, `git grep`, `wc`, `head`, `tail` or
  `bash <script> --help`; or it is a reproduction, either `bash repro/<name>.sh`
  written under the round's `repro/` directory — the only place a reviewer may
  write besides the output file — or inline as `bash -c '<pipeline>'` whose every segment starts with one of `grep rg ls git
  wc head tail cat printf echo jq test [[ [` (`git` only with
  `grep|log|show|diff|blame|rev-parse|status`), with no redirection, no command
  substitution, no process substitution, no newline, no backslash, no in-place
  flag, and no verb that has a write mode at all. The list is closed: a verb that is not on it
  is refused whatever it does, which is how `mkdir`, `touch`, `sed`, `find`,
  `yq` and the words `if`, `for` and `do` are kept out. A reproduction that
  needs any of them is a `repro/<name>.sh` file, which a human can read once
  before running it.
- `evidence` — `path:line` or `path:first-last` at the reviewed commit,
  `<sha>:path:line` for a line of a file the diff deleted or moved (the
  pre-image at that commit), or `absent:path` for a file the step should have
  produced and did not; several separated by `;`. Citations only: a word or a
  bracketed note after a line number makes the field unreadable and the finding
  is dropped, so what the line shows goes in `claim`. A range stands on its first
  line, which is what the finding is matched by across rounds. Every file used must be cited. The finding stands when at
  least one citation resolves, so cite the exact line: a wrong number wastes
  that citation.

A finding without both is rejected by `scripts/aid-review-adjudicate.sh` and
recorded in `rejected.json` with the reason. Report only what would lead to
different work if fixed: no style remarks, no praise.

Severity ladder, the same for every role:

| Severity | Meaning |
|---|---|
| `blocker` | the change does not deliver its acceptance criteria, breaks an existing behaviour, or touches what it must not |
| `major` | the change delivers, but wrongly or incompletely (a bug, a regression risk, a missing test — only when the finding names the acceptance criterion that cannot be verified without it) |
| `minor` | anything else worth fixing |

Each role's stop rule below narrows what counts as `blocker` for that role.

A `blocker` or `major` (not at CP1) also names its `rule`: the invariant the
finding breaks, stated so it can be checked everywhere, not only at the cited
line ("every served path resolves inside the brand root", "only allowlisted tags
and attributes pass the filter"). The cited line is one place the rule fails;
the author fixes the rule, and the confirmation round checks it holds
everywhere. An answer whose blocker or major has no `rule` goes back once.

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
    "rule": "Every field the banner reads is one the confirm endpoint still sends.",
    "behaviour_trace": [{"request": "POST /api/scan/confirm", "path": "scan.confirm → _build_om_conflict → 422 detail", "sink": "banner in SessionDetail",
                         "branches": [{"name": "conflict", "outcome": "banner shows undefined ordinal"}]}]}]}
```

With nothing to report, `findings` is empty and the reason is mandatory:

```json
{"role": "step_security", "checkpoint": "cp2", "findings": [], "no_findings_reason": "The diff adds no input boundary, secret, query or shell call; the two matched rules are in test fixtures."}
```

`step` is the step number under review (`null` for CP6 and CP7). `id` is
`<role>-<n>`. `provider` and `model` may be added; the round records them from
configuration either way.

## Role: step_generalist

The step's diff as the colleague who reviews the pull request. This role checks
that the change delivers its acceptance criteria and nothing else, correctly.
It reads every step the step check does not skip, as the light reviewer
(`effort: low`; the full one above `light_max_prompt_lines`); the choice is in
`round.json` `agents` (`aid-review-round.sh` `_agent_type`).

### Questions

1. Does the diff deliver every acceptance criterion in behaviour, not only by name (a criterion "met" by a string, a comment or a test that asserts nothing)?
2. Is anything in the diff outside the step's `outputs` and `allowed_paths`, or inside a forbidden path, that `step-check.json` lists or that you find?
3. Is anything added here untested? Is each added test the cheapest sufficient proof, or does an existing test already cover it (name the covering test, file and case, or concede the test is needed)? A test that names no acceptance criterion and no defect it catches is reported as `minor` with the recommendation to delete it. Which existing test does this change make obsolete — one that guards behaviour the diff removes, or a frozen list or text the diff edits? Name it; it is deleted in this step.
4. Does the change break a caller, a consumer of a file it edits or deletes, or a contract another module relies on?
5. Is there an error, retry or concurrency path the change opens that ends in a silent wrong result?
6. Does any name, path, number or claim in the diff (code, comment, doc) disagree with the repository at this commit?
7. Is anything here more than the step needs: a hand-written replacement of a standard function, an abstraction with one use, a dependency for a few lines, scaffolding for later? Name what to delete or what replaces it. `major` when the diff would be materially shorter, else `minor`; a criterion that asks for the abstraction wins.

### Stop rule

A blocker is an acceptance criterion not delivered, a forbidden path touched,
or an existing consumer broken.

## Role: step_security

The step's diff as the reviewer who assumes the input is hostile. This role
reviews every step that is not skipped (a project can still gate it with
`when: review+security`): as the light reviewer on the verdict `review`, as the
full reviewer on `review+security` (`full_when`, P110; `round.json` `agents`
records which). The rules `step-check.json` matched, when any, are
where to start, not the edge of the review. A web server, a path taken from a
caller or text rendered as HTML/SVG/CSS matches no pattern and is exactly
where the later rounds of P101/P102 found their holes.

### Questions

1. Where does the diff take input from outside (a request, a caller's path or port, a file, user or model text it renders)? Is it accepted by an allowlist, checked after it is resolved, at the boundary? For each rule `step-check.json` matched, is the match real code or a fixture?
2. Does any new endpoint, command or job skip authorization, tenant isolation or a permission check its neighbours perform?
3. Is a secret, token or credential written into code, a fixture, a log or an error message?
4. Can an input reach a shell, a query, a template, a file path or a deserializer without being constrained?
5. Does the change widen what a caller can read or write beyond what the acceptance criteria ask?

### Stop rule

A blocker is an exploitable path: unvalidated input reaching a sink, a missing
authorization check, or a secret in the tree.

## Role: final_criteria

The finished plan against what it promised. You hold the PM's brief
(`zadani.md`), the plan's acceptance and success criteria (`dod.md`) and the
record of what was executed (`plan-diff.json`, measured at the close in
isolation; `gates_report.json`), and you check each promise against a proof
that ran.

### Questions

1. Point by point of the brief (`zadani.md`, every `AC<n>`): quote the measured verdict of `plan-diff.json` for it (`present`, `absent` with its reason, or `skipped`), and judge the delivery against the point's TEXT — does it keep it (`zachovává`), soften it (`změkčuje`), drop part of it (`vypouští`) or contradict it (`odporuje`)? A point whose measured verdict is `absent` is a blocker finding, whatever else proves it; an `absent` with a reason of `no_isolation`, `env_stripped`, `no_verification_env` or `verification_env_unset` was NOT measured — say so, never count it as passed.
2. For every other acceptance criterion of the plan: which executed test or gate row proves it? Name the test by `path:line` and its result in `plan-diff.json`.
3. Is any criterion recorded as verified while its test was skipped, not selected, or does not assert what the criterion says?
4. Is any criterion proven only by a manual step, a live system or a later deployment that the range does not contain?
5. Does a success criterion of the plan as a whole have no proof at all in the range?

### Stop rule

A blocker is a brief point measured `absent`, or an acceptance criterion with
no executed proof at the candidate. A delivery that softens or drops part of a
brief point, or a criterion whose proof is weaker than its wording, is a major.

## Role: final_claims

Optional — not in the default policy since 2.116.0 (P110): `final_generalist`
holds the claims question. A project that lists `final_claims` in its own
`review-checkpoints.yaml` gets this role as before.

What the delivery says about itself against what the code does. You hold
`claims.patch` (CHANGELOG, README and docs hunks of the range) and the code at
the candidate. In a step review (CP2, P117: the default policy asks this role
when the step changes documentation — `when: docs_surface`) the claims are the
documentation hunks of the step's `diff.patch`, checked against the code at the
step's commit; question 3 then reads the step's objective instead of the plan's
type.

### Questions

1. For every behavioural claim in the CHANGELOG, README and docs hunks: does the code at the candidate do it? Cite the line that does, or the absence.
2. Does a binding instruction for whoever deploys or operates this (an order of steps, a migration, a flag that must be set) live only outside the delivered files: in a backlog, a plan, a chat?
3. Does the diff contradict the plan's declared type (a docs-only or refactor plan that changes behaviour, a plan that says "no API change" and changes one)?
4. Does a user-facing change of the range have no CHANGELOG line at all?

### Stop rule

A blocker is a false claim: the delivery says the system does something it
does not do, or a binding instruction exists only outside what is delivered.

## Role: final_generalist

The whole range as a colleague from another provider reads it, across the
steps. The step reviews already judged each step alone (`epic-findings.json`,
what they left open); you look for what none of them could see.

### Questions

1. Does a change of one step break a caller, a consumer or a test that another step of the same plan touched or relied on?
2. Is anything half-done across the steps: a function one step adds and no step calls, a flag one step reads and none sets?
3. What the step reviews left open is listed in `epic-findings.json`; questions 1 and 2 are the cross-step read.
4. Does the range remove or weaken an existing behaviour that no criterion of the plan asked to change?
5. Is a finding the step reviews left open still true at the candidate? Report it once, with today's evidence.
6. Claims (`claims.patch`: CHANGELOG, README and docs hunks): does the code at the candidate do every behavioural claim, and does a binding instruction for whoever deploys or operates this live only outside the delivered files? (A project that keeps `final_claims` has that role ask this too.)
7. Security and operations, across the range — answer each, `none` when it does not apply:
   - a new personal datum: where is it stored, and how is it deleted (retention, the user's request)?
   - repository layout vs. host layout: does a path, mount, port or file the code expects exist on the host it deploys to?
   - new dependencies, per CI job: is each one installed in every job that runs the code (a library the tests import, a binary a script calls)?
   - the documentation build: does a changed doc page still build (links, frontmatter, sidebar)?
   - data leaking to logs or notifications (Telegram, e-mail): a secret, a token, a personal datum, a whole request?
   - account boundaries: can one user, tenant or role now read or change what another owns?
   - injection across the range: does an input one step adds (a request field, a CLI option, a file name, model text) reach a shell, a query, a template rendered as HTML/SVG/CSS or a file path in another step, unconstrained? Trace each new input to its sinks.
   - paths and deletion: a path taken from a caller resolved after the check, a symlink followed while deleting or writing?
   - forged trust: can an approval, a review record or other evidence the code trusts be written by the one it is meant to check?

### Stop rule

A blocker is a break that exists only when the steps are read together (a
broken consumer, an unwired half, a behaviour lost that nobody asked to lose),
a false claim, or an exploitable path or data leak from the checklist.

## Anti-patterns

| Wrong | Right |
|---|---|
| A finding that says "might be a problem" with no command | the command that shows it, or no finding |
| Repeating what `step-check.json` already reports | trust the script; review what it cannot see |
| Answering another role's questions | stay in the role; the others cover the rest |
| `evidence` pointing at a directory, a whole file or a line of the diff | `path:line` or `path:first-last` at the reviewed commit, `<sha>:path:line` for a deleted line, `absent:path` for a missing file |
| `evidence` with a note after the citation, `a.py:12 (the removed call)` | the citation alone; the note belongs in `claim` |
| "It is probably covered somewhere" as the answer to the test question | the covering test's file and case, or the finding that the test is missing |

**Last Updated:** 2026-09-20
