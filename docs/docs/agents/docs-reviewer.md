---
sidebar_position: 7
title: "Docs Reviewer Agent"
description: "Review documentation changes for compliance, frontmatter, and completeness."
---

# Docs Reviewer Agent

The Docs Reviewer agent checks all changed documentation files for compliance with the project's documentation standards. It adapts its checks based on the documentation platform detected in `project-profile.yaml` and loads the appropriate platform playbook.

## Role

The Docs Reviewer is a **specialist agent** used during gate checks. It scopes its review to files changed in the current diff, not the entire documentation set. It does not modify files — it produces a structured review report with pass/fail results per file.

## When Dispatched

- During gate checks for documentation files
- When the Controller needs to validate documentation compliance for changed files
- Typically runs after the Docs Writer agent completes a documentation step

## Capabilities

- **YAML Frontmatter validation** — when `project.docs.frontmatter_required == true` (Docusaurus, VitePress), checks that every documentation file has correct frontmatter per the platform playbook
- **MDX format rules** — for Docusaurus projects: verifies `{braces}` in prose are in backticks, `<` in comparisons use `&lt;` or prose equivalents, JSX-like tags are valid, Mermaid blocks use the correct fence
- **Standard Markdown rules** — for MkDocs, VitePress, and generic Markdown projects
- **Mermaid diagram validation** — valid syntax, no unclosed brackets, direction specified
- **Internal link verification** — relative paths to other docs exist, no absolute local paths, no broken anchor links
- **Navigation/sidebar configuration** — for Docusaurus checks `sidebars.js` ID-to-path consistency; for MkDocs checks `mkdocs.yml` `nav:` section; for VitePress checks sidebar config
- **Date currency** — `last_updated` fields should reflect today's date on actively modified files

## Tools Available

Standard Claude Code tools. Reads `project-profile.yaml` to determine the documentation platform. Reads changed files identified by `git diff --name-only`. Does not modify any files.

## Key Behaviors

- **Scope is limited to changed files only.** Runs `git diff --name-only` to identify them, then filters for documentation files in the detected docs path.
- **Workspace files, skill files, and plugin files do not need documentation frontmatter.** These are skipped.
- **Adapts to the detected platform.** Reads `defaults/playbooks/docs-{platform}.md` for platform-specific standards.
- **Produces a structured report** with PASS/FAIL per check per file and an overall PASS/FAIL verdict.
- Issues include file:line references for precision.

## Related

- [Docs Writer Agent](./docs-writer)
- [Quality Gates](../skills/quality-gates)
- [Gates Engine Skill](../skills/gates-engine)
