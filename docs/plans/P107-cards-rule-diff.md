# P107 Step 5 — the rewritten agent cards: what each rule became

Five cards remain (`agents/`): implementer, implementer-light, reviewer-light, gate-fixer,
project-scanner. Each was rewritten into four sections — Task, Inputs, Output, Rules — with
every rule carrying its reason in the same sentence, no persona line ("You are …"), no
capitalised MUST/NEVER. The PM reads this table, not the whole text (PM 2026-09-30, the
critic's level-2 note); the full text is in the card. Auditor, verifier and simplifier were
deleted (their checks live in the review rounds, see `reference/review-successors.md`).

## implementer (51 → 54 lines) and implementer-light (identical, effort medium, "a small, well-bounded change")

| Rule in the old card | Now |
|---|---|
| "You are an AID implementer agent. Your exact role is …" | dropped as persona; the role comes from the task input (Task) |
| 1-5: role card pasted after the contract, read agent-protocol, read context_files, execute per card, produce the output format | kept, as Inputs and Output |
| Controller boundary paragraph | kept as one sentence in Inputs pointing at agent-protocol (the one text) |
| Input from outside: boundary before the feature, allowlist, resolve then check, hostile variants; the step reviewer checks it | kept whole, with the reason ("a missing boundary is a finding") |
| fix_of: fix the rule not the example, everywhere, at the root; "add a test for the reviewer's example and at least two other variants" | kept, except the test sentence, which is now "test the rule once on the path the finding names; a second case only on a different code path" (PM 2026-09-30, Step 2: 32 of 125 tests since 2.107.0 came from this instruction) |
| — | added: the least-code ladder summarised in one rule (it was only in the pasted role card) |

## reviewer-light (16 → 35 lines)

| Old | Now |
|---|---|
| "A reviewer of an AID review round whose role runs at low effort … read the prompt file first" | kept as Task and Inputs; adds that a longer prompt goes to the full reviewer (`light_max_prompt_lines`, 2.111.0) |
| Controller boundary | kept |
| — | added Rules: a finding needs a command and a resolving citation (the adjudicator drops the rest); only what changes the work; read the packet, not memory — all three were in the prompt file already, restated because this card is what the agent reads first |

## gate-fixer (197 → 58 lines)

| Old | Now |
|---|---|
| Role/Type/Dispatched-by header; "You are the Gate Fixer agent …" | Task (one paragraph, keeps: GATES state, review findings are never yours) |
| Capabilities per gate (tests, lint, security, docs, type check, build) with per-gate "Never" lines | merged into the rules "never bypass the gate" (the full list of forbidden suppressions kept) and "test or implementation?" (docs gate: accurate text, never a placeholder) — the per-gate how-to lists (ruff --fix, tsconfig, circular deps) dropped: the model knows its tools |
| Constraints — CRITICAL: scope, no gate bypassing (table), minimal changes | kept whole, as three rules with reasons; the one exception (a justified suppression with a comment) kept with its example |
| Output Format YAML with Status Values, Source Types, Confidence Levels tables | the YAML block kept with the three tables folded into its comments |
| Workflow (9 numbered steps) | merged into "root cause first" (read output, analysis, previous attempts before editing) |
| Important: utility agent, test vs implementation, unable when no root cause, "will be replaced by role agents in Run 4" | kept the first three as rules; the Run 4 promise dropped (never happened) |

## project-scanner (1 106 → 113 lines)

| Old | Now |
|---|---|
| Identity; Three Modes (A quick, B deep, C memory) | Task: Modes A and B; Mode C (Qdrant memory scan: full, incremental, kondice — ~720 lines) moved unchanged to `reference/memory-scan-protocol.md` because nothing dispatches it (`/aid-init` writes memory from the controller, the ecosystem forbids the `qdrant-brain` tools it names, no project ran it) — backlog IMP-682 |
| Quick Scan Protocol steps 1-5 (indicator files, tech stack detection, structure, app_type table, conventions, output) | Inputs (the indicator list, git log/branch) + Output (`app_type` values with their indicators, in prose) + Rules (conventions from evidence, quick means quick) |
| Deep Analysis Additions (code quality, dependency audit, architecture, tech debt) | Task, one sentence each (restored after the Codex review found the first rewrite said only "a `quality` section") + Rules ("deep means bounded: sample, skip generated dirs") |
| Constraints — CRITICAL: read-only table, scan scope limits, output paths, dedup rule | read-only, no install/build, never guess a version, confidence — kept as rules with reasons; the dedup rule went with Mode C |
| Project Profile Format (the YAML schema); the `scanner_result` reply block | both kept verbatim in Output (the reply block restored after the Codex review) |
| Important: specialist not role agent, confidence, quick vs deep, memory quality, project.yaml overwritten per scan, memory complementary, partial status | kept: confidence, quick/deep, partial status; "each scan overwrites" replaced by the merge rule of `skills/setup/project-scan.md` (merge, never overwrite PM fields — the rule `/aid-init` already states); memory lines went with Mode C |

**PM:** „ok“ (2026-09-30, po rozpisu změn v chatu)
