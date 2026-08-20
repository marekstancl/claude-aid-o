# AID — AI Development Orchestrator

## ⚠️ Infra context (eco-prod / eco-dev) — POVINNE PRECIST

**Production status:** ⚠️ **NENI AKTIVNI PRODUKCE.** Code je na eco-prod jako **mirror z migrace 2026-04-29**, ale klienti zadni, public URL neni v provozu. **Sousto je jediny live produkcni web** ekosystemu (soustonamiru.cz).

### Hosty

| Host | IP | Stav projektu zde |
|------|-----|-------------------|
| **eco-dev** | 10.20.20.22 | Active development testbed |
| **eco-prod** | 10.20.20.21 | Mirror code, **NE LIVE** (zatim) |
| pve-primary | 10.20.20.10 | Proxmox VM mgmt only, mimo MCP |

**Pristup:** WireGuard VPN `vulcan-home` na Macu → SSH `marekstancl@10.20.20.22` (dev) nebo `@10.20.20.21` (prod).

### Sdilena infra (na obou hostech)

| Sluzba | Container | Port |
|--------|-----------|------|
| PostgreSQL | `infra-postgres` | :5432 |
| Redis | `infra-redis` | :6379 |
| MinIO | `infra-minio` | :9000 |
| Nginx proxy | `infra-nginx` | :9080 |
| Cloudflare Tunnel | `infra-cloudflared` | (eco-prod, jen Sousto routovany) |
| LiteLLM AI Gateway | `svc-litellm` | :8830 |

### Development workflow

```bash
# Lokalne pres VPN
wg-quick up vulcan-home
ssh marekstancl@10.20.20.22

# Vyvoj
cd /opt/eco/projects/<projekt>
git checkout -b feature/...
docker compose up -d --build
docker compose logs -f
git push origin feature/...
gh pr create  # volitelne
```

### Deploy na "produkci" (= mirror update)

Pro tento projekt ZATIM **bez SLA** (NENI LIVE). Az se rozhodnes pustit live:

```bash
ssh marekstancl@10.20.20.21
cd /opt/eco/projects/<projekt>
git pull origin main
sudo docker compose down
sudo docker compose up -d --build
docker logs <container> --tail 50
```

### Observability (P045 EPIC 3, na eco-dev)

- **Grafana**: http://10.20.20.22:3803 (login v `services/.env` na eco-dev). 4 dashboards (eco-overview, eco-postgres, eco-host, eco-cost).
- **Loki logs**: pres Grafana Explore → Loki datasource. Query: `{container_id=~".*"} |= "<container-name>"`.
- **Telegram alerty**: `@eco_system_alerts_bot` → Marek DM (chat_id 1920844765). DM-only flow.

### Backups (P045 EPIC 4)

- Cron eco-prod 02:00 denne: GPG AES256 encrypted PG dump → `/opt/eco/data/backups/postgres/<projekt>-*.dump.gpg`
- Retention 30d, passphrase v `services/.env` (`BACKUP_GPG_PASSPHRASE`)
- Restore: `gpg --decrypt | docker exec -i infra-postgres pg_restore -U postgres -d <db>`

### Dokumentace (Docusaurus)

URL: http://10.20.20.22:3102 (eco-dev, VPN). Klicove sekce:

| Path | Pouziti |
|------|---------|
| `/ecosystem/operations/runbook` | Denni rutina, troubleshooting |
| `/ecosystem/operations/slo-matrix` | Tier 0/1/2 SLO definice + alert thresholds |
| `/ecosystem/operations/disaster-recovery` | Crash VM, HW fail, ransomware scenare |
| `/ecosystem/operations/backup-strategy` | 4 urovne backup, retention |
| `/ecosystem/operations/observability-design` | Grafana/Loki/vmalert architecture |
| `/ecosystem/operations/decision-log` | 18 P045 ADRs (D-060..D-078) |
| `/ecosystem/guardrails` | G-001 az G-020 |

---


## What is AID?

AID is a Claude Code plugin that implements **Controller + Workers architecture** for AI-driven software development. It takes an EPIC specification, generates structured execution plans, dispatches specialized role-based agents, enforces quality gates, and maintains complete evidence trails.

## Repository Structure

```
ai-orchestrator/
  .claude-plugin/
    marketplace.json            # Marketplace manifest
  plugins/aid-orchestrator/     # The plugin
    .claude-plugin/plugin.json  # Plugin manifest
    agents/                     # 9 controller agents (incl. simplifier + reporter plan-boundary specialists)
    commands/                   # 8 slash commands
    skills/                     # 8 core skills (+ extras outside manifest)
    scripts/                    # Bash controller layer
      aid-fsm.sh                # 6-state deterministic FSM
      aid-run-gates.sh          # Quality gate runner
      aid-release.sh            # Version bump + tag automation
      aid-auto-pipeline.sh      # Master orchestration (Plan → EPICs → plan.json → run → queue)
      aid-plan-to-epic.sh       # Plan.md → EPIC.md
      aid-epic-to-json.sh       # EPIC.md → plan.json
      aid-json-to-run.sh        # plan.json → run.md
      aid-queue-add.sh          # EPIC → queue entry
      lib/                      # aid-stage-log.sh, aid-token-count.sh, common.sh
      gates/scope-check.sh      # Scope validation gate
    defaults/                   # Files copied by /aid-init into target projects
      execution.yaml            # Gates + dispatch config
      orchestration.yaml        # Controller settings
      integrations.yaml         # External service config
      templates/                # plan.md, epic.md, plan.schema.json
    README.md                   # Plugin documentation
  CHANGELOG.md                  # Version history
```

## Plugin Installation

```bash
# Add marketplace
/plugin marketplace add marekstancl/claude-aid-o

# Install plugin
/plugin install aid-orchestrator@claude-aid-o

# Verify
/aid-help
```

## What the Plugin Creates in Target Projects

When users run `/aid-init`, it creates:

```
.aid-o/
  plans/             # PM + AI brainstorming → plans (archive/ for completed)
  tasks/             # PM + AI detail → EPIC specifications (archive/ for completed)
  config/            # PM-customizable (policies, templates, playbooks)
  work/              # AI internal (active, backlog, evidence, timeline)
```

## Key Commands

| Command | Purpose |
|---------|---------|
| `/aid-do [task]` | Fast Mode — implement small task with < 2 min overhead |
| `/aid-plan [topic]` | Brainstorm → architecture → plan.json |
| `/aid-run [id]` | Execute full pipeline: READY → EXECUTE → GATES → DONE |
| `/aid-status [id]` | Pipeline status, FSM state, queue |
| `/aid-init` | Initialize or upgrade .aid-o/ workspace (10-file structure) |
| `/aid-audit` | Run project health audit |
| `/aid-stop` | Emergency stop — save progress |
| `/aid-help [topic]` | Progressive help (Level 0–3) |

## Contributing

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
   be recorded in the enforcement registry (`docs/plans/AID-audit-2026-06/enforcement-registry.yaml`)
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
script bumps location 1 (root `CHANGELOG.md`) and, through its no-config fallback,
any other `CHANGELOG.md` it finds — which is location 2. Its `versioning.files[]`
loop never runs here, because that list lives in `.aid-o/config/project.yaml` and
this repo has none. **Locations 3-8 are edited by hand every release.**

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

<!-- AID-O START -->
## AID Orchestrator

This project uses AID v2.0 for multi-agent orchestration.

**Workspace:** `.aid-o/`
**Commands:** `/aid-help` for full documentation
**Quick start:** `/aid-init` → `/aid-plan "topic"` → `/aid-run`
**Fast mode:** `/aid-do "small task"` (< 2 min overhead)

**Key paths:**
- Plans: `.aid-o/plans/`
- Tasks: `.aid-o/tasks/`
- Config: `.aid-o/config/`
- Work: `.aid-o/work/`
<!-- AID-O END -->

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

## MCP Tools (G-020)

Globální (dostupné ve všech projektech přes ~/.claude/.mcp.json):
- `svc-mcp-tg-bot` — Telegram alerty (localhost:8817, replaces legacy shared-telegram per P032 v2.16.0; AID-internal alert tool, exposes `send_message` only)
- `qdrant-brain` — Osobní brain / marek-brain kolekce (localhost:8816)
- `shared-github` — GitHub API (localhost:8812)
- `shared-sequential-thinking` — Reasoning tool (localhost:8815)

Tento projekt nemá projekt-specifické MCP tools (dev-time tool, žádný přímý DB přístup).

ZAKÁZÁNO používat přímo (ops tools — jen na explicitní žádost uživatele):
- postgres-ops, docker, minio — full access k celé infra

## Ecosystem pravidla (závazná)

Tento projekt je součástí VULCAN ekosystému. Následující dokumenty jsou závazné:

- **Guardrails:** `/opt/eco/docs/docs/ecosystem/guardrails.md`
- **Architektonicka rozhodnuti:** `/opt/eco/docs/docs/ecosystem/decisions/`
- **Infrastruktura:** `/opt/eco/docs/docs/ecosystem/infrastructure/`
- **MCP Servery:** `/opt/eco/docs/docs/ecosystem/infrastructure/mcp-servers.md`
- **Ecosystem overview:** `/opt/eco/docs/docs/ecosystem/index.md`

Klíčová pravidla:
- G-008: Port rozsah 3910-3919, offset +1 = app (3911). Host port = interní port.
- G-009: docker-compose.yml pouze vlastní služby, shared-infra network external.
- G-015: Jeden Dockerfile (prod-ready), docker-compose.override.yml pro dev.
