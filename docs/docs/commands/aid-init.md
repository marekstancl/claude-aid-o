---
sidebar_position: 8
title: "/aid-init"
description: "Initialize or upgrade the .aid-o/ workspace structure"
---

# /aid-init

Initialize or upgrade the AID workspace (`.aid-o/`) in the current project. On a fresh project this creates the full directory structure, copies default configuration files, and sets up engine tracking files. On an existing workspace it detects the installed version, classifies each config file (new / upgradable / unchanged / custom / protected), and offers a safe upgrade.

## Usage

```bash
/aid-init [path]
/aid-init --upgrade     # Force upgrade mode
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | No | Base directory where `.aid-o/` is created. Defaults to the current working directory. |
| `--upgrade` | flag | No | Skip fresh-init detection and go directly to upgrade mode. |

## Examples

```bash
# Initialize in the current directory
/aid-init

# Initialize in a subdirectory
/aid-init ./my-project

# Initialize at an absolute path
/aid-init /opt/project

# Force upgrade (skip version check)
/aid-init --upgrade
```

## Mode Detection

When `/aid-init` runs, it automatically determines what to do:

| Condition | Mode |
|-----------|------|
| `.aid-o/` does not exist | Fresh init |
| `.aid-o/` exists, manifest present, versions match | Already up-to-date (no action) |
| `.aid-o/` exists, manifest present, versions differ | Upgrade mode |
| `.aid-o/` exists, no manifest | Legacy upgrade (bootstraps manifest, then upgrades) |

## Fresh Init

Creates the following directory structure:

```
.aid-o/
  01-plans/
    archive/
  02-epics/
    archive/
  03-config/
    policies/
    templates/
    playbooks/
  04-engine/
    runs/
      archive/
    memory/
    evidence/
  05-inputs/
```

Then:

- Copies all files from `defaults/policies/`, `defaults/templates/`, and `defaults/playbooks/` into `.aid-o/03-config/` (skips existing files — never overwrites)
- Creates engine tracking files: `memory/active-work.md`, `memory/project-profile.yaml`, `memory/decisions.yaml`, `backlog.md`, `lessons-learned.md`, `command-history.md`
- Copies `defaults/templates/inputs-readme.md` to `.aid-o/05-inputs/README.md`
- Generates `.aid-o/03-config/.aid-manifest.yaml` with version and file checksums
- Updates `CLAUDE.md` using marker-based merge (preserves existing content)

## Upgrade Mode

Upgrade mode classifies each config file before touching anything:

| Class | Meaning | Action |
|-------|---------|--------|
| `NEW` | File exists in new defaults but not in workspace | Copy to workspace |
| `UPGRADE` | File exists in workspace, checksum matches manifest (not modified by PM) | Replace with new defaults |
| `UNCHANGED` | File matches current defaults already | No action |
| `CUSTOM` | File exists in workspace, checksum differs (PM modified it) | Skip; list for manual review |
| `PROTECTED` | File has `custom: true` in manifest | Never touched |

You review the upgrade plan and approve before any files are changed.

## Protecting Files from Upgrade

Add `custom: true` to any file entry in `.aid-o/03-config/.aid-manifest.yaml` to permanently protect it from auto-upgrade:

```yaml
files:
  policies/gates.yaml:
    checksum: "abc123..."
    custom: true    # Never auto-upgraded
```

## CLAUDE.md Merge

`/aid-init` creates or updates `CLAUDE.md` using marker-based merge. It looks for `<!-- AID-O START -->` and `<!-- AID-O END -->` markers and replaces only the content between them — all other content in `CLAUDE.md` is preserved exactly.

## Notes

- Fresh init **never overwrites** existing files
- Upgrade mode **respects PM customizations** — only replaces files that match the manifest checksum (meaning you have not modified them)
- Config file scanning is dynamic — new files added to plugin defaults are automatically included in future upgrades without hardcoding

## Related

- [`/aid-setup`](./aid-setup) — interactive project onboarding (runs after init)
- [`/aid-help`](./aid-help) — AID documentation and help topics
