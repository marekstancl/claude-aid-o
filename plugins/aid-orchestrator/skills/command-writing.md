---
name: command-writing
description: How to write and maintain AID slash-command files — accuracy-to-code contract, structure, freshness, and the no-fabrication rule
user_invocable: false
---

# Command Writing — Authoring and Maintaining AID Commands

**Last Updated:** 2026-06-03

How to create and maintain slash-command files (`commands/*.md`) for the AID
orchestrator plugin. Companion to `skill-writing.md` (skills) — commands are a
different file type with different failure modes, so they get their own standard.
This file obeys the rules it prescribes.

---

## Purpose

A command file is the **user-facing entry point** for a slash command. It is read
by the orchestrator LLM when the user types `/aid-x`, and it tells the LLM what to
do: which scripts to run, which agents to dispatch, which files to read and write.

Commands fail differently from skills. The P041 command audit found that the
dominant command defect is **doc-vs-code drift**: a command describes a CLI flag,
file name, state-file schema, or menu option that **does not exist** in the actual
scripts — and the orchestrator, trusting the command, executes a broken path. Three
shipped commands had real functional breaks from this (Level detection always 0,
resume saving to an unread file, a happy-path reading template instead of live
config). This standard exists primarily to make that class of defect impossible.

---

## When to Invoke

Invoke this skill when:
- Writing a new `commands/*.md` file.
- Substantially revising an existing command (>25% content change).
- Auditing a command (P041 or equivalent).
- A script's CLI/paths/schema change and a command references them.

Do NOT invoke for:
- Skill files (`skills/*.md`) — use `skill-writing.md`.
- Agent cards (`agents/*.md`) — use `agents/` conventions.

---

## The Cardinal Rule — Accuracy to Code

**A command MUST describe what the scripts, FSM, and skills ACTUALLY do — verified
against the source, not from memory.** This is the one non-negotiable command rule.

Before shipping or editing a command, every one of the following that appears in it
MUST be checked against the real artifact:

| Claim type | Verify against | Failure if unverified |
|------------|----------------|------------------------|
| CLI invocation (`script.sh --flag`) | the actual script's arg parser | Orchestrator runs a command that errors "unknown argument" |
| File path (read or written) | the script/FSM that owns it | Reads/writes the wrong or nonexistent file |
| State-file name | `aid-fsm.sh` (canonical: `fsm-state.yaml`, NOT legacy `state.yaml`) | Greps a file that doesn't exist → silent wrong result |
| Schema field (e.g. queue `epic_id`/`status`) | the writing script | Displays/queries fields that aren't there |
| Config location | runtime is `.aid-o/config/*.yaml`, NOT `defaults/*.yaml` (the template) | Reads template defaults instead of project config |
| Menu / option reference (e.g. "Option 6a") | the referenced command/skill | Dead instruction — user finds nothing |
| Function/contract cited from a skill | that skill | Fabricated contract |
| Tool name (MCP) | `integrations.yaml` (`qdrant-brain`, not bare `qdrant-store`) | Calls an unconfigured tool |

If a claim cannot be verified against source, it MUST NOT be stated as current
behavior. This is the planner.md/aid-stop.md lesson: a confidently-written
fictional contract is worse than an omission.

---

## Standard Structure

Commands are leaner than skills. Required sections in order:

| # | Section | Required? | Notes |
|---|---------|-----------|-------|
| 1 | YAML frontmatter | MUST | `description` (one line, what the command does) |
| 2 | H1 title + one-line purpose | MUST | |
| 3 | Arguments / invocation | MUST | flags + positional args, with "what each does" |
| 4 | What it does (numbered steps) | MUST | the orchestration the LLM performs |
| 5 | Reads / Writes | SHOULD | the **verified** files it touches (paths + owning script) |
| 6 | Relationship to FSM / skills | SHOULD | where the real enforcement lives (reference, don't restate) |
| 7 | **Last Updated** footer | MUST | bump on any content change |

Commands have NO `## MUST Rules` / `## Completeness Gate` section requirement
(those are skill-authoring constructs). A command's correctness gate is the
Cardinal Rule + the Completeness Gate below, run by the author/auditor.

---

## Length Guidelines

| Band | Lines | When |
|------|-------|------|
| **Thin shell** | 20–60 | Pure delegators (e.g. aid-audit → auditor.md) |
| **Standard** | 60–250 | Most commands |
| **Heavy** | 250–420 | Multi-mode orchestration commands (aid-run, aid-plan, aid-init) |

Over ~420 lines, the command is probably embedding script-internal detail that
belongs in a skill or the script header — extract it and reference. Observed:
aid-audit.md (29, thin) to aid-init.md (412, heavy-justified).

---

## Freshness Rules

- One `**Last Updated:** YYYY-MM-DD` footer (commands do not need the line-2 header
  stamp that skills require — they have no frontmatter-after-H1 convention).
- Bump whenever a step, path, flag, or referenced behavior changes. The P041 audit
  found ALL 10 commands stale (2026-03-xx) despite P040 content — a command that
  describes a feature added after its footer date is a freshness defect.
- A command that references a script changed since its footer date MUST be
  re-verified against that script (Cardinal Rule) before the next release.

---

## Forbidden Patterns

1. **Fabricated contracts** — CLI flags, functions, file schemas, or menu options
   that don't exist in source. (aid-research `/aid-setup Option 6a/6b`, aid-stop
   `session.*` schema, aid-run `DONE→ERROR` edge.)
2. **Legacy file names as canonical** — `state.yaml` where the FSM writes
   `fsm-state.yaml`; `defaults/x.yaml` where runtime reads `.aid-o/config/x.yaml`.
3. **Unenforced capabilities** — documenting a subcommand/feature no script
   implements (aid-status pause/resume/reorder). Either wire it, mark it
   `(planned — TRACKING-ID)`, or omit it. A documented-but-unbacked feature is a
   Principle-#1 violation (instruction without enforcement).
4. **Restated cross-file values** — gate counts, severity vocabularies, menus
   copied from another file drift. Reference the canonical file ("severity per
   `agents/auditor.md`"), don't restate the number/list.
5. **Version-stamped headings** — `### X (P040, v2.25.0+)`. Attribution goes in the
   body or CHANGELOG (same as skill-writing Forbidden Pattern #1).
6. **Raw dispatch logging** — a command that dispatches an `Agent()` MUST wrap it
   with `aid-emit-dispatch.sh start/complete` (which supports cp1–cp4 focuses), NOT
   raw `aid-stage-log.sh log_event`. The wrapper maintains the pending-dispatches
   ledger + agent_id enforcement; raw logging bypasses both.

---

## Completeness Gate

Run before shipping or marking a command ready.

```
COMMAND COMPLETENESS GATE:

ACCURACY-TO-CODE (the cardinal checks):
  1. Every CLI invocation verified against the script's arg parser?
  2. Every file path verified against the owning script (and using canonical
     names: fsm-state.yaml, .aid-o/config/)?
  3. Every schema field / status value matches the writing script?
  4. Every cross-command/skill reference (menu option, function, gate count)
     resolves to something that actually exists?
  5. Every MCP tool named per integrations.yaml (no bare qdrant-store/find)?

STRUCTURE:
  6. Frontmatter description present; arguments documented; steps numbered?
  7. Reads/Writes section lists only verified paths?

ENFORCEMENT INTEGRITY:
  8. No documented capability lacks a backing script (or it's marked planned w/ ID)?
  9. Any Agent() dispatch uses aid-emit-dispatch.sh, not raw log_event?

FRESHNESS:
  10. Footer date current; if a referenced script changed since, re-verified?

FORBIDDEN:
  11. Zero fabricated contracts, zero legacy-canonical file names, zero
      version-stamped headings, zero restated cross-file values?

EVALUATION: all pass or N/A-with-reason → ship. Any fail → fix first.
Checks 1–5 are the highest priority — they are the defect class that caused real
functional breaks in the P041 audit.
```

---

## Migration & Grandfathering

Commands authored before this standard's adoption are audited under relaxed
criteria: **structural** non-conformance (missing Reads/Writes section, footer-only
date) is advisory until the command undergoes substantive revision (>25% change).
But the **Cardinal Rule (accuracy-to-code, checks 1–5)** applies immediately to all
commands — a fabricated contract or wrong file name is a defect regardless of age,
because it actively breaks execution. New commands must pass the full gate.

(This explicit grandfathering on-ramp is the lesson from the skill-writing.md
external review: without it, the first audit floods the PM with structural noise.)

---

## Examples

### Good — verified Reads/Writes

```markdown
## Reads / Writes
- Reads: `.aid-o/config/integrations.yaml` (knowledge section) — runtime config,
  written by /aid-setup.
- Writes: knowledge chunks via `mcp__qdrant-brain__qdrant-store` (collection per
  integrations.yaml). Quality gates: see `skills/memory-mcp.md §Quality Gate`.
```
Every path/tool is the real one; the gate set is referenced, not restated.

### Bad — fabricated + legacy

```markdown
Read defaults/integrations.yaml, then call knowledge_research() per memory-mcp.md
and configure via /aid-setup Option 6a. Status is read from state.yaml.
```
Fails checks 1–5: `defaults/` is the template not runtime; `knowledge_research()`
doesn't exist; `Option 6a` doesn't exist; `state.yaml` is the legacy name.

---

## Reference Files

- `docs/plans/AID-audit-2026-06/skill-writing-PROVISIONAL.md` — sibling standard (skills)
- `docs/plans/AID-audit-2026-06/09-command-audit.md` — the audit that motivated this standard (cross-command patterns)
- `docs/plans/AID-audit-2026-06/03-governance-recommendation.md` — enforcement registry + type→home convention
- `plugins/aid-orchestrator/scripts/aid-fsm.sh` — canonical state-file (`fsm-state.yaml`), transitions, preconditions
- `plugins/aid-orchestrator/scripts/aid-emit-dispatch.sh` — the required dispatch wrapper
- `plugins/aid-orchestrator/CLAUDE.md §On Plugin Changes` — footer + CHANGELOG conventions

---

**Last Updated:** 2026-06-03
