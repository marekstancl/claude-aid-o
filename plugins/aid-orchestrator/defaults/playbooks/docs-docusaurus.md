# Docusaurus Documentation Playbook

> Loaded when `project.docs.platform == docusaurus`. Contains platform-specific rules
> for Docusaurus projects. Generic docs responsibilities are in `playbooks/docs.md`.

## File Format

- Preferred: `.mdx` (supports JSX components in docs)
- Also supported: `.md` (standard Markdown)
- Documentation root: `{project.docs.path}` (default: `docs/`)

## Frontmatter Requirements

Every documentation file in `{project.docs.path}` MUST have YAML frontmatter:

```yaml
---
title: "Page Title"
sidebar_label: "Short Label"
last_updated: "YYYY-MM-DD"
status: draft|review|published
audience: developer|pm|user
complexity: beginner|intermediate|advanced
---
```

**Required fields:** `title`, `sidebar_label`, `last_updated`
**Optional but recommended:** `status`, `audience`, `complexity`

## MDX Escaping Rules

MDX is stricter than Markdown — these cause build failures if not followed:

- `{braces}` in prose text MUST be in backticks: `` `{braces}` ``
- `<` in comparisons MUST use `&lt;` or the word "under" / "less than"
- JSX-like tags (`<Component>`) MUST be valid JSX or escaped
- Mermaid code blocks MUST use ` ```mermaid ` fence (not inline)

## Sidebar Configuration

If `sidebars.js` (or `sidebars.ts`) is modified:
- Document IDs must match file paths (no numeric prefix, no `.md` extension)
- Category structure should be logical and match directory layout
- No orphaned pages (every doc in `{project.docs.path}` should appear in sidebar)

## Build Verification

After writing or modifying docs, verify the build:

```bash
cd {project.docs.path}
npm run build
```

Exit code 0 = success. Any error (broken links, MDX parse failure, missing sidebar entry) must be fixed before committing.

## Quality Checklist

- [ ] Frontmatter present with required fields (`title`, `sidebar_label`, `last_updated`)
- [ ] MDX escaping correct (braces in backticks, `<` escaped, JSX tags valid)
- [ ] `last_updated` set to today's date on modified files
- [ ] No broken internal links (`[text](./relative-path.md)`)
- [ ] Build passes: `npm run build` in `{project.docs.path}` exits with code 0
- [ ] Sidebar entries present for new pages
