---
name: aid-init
description: Initialize or upgrade .aid-o/ workspace structure
user_invocable: true
---

Initialize or upgrade AID workspace (`.aid-o/`) in the current project.

This command creates the recommended workspace structure and copies default configuration files from the plugin's `defaults/` directory. When run on an existing workspace, it detects the installed version, identifies new and updated files, respects PM customizations, and offers a safe upgrade.

## Usage

```
/aid-init [path]
/aid-init --upgrade     # force upgrade mode (skip init, go straight to upgrade)
```

`[path]` is optional. When provided, it sets the base directory where `.aid-o/` is created instead of the current working directory.

### Examples

```
/aid-init                        # create .aid-o/ in current directory
/aid-init ./subdir               # create .aid-o/ in a relative subdirectory
/aid-init /opt/project           # create .aid-o/ in an absolute path
```

When `[path]` differs from the current working directory, `CLAUDE.md` is created at `{path}/CLAUDE.md` rather than in the current directory.

## Mode Detection

When `/aid-init` runs, it determines the mode automatically:

1. **If `.aid-o/` does not exist** → **Fresh Init** (create workspace from scratch)
2. **If `.aid-o/` exists AND `.aid-o/03-config/.aid-manifest.yaml` exists** → check version:
   - Plugin version == manifest version → **Already Up-to-Date** (report and exit)
   - Plugin version != manifest version → **Upgrade Mode**
3. **If `.aid-o/` exists AND `.aid-manifest.yaml` does NOT exist** → **Legacy Upgrade** (create manifest from current state, then run upgrade)

Read the plugin version from `plugin.json` (`"version"` field) in the plugin's `.claude-plugin/` directory.

---

## Fresh Init

Runs when `.aid-o/` does not exist (or `--upgrade` not passed on a fresh project).

### Directory Structure

Create the following directories (skip if they already exist):

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

### Config Files (Dynamic Scan)

**Scan** the plugin's `defaults/` directory for all files in these subdirectories:
- `defaults/policies/*`
- `defaults/templates/*`
- `defaults/playbooks/*`

For **each file found**, copy it to the corresponding path under `.aid-o/03-config/`. Do NOT hardcode the file list — scan dynamically so new defaults are automatically included in future versions.

**Important:** Do NOT overwrite existing files during fresh init — if a file already exists, skip it and note "already exists" in the output.

### Engine Files

Create these empty tracking files in `.aid-o/04-engine/` (skip if they already exist):

| File | Initial Content |
|------|----------------|
| `memory/active-work.md` | `# Active Work\n\n_Initialized by /aid-init_\n\n## Current Focus\n\n_No active work_\n\n## Context for Next Run\n\n## Recent Work\n\n## Next Steps\n\n## Blockers` |
| `memory/project-profile.yaml` | `# Project Profile\n# Auto-populated by /aid-setup or Project Scanner agent\n\nproject_name: ""\ntech_stack: {}\narchitecture: ""\ninitialized: false` |
| `memory/decisions.yaml` | `# Key Decisions\n# ADR-lite format — recorded by Orchestrator\n\ndecisions: []` |
| `backlog.md` | See **Backlog Template** below |
| `lessons-learned.md` | `# Lessons Learned\n\n| Date | Lesson | Context |\n|------|---------|---------|` |
| `command-history.md` | `# Command History\n\n| Command | Purpose | Verified |\n|---------|---------|----------|` |
| `evidence/.gitkeep` | _(empty file)_ |

### Backlog Template

The `backlog.md` file uses categorized sections for different proposal types.
**Source values:** `user` (submitted by PM), `agent` (discovered by AI agent during EPIC),
`curator` (proposed by Curator post-processing), `audit` (found by Auditor).

Initial content for `backlog.md`:

```markdown
# AID Backlog

_Managed by AID Curator agent. Source: user | agent | curator | audit_

## Active Proposals

### Bugs
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Features
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Refactoring / Tech Debt
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

### Performance
| ID | Priority | Source | Summary | Epic |
|----|----------|--------|---------|------|

## Deferred
| ID | Type | Priority | Source | Summary | Reason |
|----|------|----------|--------|---------|--------|

## Rejected
| ID | Type | Source | Summary | Reason |
|----|------|--------|---------|--------|

## Implemented
| ID | Type | Source | Summary | Implemented In |
|----|------|--------|---------|----------------|
```

### Input Files

Copy the inputs README template into the `05-inputs/` directory (skip if it already exists):

```
Copy defaults/templates/inputs-readme.md → .aid-o/05-inputs/README.md
```

### Generate Manifest

After all files are created/copied, generate `.aid-o/03-config/.aid-manifest.yaml`:

```yaml
# AID Config Manifest — tracks installed defaults for upgrade detection
# Generated by /aid-init — do not edit manually

plugin_version: "{version from plugin.json}"
installed_at: "{ISO 8601 timestamp}"
upgraded_at: null

files:
  # Each file: relative path from 03-config/ → md5 checksum at install time
  # Files marked custom: true are never auto-upgraded
  policies/gates.yaml:
    checksum: "{md5}"
  policies/decision-policies.yaml:
    checksum: "{md5}"
  # ... (one entry per file copied from defaults/)
```

**Checksum computation:** For each file copied, compute `md5sum` of the file content and store as `checksum`. This enables upgrade mode to detect whether PM has modified the file since installation.

### CLAUDE.md Update

Update CLAUDE.md using the marker-based merge described in the **CLAUDE.md Marker-Based Merge** section below.

### Fresh Init Output

```
AID Workspace Initialized (.aid-o/)
====================================

Directories:
  [CREATED] .aid-o/01-plans/
  [CREATED] .aid-o/01-plans/archive/
  ...

Config files (.aid-o/03-config/):
  [CREATED] policies/gates.yaml
  [CREATED] policies/decision-policies.yaml
  ...
  ({N} files from plugin defaults)

Engine files (.aid-o/04-engine/):
  [CREATED] memory/active-work.md
  [CREATED] backlog.md
  ...

Input files (.aid-o/05-inputs/):
  [CREATED] README.md

Manifest: .aid-o/03-config/.aid-manifest.yaml (v{version})

CLAUDE.md:
  [CREATED] CLAUDE.md

Summary: {N} created, {M} already existed

Next steps:
  1. Run /aid-setup for interactive project onboarding
  2. Customize .aid-o/03-config/policies/ for your project
  3. Create your first Plan in .aid-o/01-plans/
```

---

## Upgrade Mode

Runs when `.aid-o/` exists and the plugin version differs from the manifest version.

### Step 1: Read Manifest

1. Read `.aid-o/03-config/.aid-manifest.yaml`
2. Extract `plugin_version` (installed version) and `files` (checksums)
3. Read current plugin version from `plugin.json`
4. Present to PM:
   ```
   AID Upgrade Available
   ====================================
   Installed: v{manifest.plugin_version}
   Available: v{plugin_version}

   Analyzing config files...
   ```

### Step 2: Classify Files

For each file in `defaults/{policies,templates,playbooks}/*`:

1. **Compute** the relative path (e.g., `policies/gates.yaml`)
2. **Check** if the file exists in `.aid-o/03-config/`:

**Case A: File does NOT exist in .aid-o/** → classify as `NEW`

**Case B: File exists in .aid-o/ AND is in manifest:**
1. Compute current md5 of the file in `.aid-o/03-config/`
2. Compare with `checksum` stored in manifest:
   - **Checksums match** (PM did not modify) → classify as `UPGRADABLE`
   - **Checksums differ** (PM customized) → classify as `CUSTOM`
3. If file has `custom: true` in manifest → classify as `PROTECTED` (regardless of checksum)

**Case C: File exists in .aid-o/ BUT NOT in manifest** (legacy or manually added):
1. Compare content with the CURRENT defaults file:
   - **Identical** → classify as `UPGRADABLE` (happens to match defaults, safe to track)
   - **Different** → classify as `CUSTOM` (assume PM modified, be safe)

Additionally, for `UPGRADABLE` files, check if the defaults file actually changed:
- Compute md5 of the NEW defaults file
- If new defaults checksum == manifest checksum → classify as `UNCHANGED` (no update needed)
- If different → remains `UPGRADABLE`

### Step 3: Present Upgrade Plan

Show PM the classified file list and ask for approval:

```
Upgrade Plan (v{old} → v{new})
====================================

[NEW]        policies/dispatch-strategy.yaml
[NEW]        playbooks/e2e.md
[NEW]        playbooks/docs-docusaurus.md
[UPGRADE]    playbooks/architect.md
[UPGRADE]    playbooks/backend.md
[UPGRADE]    templates/epic.md
[UNCHANGED]  policies/decision-policies.yaml
[UNCHANGED]  templates/plan.md
[PROTECTED]  policies/gates.yaml (marked custom — never auto-upgraded)
[CUSTOM]     policies/memory-config.yaml (locally modified)

Actions:
  NEW:        {N} files will be added
  UPGRADE:    {N} files will be replaced with new defaults
  UNCHANGED:  {N} files already match (no action)
  PROTECTED:  {N} files explicitly protected (no action)
  CUSTOM:     {N} files locally modified (skipped — review manually)

Proceed? (Y/N/Review)
```

**If PM says "Review":** For each `CUSTOM` file, show a brief diff summary (lines added/removed/changed) and ask per-file: "(U)pgrade anyway / (S)kip / (M)ark as protected"

### Step 4: Execute Upgrade

**For NEW files:** Copy from defaults to `.aid-o/03-config/`
**For UPGRADABLE files:** Replace content from defaults
**For UNCHANGED files:** No action
**For PROTECTED files:** No action
**For CUSTOM files (default):** No action; list them in post-upgrade summary for manual review

After all file operations:
1. Recompute checksums for all files in `.aid-o/03-config/`
2. Update `.aid-manifest.yaml`:
   - Set `plugin_version` to new version
   - Set `upgraded_at` to current timestamp
   - Update all `checksum` values
   - Preserve `custom: true` flags
   - Add entries for newly added files
3. Run CLAUDE.md marker-based merge (in case the AID section template changed)

### Step 5: Upgrade Output

```
AID Workspace Upgraded (v{old} → v{new})
====================================

Config files (.aid-o/03-config/):
  [NEW]        policies/dispatch-strategy.yaml
  [NEW]        playbooks/e2e.md
  [UPGRADED]   playbooks/architect.md
  [UPGRADED]   templates/epic.md
  [UNCHANGED]  policies/decision-policies.yaml
  [PROTECTED]  policies/gates.yaml
  [CUSTOM]     policies/memory-config.yaml (review manually)

Manifest: .aid-o/03-config/.aid-manifest.yaml (v{new})

Summary: {N} new, {U} upgraded, {X} unchanged, {P} protected, {C} custom (skipped)

{if C > 0:}
Review these locally-modified files against new defaults:
  policies/memory-config.yaml
  Tip: diff .aid-o/03-config/policies/memory-config.yaml <plugin-defaults-path>/policies/memory-config.yaml
{end if}
```

---

## Legacy Upgrade

Runs when `.aid-o/` exists but `.aid-manifest.yaml` does NOT exist (pre-manifest workspace).

### Step 1: Bootstrap Manifest

1. Scan all files in `.aid-o/03-config/{policies,templates,playbooks}/`
2. For each file, compute md5 checksum
3. Compare each file with the CURRENT defaults:
   - If identical → record as default (safe to upgrade in future)
   - If different → record as custom (PM may have modified)
4. Write `.aid-manifest.yaml` with `plugin_version: "unknown"` and computed checksums
5. Present:
   ```
   Legacy workspace detected (no manifest).
   Created .aid-manifest.yaml from current state.

   Files matching defaults: {N} (safe to upgrade)
   Files differing from defaults: {M} (assumed customized)
   Missing from workspace: {K} (will be added)
   ```

### Step 2: Run Normal Upgrade

Proceed with Upgrade Mode Step 2-5 using the bootstrapped manifest.

**Important:** Since the old version is "unknown", ALL defaults files that differ will be treated as potentially customized. This is the safe/conservative path — PM can override per-file during review.

---

## Marking Files as Custom

PM can manually protect files from auto-upgrade by adding `custom: true` in the manifest:

```yaml
files:
  policies/gates.yaml:
    checksum: "abc123..."
    custom: true    # ← PM adds this to protect from auto-upgrade
```

Or during upgrade review (Step 3 "Review" option), PM can mark individual files as protected.

---

## CLAUDE.md Marker-Based Merge

Step 5 (fresh init) or Step 4 (upgrade) handles creating or updating `CLAUDE.md` in the project root so that AID information is always present and up to date, without destroying any user-written content.

### Markers

The AID section is delimited by exactly these HTML comment markers:

```
<!-- AID-O START -->
<!-- AID-O END -->
```

### AID Section Content

The full block (including markers) that is written:

```markdown
<!-- AID-O START -->
## AID Orchestrator

This project uses AID for multi-agent orchestration.

**Workspace:** `.aid-o/`
**Commands:** `/aid-help` for full documentation
**Quick start:** `/aid-setup` → create EPIC → `/aid-run-epic`

**Key paths:**
- Plans: `.aid-o/01-plans/`
- EPICs: `.aid-o/02-epics/`
- Config: `.aid-o/03-config/`
- Engine: `.aid-o/04-engine/`
<!-- AID-O END -->
```

### Merge Logic

1. **Generate** the AID section content (the block above).
2. **Check** if `CLAUDE.md` exists in the project root.
3. **If CLAUDE.md exists:**
   a. Read the entire file content.
   b. Search for `<!-- AID-O START -->` and `<!-- AID-O END -->` markers.
   c. **If both markers are found:** replace everything from `<!-- AID-O START -->` through `<!-- AID-O END -->` (inclusive) with the new AID section content. All content before and after the markers is preserved exactly as-is.
   d. **If markers are NOT found:** append a blank line followed by the AID section content at the end of the file.
   e. Log `[UPDATED] CLAUDE.md (markers replaced)` or `[UPDATED] CLAUDE.md (section appended)`.
4. **If CLAUDE.md does not exist:**
   a. Create `CLAUDE.md` with the AID section content as its sole content.
   b. Log `[CREATED] CLAUDE.md`.

---

## Implementation Steps (Summary)

### Fresh Init
1. Determine the plugin's `defaults/` directory location (relative to this command file: `../defaults/`)
2. Create directory structure (skip existing, includes `05-inputs/`)
3. **Scan** `defaults/{policies,templates,playbooks}/*` for all files (dynamic, not hardcoded)
4. Copy each file to `.aid-o/03-config/` (skip existing)
5. Create engine files (skip existing)
6. Copy `defaults/templates/inputs-readme.md` to `.aid-o/05-inputs/README.md` (skip if exists)
7. **Generate `.aid-manifest.yaml`** with version and checksums
8. Update CLAUDE.md (marker-based merge)
9. Print summary

### Upgrade
1. Read manifest and plugin version
2. Scan defaults, classify each file (NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED)
3. Present upgrade plan to PM, ask for approval
4. Execute: copy NEW, replace UPGRADABLE, skip rest
5. Update manifest (new version, new checksums)
6. Update CLAUDE.md (marker-based merge)
7. Print summary with review hints for CUSTOM files

---

## Important

- **Fresh init NEVER overwrites** existing files
- **Upgrade mode respects PM customizations** — only replaces files whose checksums match the manifest (PM didn't touch them)
- **Protected files** (`custom: true` in manifest) are NEVER auto-upgraded
- **Dynamic file scanning** — do not hardcode the defaults file list; scan `defaults/` directories so new files in future versions are automatically picked up
- If `$ARGUMENTS` contains a path, use that as the target directory instead of current directory
- After initialization, remind the user to customize `03-config/policies/` files for their project
- Naming conventions: Plans `P{NNN}`, Epics `E-{NNN}-{phase}_{total}`, Runs `R-{EPIC_ID}-{run_number}` (see `skills/epic-orchestration.md` ID Generation)
