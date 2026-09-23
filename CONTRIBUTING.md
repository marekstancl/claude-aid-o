# Contributing to AID

The rules a change to this repository has to respect: what to update when the
plugin changes, how a release is cut, how the testbed and the test tiers work,
and where plugin issues reported by projects go. This file is public and is
what the enforcement registry cites; the private, machine-specific context for
Claude Code sessions lives in the untracked `CLAUDE.md` next to it.

## Ground rules

- **Language:** English for all plugin code and documentation
- **Plugin manifest:** `plugins/aid-orchestrator/.claude-plugin/plugin.json`
- **Testing:** Use `/plugin validate .` from repo root to validate marketplace

### AID Architecture Principles

Before introducing new detection capability into the plugin (compliance check,
gate, telemetry signal, audit field), consult
[`docs/plans/AID-v3-principles.md`](docs/plans/AID-v3-principles.md) for binding
architectural principles. Each detection capability MUST specify its enforcement
mechanism (FSM precondition / out-of-band hard fail / PM confirmation gate) at
design time, not "later". Principle #1 — *Detector without Enforcement is
Decoration* — is anchored to the P026 (WAN, 2026-05-13) incident where a
working detector flagged correctly but PM merged anyway because no enforcement
was wired.

This document governs aid-orchestrator-internal design work only. It is not
distributed with the plugin and does not bind consumer projects.

### On Plugin Changes — Mandatory Updates

When modifying plugin files (`plugins/aid-orchestrator/`), always update:

1. **CHANGELOG.md** — both root and `plugins/aid-orchestrator/CHANGELOG.md` — **must be identical** (see format below)
2. **`Last Updated` date** — in modified skill files (footer `**Last Updated:** YYYY-MM-DD`)
3. **`defaults/` sync** — if defaults files changed, note in CHANGELOG; `.aid-o/` in target projects will catch up via `/aid-init` upgrade
4. **Authoring standards** — new or substantially-revised `skills/*.md` must follow
   `skills/skill-writing.md`; new/revised `commands/*.md` must follow `skills/command-writing.md`.
   The mechanical subset is enforced by `scripts/aid-lint-skill.sh`, run over every skill +
   command by `scripts/tests/test-skill-lint.sh` (part of the suite). New files must lint clean;
   pre-standard files are grandfathered (structural findings advisory) until substantively revised —
   when you bring one up to standard, remove it from the GRANDFATHERED list in that test.
5. **Register + document every enforcement** — any new detection capability (FSM precondition,
   structural check, gate, severity-routed compliance key, dispatch guard, policy toggle) MUST
   be recorded in the enforcement registry (`plugins/aid-orchestrator/defaults/enforcement-registry.yaml`)
   with its `type`/`source`/`instruction`/`severity`/`surface`, and its enforcement mechanism named
   at design time per [`docs/plans/AID-v3-principles.md`](docs/plans/AID-v3-principles.md) §1
   (*Detector without Enforcement is Decoration*). New contributor-facing reference: `docs/extending-aid.md`.

### CHANGELOG Format Standard

Both CHANGELOGs (`CHANGELOG.md` root and `plugins/aid-orchestrator/CHANGELOG.md`) follow [Keep a Changelog](https://keepachangelog.com/) with this entry format:

```
## [X.Y.Z] — YYYY-MM-DD

### Added
- **Feature Name** — description of what was added and why it matters

### Changed
- **Component Name** — what changed and the effect

### Fixed
- **Bug Name** — what was broken and how it was fixed

### Removed
- **Component Name** — what was removed and why
```

**Rules:**
- Every entry starts with `- **Bold Name** — description` (em dash, not colon)
- Description is one sentence, specific enough to understand without reading code
- No trailing Task/Issue IDs in entries (those belong in commit messages, not CHANGELOG)
- Group related changes into a single entry when they form one logical feature
- Root and plugin CHANGELOGs are **always identical** — write one, copy to the other
- Sections appear in order: Added → Changed → Fixed → Removed (omit empty sections)

### README Roadmap Update

When releasing a new version, update the `## Roadmap` section in root `README.md`:

```markdown
## Roadmap

- **vX.Y.Z** (current) — one-line summary of major features in this version
- **vA.B.C** — previous version summary
- ...
```

Keep the 3 most recent versions. Older versions are documented only in CHANGELOG.

## Version Management

### Single Source of Truth

The **CHANGELOG header** (`## [X.Y.Z]`) is the single source of truth for the plugin version.
Individual skill/agent/command files do NOT contain version numbers — only `**Last Updated:**` dates.

### Version File Registry — the 8 release-boundary locations

Every push to main MUST ensure these 8 locations are in sync. **Seven of them
carry the version number; location 8 does not** — it is a fixed licence line in
the same README the release edits, and the checker asserts its PRESENCE, byte
for byte. It rides along in this registry so one release-boundary command covers
it; it can never "agree with" a version, because it holds none.

| # | File | Field | Update Method |
|---|------|-------|---------------|
| 1 | `CHANGELOG.md` | `## [X.Y.Z]` header | Manual (source of truth) |
| 2 | `plugins/aid-orchestrator/CHANGELOG.md` | `## [X.Y.Z]` header | Manual (copy of #1) |
| 3 | `.claude-plugin/marketplace.json` | `metadata.version` | JSON field |
| 4 | `.claude-plugin/marketplace.json` | `plugins[0].version` | JSON field |
| 5 | `plugins/aid-orchestrator/.claude-plugin/plugin.json` | `version` | JSON field |
| 6 | `plugins/aid-orchestrator/README.md` | `- **Plugin:** X.Y.Z` | Regex |
| 7 | `README.md` | `- **vX.Y.Z** (current)` | Regex |
| 8 | `README.md` | `AGPL-3.0-only — see [LICENSE](LICENSE)` (no version — presence only) | Exact line |

This table is the human definition of the 8 locations;
`plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` carries its own
hard-coded copy of the same list and does **not** parse this file, so a location
added here must be added to the script by hand or it goes unchecked. There is no
`defaults/policies/release-policy.yaml` (an earlier version of this file cited
one that does not exist).

**What `aid-release.sh` covers, and what stays manual.** In *this* repository the
script bumps its version source, `plugin.json` (location 5), writes the entry into
root `CHANGELOG.md` (location 1), and then walks `versioning.files[]` in the tracked
`.aid-o/config/project.yaml`, which as of 2026-09-20 lists locations 2, 3 and 4
(plugin `CHANGELOG.md`, both `marketplace.json` fields). **Locations 6-8 — the two
README lines and the licence line — are edited by hand every release**, and the
checker below is what catches a hand that forgot. (An earlier version of this text
claimed the repo had no `project.yaml`; it does, and it has since P089.)

**Pre-push check (release boundary):** Before pushing a release, run the checker —
not a set of eyeball greps:
```bash
bash plugins/aid-orchestrator/scripts/tests/verify-version-files.sh <new_version> --baseline <old_version>
```
`<new_version>` is mandatory and `--baseline` is optional (it adds the "the
version actually moved" assertion). Three exits, and they are not the same thing:

- **0** — every check passed: the seven version-carrying locations all show
  `<new_version>`, the licence line is present, and both CHANGELOGs carry an
  identical entry for it.
- **1** — checks ran and something failed. One `FAIL:` line **per failed check**
  (not one line total), then an `OVERALL: FAIL — N check(s) failed` summary. Not
  every FAIL names a location: the two CHANGELOG sections differing, a missing
  CHANGELOG entry and the baseline assertion are checks about content, not about
  a registry row.
- **2** — usage error (no `<new_version>`, an unknown flag, an unreachable
  `--project-root`, or `jq` missing). Prints usage or an `ERROR:` line and **no
  `FAIL:` line at all** — nothing was checked, so nothing disagreed.

This is an **invocation-time, release-boundary** check, deliberately not a CI gate
and not a member of the test suite: the version-carrying locations legitimately
diverge in the middle of development, so a suite-wide run would fail every
non-release commit. Its logic is regression-tested in
`scripts/tests/bats/test-aid-release-seal.bats`; what is unenforced is that a
human runs it. Registered as `version_registry_sync` in the enforcement registry
with `severity: advisory`, which is what an unrun check is worth.

## Release Workflow

1. Write CHANGELOG entry in root `CHANGELOG.md` with new `## [X.Y.Z]` header
2. Copy entry to `plugins/aid-orchestrator/CHANGELOG.md` (must be identical)
3. Bump version in all 6 remaining files (#3-#8 from registry above)
4. Update root `README.md` Roadmap section (add new version line, move previous down)
5. Commit: `release: vX.Y.Z — one-line summary`
6. Tag: `git tag vX.Y.Z`
7. GitHub Release: `gh release create vX.Y.Z --title "vX.Y.Z — summary" --notes "{CHANGELOG section for this version}"`
8. Push: `git push && git push --tags`
9. **Update plugin in all projects** (see below)

### Plugin Update — MANDATORY after every push

After pushing to GitHub, update the plugin cache in every project that uses it:

```bash
# Step 1: Try the standard update command
claude plugin update aid-orchestrator@claude-aid-o

# Step 2: If step 1 reports "already at latest" but version is wrong, force-refresh:
git -C ~/.claude/plugins/marketplaces/claude-aid-o fetch origin && git -C ~/.claude/plugins/marketplaces/claude-aid-o reset --hard origin/main
```

Then restart Claude Code (close and reopen IDE/terminal) to load the new version.

**Why:** Claude Code caches plugins as shallow git clones in `~/.claude/plugins/marketplaces/`.
The `plugin update` command runs `git fetch` but may not update the working tree (known issue).
The force-refresh command resets the cached clone to match the remote.

**Verification:** After restart, run `/aid-help` and check the version matches.

## The testbed — `/opt/eco/projects/aid-testbed`

A separate, permanent project whose only reason to exist is to ask: **does AID
still do what it promised, on a repository it was NOT written against?**

Run it after any change that touches planning, gates or hooks:

```bash
/opt/eco/projects/aid-testbed/bin/verify.sh                    # deterministic, no API
/opt/eco/projects/aid-testbed/bin/verify.sh --live             # also what needs a real session
/opt/eco/projects/aid-testbed/bin/verify.sh --plugin <dir>     # a working tree instead of the install
```

**Why it is not more tests inside this repo.** The plugin's own suites are green
and all stop at the same boundary: none of them can watch a real project being
planned. The testbed is a real project with its own layout, its **own standards
map** and its own documentation surface (`prirucka/`, not `docs/`) — so anything
this repository's shape is baked into fails there and nowhere else. That is not
hypothetical: v2.88.1 existed because `aid-standards-map.sh` carried this
repository's path table, and v2.89.2 because `/aid-init` never created
`counter.yaml`, which only a project that had never had a plan could show.

**Half of its checks expect a REFUSAL.** `fixtures/plan-sabotaged.md` carries one
deliberate defect per mechanism, because a gate that never refuses anything is
indistinguishable from a gate that is not wired at all.

**It verifies the INSTALLED plugin by default**, not a working tree. What a user
runs is what is installed, and the two came apart once already: v2.89.0 was
pushed, tagged and released while the ACTIVE installed version was still 2.77.3,
so none of its hooks existed. The canary caught it; nothing else would have.

**`expected/fingerprint.yaml` is written BEFORE a run.** A verification that
decides afterwards what counts as success proves nothing. The same file carries
`known_findings` — defects the harness knows about and deliberately does not
fail on, because they are waiting for a decision and a harness that cries wolf
every run stops being read.

**What it cannot measure is printed on every run**, so absence is never mistaken
for a pass: a continuity capsule across a real compaction (a compaction cannot
be triggered on demand) and the subagent protocol notice reaching a real role
agent (the mechanism is measured, that delivery is not).

## Problémy pluginu hlášené projekty (aid-plugin-issues)

Každý projekt, který AID používá, má soubor `.aid-o/work/aid-plugin-issues.md`
(vzniká sám při `plan-start` a každém `init`; pravidla kdy a jak psát má v
hlavičce). Píší do něj agenti i controller, když se špatně chová **AID sám** –
ne projekt. Soubor projektu je jediný záznam: rozhodnutí se píše do něj.

**Přehled:** `bash bin/aid-plugin-issues-collect.sh` projde
`/opt/eco/projects/*/.aid-o/work/aid-plugin-issues.md` a vypíše body bez
rozhodnutí (HOTOVO / ZAMÍTNUTO / ČÁSTEČNĚ / UŽ ŘEŠENO) s číslem řádku. Nic
nezapisuje a nic nekopíruje; bod označený jen `PŘEVZATO` (starý sběr) je
pořád otevřený. Poslední roztřídění: `docs/plans/plugin-issues-triage-2026-09-23.md`.

**Postup:**
1. Každý bod ověřit v kódu a nechat nezávisle posoudit Codexem
   (reálná chyba / dokumentace / design / už opraveno).
2. Předložit PM lidsky: co se děje, možnosti, doporučení, proč – PM rozhodne.
   Nic nejde do backlogu bez tohoto popisu.
3. Schválené opravy: návrh → Codex → oprava → Codex → merge cesta (t0+t1) → vydání.
4. Výsledek dopsat pod bod v souboru projektu:
   `> **HOTOVO vX.Y.Z (datum):** co se změnilo` / `ZAMÍTNUTO:` proč /
   `NECHAT, ověřit <kdy>`. Soubor projektu je jeho záznam, nikdy se nemaže.
5. Designové body, které PM schválil odložit, dostanou řádek `IMP-NNN`
   v `.aid-o/work/backlog.md` s odkazem na projekt a číslo bodu.

## Conventions

### Test tiers (P081 — AID is the ecosystem pilot)

Binding source: `/ecosystem/specs/test-standard`
(`/opt/eco/docs/docs/ecosystem/specs/test-standard.md`).

Every test suite declares its tier in its leading comment block, once:

    #!/usr/bin/env bats
    # aid-tier: t1

| Tier | Cost per case | Whole-tier budget | When it runs |
|------|---------------|-------------------|--------------|
| `t0` | under 2 s     | under 2 min       | merge path (the pulse) |
| `t1` | under 30 s    | under 10 min      | merge path — this is what blocks a merge |
| `t2` | more, **or cross-component at any cost** | none | nightly, 21:00 UTC = 23:00 Prague |

Tier follows measured cost and scope — never importance, and never a wish to
avoid blocking. `aid-test-tier-assign.sh` proposes from measurements and
enforces the aggregate budgets by demoting; `aid-test-tier-lint.sh` enforces
that every suite carries exactly one tag, that no filename carries a plan
number, and that no tier is cheaper than its newest measurement supports.

A tag and not a `tests/t0|t1|t2/` directory: directories were costed at ≈420
literal path references (registry `test:` fields, catalog join keys, CI jobs,
gate commands). Re-open only with a plan that counts again.

A suite filename states its subject, never the plan that produced it.
Provenance goes in the header. `scripts/tests/tier-lint-allowlist.txt` holds
sanctioned exceptions and is currently empty.

The merge path is T0 + T1. The full portfolio runs nightly
(`.github/workflows/nightly-tests.yml`), writes
`/opt/eco/data/aid-nightly/aid-orchestrator/<date>.json`, reports red once with
a streak, and shows one line in `/aid-status`.

Cross-project ownership (from the standard, anchored here for the successor):
the project that owns the code owns its tests and its nightly hour. A
cross-project suite belongs to the project whose behaviour it asserts, not to
whoever wrote it.
