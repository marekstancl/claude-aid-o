---
sidebar_position: 5
title: "Code Style & Conventions"
description: "Markdown conventions for agents, commands, and skills — YAML conventions for config files — naming rules."
---

# Code Style and Conventions

AID's "code" is primarily Markdown (for agents, commands, skills, and playbooks) and YAML (for configuration files). Consistency in format makes the plugin easier to read, easier to extend, and more reliable for Claude to execute. This document covers every convention you need to follow.

## File Naming

All files in the plugin use **kebab-case** with no uppercase letters:

- Agents: `docs-writer.md`, `quality-gates-runner.md`, `gate-fixer.md`
- Commands: `aid-run-epic.md`, `aid-epic-queue.md`, `aid-plan-epic.md`
- Skills: `epic-orchestration.md`, `retry-engine.md`, `memory-mcp.md`
- Policies: `decision-policies.yaml`, `memory-config.yaml`, `slack-config.yaml`
- Templates: `run-new-feature.md`, `run-bug-fix.md`
- Playbooks: `docs-docusaurus.md`, `docs-generic.md`

Never use underscores, camelCase, or PascalCase in filenames. The sole exception is `README.md` and `CHANGELOG.md`, which are uppercase by universal convention.

## Markdown Conventions

### Heading Levels

Use heading levels consistently with their semantic meaning:

- `#` — file-level title only (one per file)
- `##` — major sections (Identity, Capabilities, Constraints, etc.)
- `###` — subsections within a major section
- `####` — only when a subsection itself needs sub-grouping (rare)

Never skip heading levels. Do not use `##` for emphasis inside prose — use `**bold**` instead.

### Horizontal Rules

Use `---` to separate major logical sections within a file. In agent files, every major section (`## Identity`, `## Capabilities`, `## Constraints — CRITICAL`, etc.) is preceded and followed by a horizontal rule. This matches the pattern established in the existing agent files:

```markdown
---

## Identity

...

---

## Capabilities
```

### Bold and Emphasis

- Use `**bold**` for key terms, agent names, important values, and non-negotiable rules.
- Use `_italic_` sparingly — only for genuine emphasis on a single word or short phrase.
- Never use bold for entire sentences. If a sentence needs that much emphasis, it belongs in a `## Important` section or a `:::warning` callout (in Docusaurus docs).

### Code Blocks

Use fenced code blocks with the appropriate language tag:

```markdown
\`\`\`yaml
key: value
\`\`\`

\`\`\`bash
/aid-init
\`\`\`

\`\`\`
# No language tag for plain text output or pseudocode
1. RECEIVE step_spec
2. READ playbook
\`\`\`
```

For inline code, use backticks: `` `allowed_paths` ``, `` `.aid-o/` ``, `` `/aid-help` ``.

### Lists

Use unordered lists (`-`) for sets of items where order does not matter. Use ordered lists (`1.`) for sequential steps or ranked priorities. Do not mix `*` and `-` within the same file — the convention throughout the plugin is `-`.

Indent nested list items with two spaces:

```markdown
- Parent item
  - Nested item
  - Another nested item
- Second parent item
```

### Tables

Tables use standard GFM (GitHub Flavored Markdown) format. Always include a header row and alignment row:

```markdown
| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | The agent role identifier |
| `model` | string | Claude model: `sonnet` or `opus` |
```

Align columns for readability when editing, but do not enforce exact column widths — that is fragile and hard to maintain.

### Em Dash

Use an em dash (`—`) rather than a hyphen (`-`) or double-hyphen (`--`) when separating a term from its description in list entries and header blocks:

```markdown
- **Feature Name** — description of what was added
**Role:** Design API contracts, event schemas, ADRs — never implement features.
```

This convention appears throughout the plugin in CHANGELOG entries, agent headers, and capability lists.

## Agent and Playbook Conventions

### Agent Frontmatter

The only frontmatter field in agent files is `model`. No other fields are used:

```yaml
---
model: sonnet
---
```

Do not add fields like `title`, `description`, or `sidebar_position` to agent files. Those belong only in the Docusaurus documentation pages under `docs/docs/`.

### `## Constraints — CRITICAL` Section

The constraints section heading must always be exactly `## Constraints — CRITICAL` (with the em dash, not a hyphen). The first sentence of the section must always be:

```markdown
These constraints are non-negotiable:
```

This phrasing is intentional and uniform across all agents. Do not paraphrase it.

### Workflow Code Block

The `## Workflow` section uses a plain (no language tag) fenced code block. The steps are numbered, and sub-steps are indented with spaces (not tabs):

```
1. RECEIVE step_spec from Orchestrator
2. READ your playbook (defaults/playbooks/{role}.md)
3. READ relevant context:
   - EPIC specification
   - Prior step outputs (from dependencies)
4. VALIDATE scope
5. EXECUTE task per playbook guidelines
6. VERIFY against acceptance_criteria
7. RECORD improvement_notes
8. OUTPUT step_output YAML block
```

### `**Last Updated:**` Footer

Every skill file (in `skills/`) must end with a `**Last Updated:** YYYY-MM-DD` footer. Update this date whenever you modify the skill. Agent, command, and playbook files do not include this footer — it is specific to skills.

```markdown
**Last Updated:** 2026-02-26
```

## YAML Conventions

### Indentation

Always use 2-space indentation. Never use tabs.

```yaml
gates:
  tests_pass:
    description: "All tests pass (unit + integration)"
    required: true
    command: "pytest -q --tb=short"
    timeout_seconds: 300
    pass_criteria: "exit code 0"
```

### Quoted Strings

Use double quotes for string values that contain special characters, template variables, or human-readable sentences. Leave simple identifiers and numbers unquoted:

```yaml
# Quoted — contains a sentence
description: "All tests pass (unit + integration)"
pass_criteria: "exit code 0"

# Quoted — contains template variable
message_template: |
  GATE FAILURE — Escalation to PM
  Gate: {gate_name}

# Unquoted — simple identifier or number
required: true
timeout_seconds: 300
strategy: fixed
```

### Comments

Use `#` comments to explain non-obvious configuration. Place the comment on the line above the key it describes, not inline, except for short clarifying notes:

```yaml
# After max_attempts failures, the Controller escalates to PM
escalation:
  method: "inline"
  message_template: |
    ...

# Budget constraints
budget:
  max_llm_cost_per_epic_usd: 50
  warn_at_percentage: 80    # warn when 80% of budget is consumed
```

### Section Separators

For long YAML files with multiple logical sections, use a comment separator line to improve scanability:

```yaml
# ─── Quality Thresholds ─────────────────────────────────────────────
quality_thresholds:
  min_test_coverage_percent: 80

# ─── Auto-Decisions (Controller decides without PM) ─────────────────
auto_decisions:
  - condition: "all gate results = pass"
```

This style appears in `decision-policies.yaml` and should be followed in any new policy file with multiple logical sections.

### Null Values

Use `~` (YAML null) rather than `null` or leaving the key empty:

```yaml
upgraded_at: ~
active_epic: ~
```

## Naming Conventions for IDs

| Entity | Convention | Example |
|--------|------------|---------|
| EPIC ID | `E-{NNN}-{phase}_{total}` | `E-007-2_2` |
| Plan ID | `P{NNN}` | `P042` |
| Run ID | `R-{EPIC_ID}-{run_number}` | `R-005-1_4-1` |
| Branch name | `run/YYYY-MM-DD-{topic}` | `run/2026-02-26-user-auth` |
| Git commit type | conventional commit types | `feat`, `fix`, `docs`, `chore` |

These conventions are defined in `skills/epic-orchestration.md` and `skills/agent-core.md`. Follow them exactly when referencing IDs in documentation.

## Documentation Pages (Docusaurus)

Pages in `docs/docs/` are Docusaurus Markdown and require frontmatter with `sidebar_position`, `title`, and `description`:

```yaml
---
sidebar_position: 2
title: "Architect Agent"
description: "Design API contracts, event schemas, ADRs, and module boundaries."
---
```

- `sidebar_position` is a positive integer. Lower numbers appear higher in the sidebar. Use the next available integer within the section.
- `title` is the page title shown in the sidebar and as the browser tab title. Use sentence case, not title case, unless the title is a proper noun or command name.
- `description` is used for SEO meta and page previews. Keep it under 160 characters.

Do not add frontmatter to plugin source files (agents, commands, skills) beyond what those files already use — frontmatter in those files is for Claude Code, not Docusaurus.
